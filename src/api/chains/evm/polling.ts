import type {
  ApiAccountWithChain,
  ApiActivityTimestamps,
  EVMChain,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { parseAccountId } from '../../../util/account';
import { getChainConfig } from '../../../util/chain';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { NftStream } from './util/nftStream';
import { getAlchemySocket } from './util/socket';
import { fetchStoredWallet } from '../../common/accounts';
import {
  activeNftTiming,
  activeWalletTiming,
  inactiveWalletTiming,
} from '../../common/polling/utils';
import { sendUpdateTokens } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { FIRST_TRANSACTIONS_LIMIT, SEC } from '../../constants';
import { getTokenActivitySlice } from './activities';
import { fetchAccountAssets, getIsWalletActive } from './wallet';

export function setupActivePolling<C extends EVMChain>(
  chain: C,
  accountId: string,
  account: ApiAccountWithChain<C>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
): NoneToVoidFunction {
  const { address } = account.byChain[chain];

  const {
    scheduleCrossApiActivityCatchUp,
    cancelCrossApiActivityCatchUp,
  } = setupActivityPolling(
    chain, accountId, newestActivityTimestamps, onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
  );

  const nftPolling = setupNftPolling(chain, accountId, address, scheduleCrossApiActivityCatchUp, onUpdate);

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

  return () => {
    nftPolling.stop();
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

        return timestamps.length > 0;
      } else {
        const result = await loadNewActivities(chain, accountId, newestConfirmedActivityTimestamp, onUpdate);
        const newTimestamps = compact(Object.values(result));

        if (newTimestamps.length && Math.max(...newTimestamps) > newestConfirmedActivityTimestamp) {
          newestConfirmedActivityTimestamp = Math.max(newestConfirmedActivityTimestamp, Math.max(...newTimestamps));
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

        await pause(SEC);
      }
    })();
  }

  function cancelCrossApiActivityCatchUp() {
    balanceCatchUpGeneration += 1;
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

  const balanceStream = new BalanceStream(
    chain,
    getAlchemySocket(network, chain),
    network,
    address,
    () => sendUpdateTokens(onUpdate),
    isActive ? activeWalletTiming : inactiveWalletTiming,
    (...args) => fetchAccountAssets(chain, ...args),
    undefined,
    undefined,
    checkIsWalletActive,
  );

  balanceStream.onUpdate((balances, updateSource) => {
    onUpdate({
      type: 'updateBalances',
      accountId,
      chain,
      balances,
    });

    scheduleCrossApiActivityCatchUp(updateSource);
  });

  if (onUpdatingStatusChange) {
    balanceStream.onLoadingChange(onUpdatingStatusChange);
  }

  return {
    stop() {
      cancelCrossApiActivityCatchUp();
      balanceStream.destroy();
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

    const { activities, hasMore: mainHistoryHasMore } = await getTokenActivitySlice(
      chain,
      network,
      address,
      undefined,
      undefined,
      undefined,
      FIRST_TRANSACTIONS_LIMIT,
    );

    activities
      .slice()
      .reverse()
      .forEach((activity) => {
        txCallbacks.runCallbacks(activity);
      });

    onUpdate({
      type: 'initialActivities',
      chain,
      accountId,
      mainActivities: activities,
      mainHistoryHasMore,
      bySlug: {},
    });

    const result: ApiActivityTimestamps = {};
    if (activities.length) {
      result[getChainConfig(chain).nativeToken.slug] = activities[0].timestamp;
    }
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

  const { activities } = await getTokenActivitySlice(
    chain,
    network,
    address,
    undefined,
    undefined,
    newestActivityTimestamp,
    FIRST_TRANSACTIONS_LIMIT,
  );

  const result: ApiActivityTimestamps = {};
  if (!activities.length) return result;

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

  result[getChainConfig(chain).nativeToken.slug] = activities[0].timestamp;
  return result;
}
