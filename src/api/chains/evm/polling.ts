import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  ApiBalanceBySlug,
  ApiChain,
  EVMChain,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { parseAccountId } from '../../../util/account';
import { getActivityTokenSlugs } from '../../../util/activities';
import { getChainConfig, getSupportedChains } from '../../../util/chain';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { getChainBySlug } from '../../../util/tokens';
import { NftStream } from './util/nftStream';
import { getAlchemySocket } from './util/socket';
import { fetchStoredWallet } from '../../common/accounts';
import {
  activeNftTiming,
  activeWalletTiming,
  inactiveWalletTiming,
} from '../../common/polling/utils';
import { swapReplaceActivities } from '../../common/swap';
import { sendUpdateTokens } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { FIRST_TRANSACTIONS_LIMIT, MINUTE, SEC } from '../../constants';
import { getTokenActivitySlice } from './activities';
import { fetchAccountAssets, fetchCrosschainAccountAssets, getIsWalletActive } from './wallet';

const activeEvmWalletTiming = {
  ...activeWalletTiming,
  forcedPollingPeriod: { focused: 3 * MINUTE, notFocused: 10 * MINUTE },
};

const inactiveEvmWalletTiming = {
  ...inactiveWalletTiming,
  forcedPollingPeriod: { focused: 10 * MINUTE, notFocused: 10 * MINUTE },
};

export function setupActivePolling<C extends EVMChain>(
  chain: C,
  accountId: string,
  account: ApiAccountWithChain<C>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
): NoneToVoidFunction {
  const { address } = account.byChain[chain];
  let markWalletActiveForBalancePolling: NoneToVoidFunction = () => {};

  const {
    scheduleCrossApiActivityCatchUp,
    cancelCrossApiActivityCatchUp,
  } = setupActivityPolling(
    chain, accountId, newestActivityTimestamps, onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
    () => markWalletActiveForBalancePolling(),
  );

  const nftPolling = getChainConfig(chain).isNftSupported
    ? setupNftPolling(chain, accountId, address, scheduleCrossApiActivityCatchUp, onUpdate)
    : undefined;

  const balancePolling = setupBalancePolling(
    chain,
    accountId,
    address,
    true,
    scheduleCrossApiActivityCatchUp,
    cancelCrossApiActivityCatchUp,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'balance'),
  );
  markWalletActiveForBalancePolling = balancePolling.markWalletActiveAndForcePoll;

  return () => {
    nftPolling?.stop();
    balancePolling.stop();
  };
}

const BALANCE_ACTIVITY_CATCH_UP_ATTEMPTS = 60;

function setupActivityPolling(
  chain: EVMChain,
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: (isUpdating: boolean) => void,
  onActivityDetected: NoneToVoidFunction,
): {
    scheduleCrossApiActivityCatchUp: (source: 'socket' | 'poll') => void;
    cancelCrossApiActivityCatchUp: NoneToVoidFunction;
  } {
  const initialTimestamps = compact(Object.values(newestActivityTimestamps));
  let newestConfirmedActivityTimestamp = initialTimestamps.length ? Math.max(...initialTimestamps) : undefined;

  let lastEmptyTimestamp: number | undefined;
  let balanceCatchUpGeneration = 0;

  async function rawUpdate(): Promise<boolean> {
    if (newestConfirmedActivityTimestamp !== undefined && newestConfirmedActivityTimestamp === lastEmptyTimestamp) {
      return false;
    }

    onUpdatingStatusChange(true);

    try {
      if (newestConfirmedActivityTimestamp === undefined) {
        const result = await loadInitialActivities(chain, accountId, onUpdate);
        const timestamps = compact(Object.values(result));

        newestConfirmedActivityTimestamp = timestamps.length ? Math.max(...timestamps) : undefined;
        if (timestamps.length) {
          onActivityDetected();
        }

        return timestamps.length > 0;
      } else {
        const result = await loadNewActivities(chain, accountId, newestConfirmedActivityTimestamp, onUpdate);
        const newTimestamps = compact(Object.values(result));

        if (newTimestamps.length && Math.max(...newTimestamps) > newestConfirmedActivityTimestamp) {
          newestConfirmedActivityTimestamp = Math.max(newestConfirmedActivityTimestamp, Math.max(...newTimestamps));
          onActivityDetected();
          return true;
        }

        lastEmptyTimestamp = newestConfirmedActivityTimestamp;

        return false;
      }
    } catch (err) {
      logDebugError(`EVM:${chain} setupActivityPolling`, err);
      return false;
    } finally {
      onUpdatingStatusChange(false);
    }
  }

  function scheduleCrossApiActivityCatchUp(source: 'socket' | 'poll') {
    balanceCatchUpGeneration += 1;
    const generation = balanceCatchUpGeneration;

    void (async () => {
      for (let attempt = 0; attempt < BALANCE_ACTIVITY_CATCH_UP_ATTEMPTS; attempt++) {
        if (generation !== balanceCatchUpGeneration) {
          return;
        }
        lastEmptyTimestamp = undefined;
        const found = await rawUpdate();

        if (source === 'poll') {
          return;
        }

        if (found) {
          return;
        }
        if (newestConfirmedActivityTimestamp === undefined) {
          return;
        }
        if (generation !== balanceCatchUpGeneration) {
          return;
        }

        await pause(SEC * 2);
      }
    })();
  }

  function cancelCrossApiActivityCatchUp() {
    balanceCatchUpGeneration += 1;
  }

  if (newestConfirmedActivityTimestamp === undefined) {
    scheduleCrossApiActivityCatchUp('poll');
  }

  return {
    scheduleCrossApiActivityCatchUp,
    cancelCrossApiActivityCatchUp,
  };
}

function setupNftPolling(
  chain: EVMChain,
  accountId: string,
  address: string,
  scheduleCrossApiActivityCatchUp: (source: 'socket' | 'poll') => void,
  onUpdate: OnApiUpdate,
) {
  const { network } = parseAccountId(accountId);

  const nftStream = new NftStream(chain, network, address, accountId, activeNftTiming);

  nftStream.onUpdate((params) => {
    if (params.direction === 'set') {
      onUpdate({
        type: 'updateNfts',
        accountId,
        nfts: params.nfts,
        chain,
        isFullLoading: params.isFullLoading,
        streamedAddresses: params.streamedAddresses,
      });
      if (!params.hasNewNfts) return;
    }
    if (params.direction === 'send') {
      onUpdate({
        type: 'nftSent',
        accountId,
        chain,
        nftAddress: params.nftAddress,
        newOwnerAddress: params.newOwner,
      });
      scheduleCrossApiActivityCatchUp('socket');
    }
    if (params.direction === 'receive') {
      onUpdate({
        type: 'nftReceived',
        accountId,
        nft: params.nft,
        nftAddress: params.nft.address,
      });
      scheduleCrossApiActivityCatchUp('socket');
    }
  });

  return {
    stop() {
      nftStream.destroy();
    },
  };
}

function setupBalancePolling(
  chain: EVMChain,
  accountId: string,
  address: string,
  isActive: boolean,
  scheduleCrossApiActivityCatchUp: (source: 'socket' | 'poll') => void,
  cancelCrossApiActivityCatchUp: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);
  const checkIsWalletActive = async () => {
    return getIsWalletActive(network, chain, address);
  };

  const balanceStream = new BalanceStream({
    chain,
    wsClient: getAlchemySocket(network, chain),
    network,
    address,
    sendUpdateTokens: () => sendUpdateTokens(onUpdate),
    fallbackPollingOptions: isActive ? activeEvmWalletTiming : inactiveEvmWalletTiming,
    fetchBalancesCb: (...args) => fetchAccountAssets(chain, ...args),
    fetchCrosschainBalancesCb: fetchCrosschainAccountAssets,
    importUnknownTokens: undefined,
    loadingConcurrencyLimiter: undefined,
    ensureIsPollingNeeded: checkIsWalletActive,
  });

  balanceStream.onUpdate((balances, updateSource) => {
    const crosschainAssetsByChain = new Map<ApiChain, ApiBalanceBySlug>();

    const knownChains = getSupportedChains();

    for (const [slug, balance] of Object.entries(balances)) {
      const assetChain = getChainBySlug(slug);

      if (!knownChains.includes(assetChain)) {
        continue;
      }

      crosschainAssetsByChain.set(assetChain, {
        ...crosschainAssetsByChain.get(assetChain),
        [slug]: balance,
      });
    }

    for (const [assetChain, balances] of crosschainAssetsByChain.entries()) {
      onUpdate({
        type: 'updateBalances',
        accountId,
        chain: assetChain,
        balances,
      });
    }

    scheduleCrossApiActivityCatchUp(updateSource);
  });

  if (onUpdatingStatusChange) {
    balanceStream.onLoadingChange(onUpdatingStatusChange);
  }
  balanceStream.start();

  return {
    stop() {
      cancelCrossApiActivityCatchUp();
      balanceStream.destroy();
    },
    markWalletActiveAndForcePoll() {
      balanceStream.markWalletActiveAndForcePoll();
    },
  };
}

export function setupInactivePolling<C extends EVMChain>(
  chain: C,
  accountId: string,
  account: ApiAccountWithChain<C>,
  onUpdate: OnApiUpdate,
): NoneToVoidFunction {
  const { address } = account.byChain[chain];

  const balancePolling = setupBalancePolling(
    chain,
    accountId,
    address,
    false,
    () => {},
    () => {},
    onUpdate,
  );

  return balancePolling.stop;
}

async function loadInitialActivities(
  chain: EVMChain,
  accountId: string,
  onUpdate: OnApiUpdate,
): Promise<ApiActivityTimestamps> {
  try {
    const { network } = parseAccountId(accountId);
    const { address } = await fetchStoredWallet(accountId, chain);

    const { activities: rawActivities, hasMore: mainHistoryHasMore } = await getTokenActivitySlice(
      chain,
      network,
      address,
      undefined,
      undefined,
      undefined,
      FIRST_TRANSACTIONS_LIMIT,
    );

    // Merge cross-chain CEX swaps into the feed, the way TON/Solana/Tron do on initial load. The
    // on-chain leg of such a swap arrives here as a plain transfer; without this the live EVM feed
    // shows it un-merged until the user paginates deep enough to hit the shared history path
    // (`fetchPastActivities`), which already applies the same replacement.
    const activities = await swapReplaceActivities(accountId, rawActivities, undefined, true);

    activities
      .slice()
      .reverse()
      .forEach((activity) => {
        txCallbacks.runCallbacks(activity);
      });

    // Record the newest activity of every token slug, not just the native one. A token- or
    // swap-led wallet can have no native-coin activity on its first page, so a native-only marker
    // would stay unset and make every launch repeat the full initial fetch instead of an
    // incremental poll. An empty wallet still yields an empty `bySlug`, so the reducer's
    // empty-update guard short-circuits.
    const result: ApiActivityTimestamps = {};
    const bySlug: Record<string, ApiActivity[]> = {};
    for (const activity of activities) {
      for (const slug of getActivityTokenSlugs(activity)) {
        (bySlug[slug] ??= []).push(activity);
        result[slug] ??= activity.timestamp; // `activities` is sorted newest-first
      }
    }

    // `getActivityTokenSlugs` returns no slugs for NFT transfers, so a first page made entirely of
    // NFT activity leaves `result` empty and `newestConfirmedActivityTimestamp` stuck at `undefined`,
    // forcing every subsequent poll to repeat this expensive initial load. Stamp a native-token
    // fallback timestamp (without touching `bySlug`) so that doesn't happen, mirroring the
    // unconditional stamp in `loadNewActivities`.
    if (!Object.keys(result).length && activities.length) {
      result[getChainConfig(chain).nativeToken.slug] = activities[0].timestamp;
    }

    onUpdate({
      type: 'initialActivities',
      chain,
      accountId,
      mainActivities: activities,
      mainHistoryHasMore,
      bySlug,
    });

    return result;
  } catch (err) {
    // Ensure `areInitialActivitiesLoaded[chain] = true` even on failure so
    // `waitInitialActivityLoading` unblocks and other chains stay visible.
    onUpdate({
      type: 'initialActivities',
      chain,
      accountId,
      mainActivities: [],
      bySlug: {},
    });
    throw err;
  }
}

async function loadNewActivities(
  chain: EVMChain,
  accountId: string,
  newestActivityTimestamp: number,
  onUpdate: OnApiUpdate,
): Promise<ApiActivityTimestamps> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, chain);

  const { activities: rawActivities } = await getTokenActivitySlice(
    chain,
    network,
    address,
    undefined,
    undefined,
    newestActivityTimestamp,
    FIRST_TRANSACTIONS_LIMIT,
  );

  const result: ApiActivityTimestamps = {};
  if (!rawActivities.length) return result;

  // Advance the polling cursor from the RAW on-chain slice, before the swap merge. A merged
  // cross-chain CEX swap can carry a backend timestamp newer than every on-chain leg in this slice;
  // anchoring the cursor on it would push `min_mined_at` past a genuine on-chain tx whose timestamp
  // falls in between, so that tx is never fetched on the next poll and silently misses the live feed.
  // Tron keeps its cursor on the raw slice for the same reason; the merge below is display-only.
  result[getChainConfig(chain).nativeToken.slug] = rawActivities[0].timestamp;

  // Merge cross-chain CEX swaps so a freshly polled swap leg is shown as a swap, not a plain
  // transfer, consistent with the initial load and the shared pagination path.
  const activities = await swapReplaceActivities(accountId, rawActivities, undefined, true);

  activities
    .slice()
    .reverse()
    .forEach((activity) => {
      txCallbacks.runCallbacks(activity);
    });

  onUpdate({
    type: 'newActivities',
    chain,
    activities,
    pendingActivities: [],
    accountId,
  });

  return result;
}
