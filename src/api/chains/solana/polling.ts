import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { parseAccountId } from '../../../util/account';
import { focusAwareDelay } from '../../../util/focusAwareDelay';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { throttle } from '../../../util/schedulers';
import { NftStream } from './util/nftStream';
import { getHeliusSocket } from './util/socket';
import { fetchStoredWallet } from '../../common/accounts';
import { getConcurrencyLimiter } from '../../common/polling/setupInactiveChainPolling';
import { activeWalletTiming, inactiveWalletTiming, periodToMs } from '../../common/polling/utils';
import { swapReplaceActivities } from '../../common/swap';
import { sendUpdateTokens } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { FIRST_TRANSACTIONS_LIMIT } from '../../constants';
import { getTokenActivitySlice } from './activities';
import { fetchAccountAssets } from './wallet';

export function setupActivePolling(
  accountId: string,
  account: ApiAccountWithChain<'solana'>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
): NoneToVoidFunction {
  const { address } = account.byChain.solana;

  const activityPolling = setupActivityPolling(
    accountId,
    newestActivityTimestamps,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
  );

  const nftPolling = setupNftPolling(
    accountId,
    address,
    true,
    activityPolling.update,
    onUpdate,
  );

  const balancePolling = setupBalancePolling(
    accountId,
    address,
    true,
    activityPolling.update,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'balance'),
  );

  return () => {
    nftPolling.stop();
    balancePolling.stop();
  };
}

function setupBalancePolling(
  accountId: string,
  address: string,
  isActive: boolean,
  activityUpdate: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);

  const balanceStream = new BalanceStream(
    'solana',
    getHeliusSocket(network),
    network,
    address,
    () => sendUpdateTokens(onUpdate),
    isActive ? activeWalletTiming : inactiveWalletTiming,
    fetchAccountAssets,
    undefined,
    isActive ? undefined : getConcurrencyLimiter('solana', network),
  );

  balanceStream.onUpdate((balances) => {
    onUpdate({
      type: 'updateBalances',
      accountId,
      chain: 'solana',
      balances,
    });
    activityUpdate();
  });

  if (onUpdatingStatusChange) {
    balanceStream.onLoadingChange(onUpdatingStatusChange);
  }

  return {
    stop() {
      balanceStream.destroy();
    },
    getBalances() {
      return balanceStream.getBalances();
    },
  };
}

function setupActivityPolling(
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: (isUpdating: boolean) => void,
) {
  const initialTimestamps = compact(Object.values(newestActivityTimestamps));
  let newestConfirmedActivityTimestamp = initialTimestamps.length ? Math.max(...initialTimestamps) : undefined;

  // Tracks the last timestamp for which the API returned no new activities.
  // Prevents redundant re-queries (e.g., the throttle's scheduled second run after an empty response).
  // Reset every time a new external signal arrives via update(), so real transactions are never skipped.
  let lastEmptyTimestamp: number | undefined;

  async function rawUpdate() {
    if (newestConfirmedActivityTimestamp !== undefined && newestConfirmedActivityTimestamp === lastEmptyTimestamp) {
      return;
    }

    onUpdatingStatusChange(true);

    try {
      if (newestConfirmedActivityTimestamp === undefined) {
        const result = await loadInitialActivities(accountId, onUpdate);
        const timestamps = compact(Object.values(result));

        newestConfirmedActivityTimestamp = timestamps.length ? Math.max(...timestamps) : undefined;
      } else {
        const result = await loadNewActivities(accountId, newestConfirmedActivityTimestamp, onUpdate);
        const newTimestamps = compact(Object.values(result));

        if (newTimestamps.length && Math.max(...newTimestamps) > newestConfirmedActivityTimestamp) {
          newestConfirmedActivityTimestamp = Math.max(newestConfirmedActivityTimestamp, Math.max(...newTimestamps));
        } else {
          lastEmptyTimestamp = newestConfirmedActivityTimestamp;
        }
      }
    } catch (err) {
      logDebugError('setupActivityPolling update', err);
    } finally {
      onUpdatingStatusChange(false);
    }
  }

  const throttledUpdate = throttle(rawUpdate, () => focusAwareDelay(...periodToMs(activeWalletTiming.minPollDelay)));

  function update() {
    lastEmptyTimestamp = undefined;
    throttledUpdate();
  }

  return { update };
}

function setupNftPolling(
  accountId: string,
  address: string,
  isActive: boolean,
  activityUpdate: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
) {
  const nftStream = new NftStream(
    parseAccountId(accountId).network,
    address,
    accountId,
    isActive ? activeWalletTiming : inactiveWalletTiming,
  );

  nftStream.onUpdate((params) => {
    if (params.direction === 'set') {
      onUpdate({
        type: 'updateNfts',
        accountId,
        nfts: params.nfts,
        chain: 'solana',
        isFullLoading: params.isFullLoading,
        streamedAddresses: params.streamedAddresses,
      });
      if (!params.hasNewNfts) return;
    }
    if (params.direction === 'send') {
      onUpdate({
        type: 'nftSent',
        accountId,
        nftAddress: params.nftAddress,
        newOwnerAddress: params.newOwner,
      });
    }
    if (params.direction === 'receive') {
      onUpdate({
        type: 'nftReceived',
        accountId,
        nft: params.nft,
        nftAddress: params.nft.address,
      });
    }

    activityUpdate();
  });

  return {
    stop() {
      nftStream.destroy();
    },
  };
}

export function setupInactivePolling(
  accountId: string,
  account: ApiAccountWithChain<'solana'>,
  onUpdate: OnApiUpdate,
): NoneToVoidFunction {
  const { address } = account.byChain.solana;

  const balancePolling = setupBalancePolling(accountId, address, false, () => {}, onUpdate);

  return balancePolling.stop;
}

async function loadInitialActivities(accountId: string, onUpdate: OnApiUpdate) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');
  const result: ApiActivityTimestamps = {};
  const bySlug: Record<string, ApiActivity[]> = {};

  let activities: ApiActivity[] = await getTokenActivitySlice(
    network,
    address,
    undefined,
    undefined,
    undefined,
    FIRST_TRANSACTIONS_LIMIT,
  );

  activities = await swapReplaceActivities(accountId, activities, undefined, true);

  for (const tx of activities) {
    if (tx.kind === 'transaction') {
      bySlug[tx.slug] = [...(bySlug[tx.slug] || []), tx];
      result[tx.slug] = bySlug[tx.slug][0].timestamp;
    } else {
      bySlug[tx.from] = [...(bySlug[tx.from] || []), tx];
      bySlug[tx.to] = [...(bySlug[tx.to] || []), tx];

      result[tx.from] = bySlug[tx.from][0].timestamp;
      result[tx.to] = bySlug[tx.to][0].timestamp;
    }
  }

  const mainActivities = activities;

  mainActivities
    .slice()
    .reverse()
    .forEach((transaction) => {
      txCallbacks.runCallbacks(transaction);
    });

  onUpdate({
    type: 'initialActivities',
    chain: 'solana',
    accountId,
    mainActivities,
    bySlug,
  });

  return result;
}

async function loadNewActivities(
  accountId: string,
  newestActivityTimestamp: number,
  onUpdate: OnApiUpdate,
) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');
  const result: ApiActivityTimestamps = {};
  const bySlug: Record<string, ApiActivity[]> = {};

  let rawActivities: ApiActivity[] = await getTokenActivitySlice(
    network,
    address,
    undefined,
    undefined,
    newestActivityTimestamp,
    FIRST_TRANSACTIONS_LIMIT,
  );

  rawActivities = await swapReplaceActivities(accountId, rawActivities, undefined, true);

  for (const tx of rawActivities) {
    if (tx.kind === 'transaction') {
      bySlug[tx.slug] = [...(bySlug[tx.slug] || []), tx];

      result[tx.slug] = bySlug[tx.slug][0].timestamp;
    } else {
      bySlug[tx.from] = [...(bySlug[tx.from] || []), tx];
      bySlug[tx.to] = [...(bySlug[tx.to] || []), tx];

      result[tx.from] = bySlug[tx.from][0].timestamp;
      result[tx.to] = bySlug[tx.to][0].timestamp;
    }
  }

  const activities = rawActivities;

  activities
    .slice()
    .reverse()
    .forEach((activity) => {
      txCallbacks.runCallbacks(activity);
    });

  if (activities.length > 0) {
    onUpdate({
      type: 'newActivities',
      chain: 'solana',
      activities,
      pendingActivities: [],
      accountId,
    });
  }

  return result;
}
