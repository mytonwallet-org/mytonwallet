import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  OnApiUpdate,
  OnUpdatingStatusChange,
  UTXOChain,
} from '../../types';

import { parseAccountId } from '../../../util/account';
import { getActivityTokenSlugs, getIsActivityPending } from '../../../util/activities';
import { getChainConfig } from '../../../util/chain';
import { focusAwareDelay } from '../../../util/focusAwareDelay';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause, throttle } from '../../../util/schedulers';
import { getUtxoSocket } from './util/socket';
import { fetchStoredWallet } from '../../common/accounts';
import { getUtxoBackendSocket } from '../../common/backendSocket';
import {
  activeWalletTiming,
  inactiveWalletTiming,
  periodToMs,
} from '../../common/polling/utils';
import { swapReplaceActivities } from '../../common/swap';
import { sendUpdateTokens } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { FIRST_TRANSACTIONS_LIMIT } from '../../constants';
import { getTokenActivitySlice, parseUtxoTransaction } from './activities';
import { normalizeAddress } from './address';
import { fetchAccountAssets } from './wallet';

/** Blockbook fetches are fast; on import they can finish before the account lands in global state. */
const INITIAL_BALANCE_PUSH_ATTEMPTS = 3;
const INITIAL_BALANCE_PUSH_DELAY_MS = 600;

export function setupActivePolling<C extends UTXOChain>(
  chain: C,
  accountId: string,
  account: ApiAccountWithChain<C>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
  _shouldResetBalances?: boolean,
): NoneToVoidFunction {
  const { address } = account.byChain[chain];

  const activityPolling = setupActivityPolling(
    chain,
    accountId,
    newestActivityTimestamps,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
  );

  const balancePolling = setupBalancePolling(
    chain,
    accountId,
    address,
    true,
    activityPolling.update,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'balance'),
  );
  const backendActivityWatcher = setupUtxoBackendActivityTracking(
    chain, accountId, address, activityPolling.update, onUpdate,
  );

  const hasCachedTimestamps = compact(Object.values(newestActivityTimestamps)).length > 0;

  if (!hasCachedTimestamps) {
    activityPolling.update();
  }

  return () => {
    backendActivityWatcher?.();
    balancePolling.stop();
  };
}

export function setupInactivePolling<C extends UTXOChain>(
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
    onUpdate,
  );

  return balancePolling.stop;
}

function setupActivityPolling(
  chain: UTXOChain,
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: (isUpdating: boolean) => void,
) {
  const initialTimestamps = compact(Object.values(newestActivityTimestamps));
  let newestConfirmedActivityTimestamp = initialTimestamps.length ? Math.max(...initialTimestamps) : undefined;

  let lastEmptyTimestamp: number | undefined;

  async function rawUpdate() {
    if (newestConfirmedActivityTimestamp !== undefined && newestConfirmedActivityTimestamp === lastEmptyTimestamp) {
      return;
    }

    onUpdatingStatusChange(true);

    try {
      if (newestConfirmedActivityTimestamp === undefined) {
        const result = await loadInitialActivities(chain, accountId, onUpdate);
        const timestamps = compact(Object.values(result));

        newestConfirmedActivityTimestamp = timestamps.length ? Math.max(...timestamps) : undefined;
      } else {
        const result = await loadNewActivities(chain, accountId, newestConfirmedActivityTimestamp, onUpdate);
        const newTimestamps = compact(Object.values(result));

        if (newTimestamps.length && Math.max(...newTimestamps) > newestConfirmedActivityTimestamp) {
          newestConfirmedActivityTimestamp = Math.max(newestConfirmedActivityTimestamp, Math.max(...newTimestamps));
        } else {
          lastEmptyTimestamp = newestConfirmedActivityTimestamp;
        }
      }
    } catch (err) {
      logDebugError(`utxo:${chain}:setupActivityPolling`, err);
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

export function setupUtxoBackendActivityTracking(
  chain: UTXOChain,
  accountId: string,
  address: string,
  activityUpdate: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
) {
  const { network } = parseAccountId(accountId);
  const subscriptionAddress = normalizeAddress(chain, address, network);
  const watcher = getUtxoBackendSocket(network).watchWallets([{
    chain,
    address: subscriptionAddress,
    events: ['activity'],
  }], {
    onConnect: activityUpdate,
    onNewActivities: ({ utxoActivityUpdate }) => {
      if (!utxoActivityUpdate) {
        activityUpdate();
        return;
      }

      const activity = parseUtxoTransaction(
        utxoActivityUpdate.chain,
        network,
        subscriptionAddress,
        utxoActivityUpdate.rawTransaction,
      );

      onUpdate({
        type: 'newActivities',
        accountId,
        chain: utxoActivityUpdate.chain,
        activities: [{
          ...activity,
          confirmations: utxoActivityUpdate.confirmations,
          maxConfirmations: utxoActivityUpdate.maxConfirmations,
          etaSeconds: utxoActivityUpdate.etaSeconds,
          status: utxoActivityUpdate.status,
        }],
      });
    },
  });

  return () => watcher.destroy();
}

function setupBalancePolling(
  chain: UTXOChain,
  accountId: string,
  address: string,
  isActive: boolean,
  activityUpdate: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);

  const balanceStream = new BalanceStream({
    chain,
    wsClient: getUtxoSocket(network, chain),
    network,
    address,
    sendUpdateTokens: () => sendUpdateTokens(onUpdate),
    fallbackPollingOptions: isActive ? activeWalletTiming : inactiveWalletTiming,
    fetchBalancesCb: async (...args) => ({ balances: await fetchAccountAssets(chain, ...args) }),
    // UTXO activities are handled by the backend confirmation tracker; keep direct Blockbook only for balances.
    onNewActivities: undefined,
  });

  balanceStream.onUpdate((balances) => {
    onUpdate({
      type: 'updateBalances',
      accountId,
      chain,
      balances,
    });

    activityUpdate();
  });

  if (onUpdatingStatusChange) {
    balanceStream.onLoadingChange(onUpdatingStatusChange);
  }

  balanceStream.start();

  async function pushInitialBalances() {
    let didPushBalances = false;

    for (let attempt = 0; attempt < INITIAL_BALANCE_PUSH_ATTEMPTS; attempt++) {
      if (attempt > 0) {
        await pause(INITIAL_BALANCE_PUSH_DELAY_MS);
      }

      try {
        const balances = await fetchAccountAssets(chain, network, address, () => sendUpdateTokens(onUpdate));

        onUpdate({
          type: 'updateBalances',
          accountId,
          chain,
          balances,
        });

        didPushBalances = true;
      } catch (err) {
        logDebugError(`utxo:${chain}:pushInitialBalances`, err);
      }
    }

    if (didPushBalances) {
      activityUpdate();
    }
  }

  if (isActive) {
    void pushInitialBalances();
  }

  return {
    stop() {
      balanceStream.destroy();
    },
  };
}

async function loadInitialActivities(
  chain: UTXOChain,
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
      FIRST_TRANSACTIONS_LIMIT,
    );

    const activities = await swapReplaceActivities(accountId, rawActivities, undefined, true);

    activities
      .slice()
      .reverse()
      .forEach((activity) => {
        txCallbacks.runCallbacks(activity);
      });

    const result: ApiActivityTimestamps = {};
    const bySlug: Record<string, ApiActivity[]> = {};
    for (const activity of activities) {
      for (const slug of getActivityTokenSlugs(activity)) {
        (bySlug[slug] ??= []).push(activity);
        if (!getIsActivityPending(activity)) {
          result[slug] ??= activity.timestamp;
        }
      }
    }

    const newestConfirmedActivity = activities.find((activity) => !getIsActivityPending(activity));
    if (!Object.keys(result).length && newestConfirmedActivity) {
      result[getChainConfig(chain).nativeToken.slug] = newestConfirmedActivity.timestamp;
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
  chain: UTXOChain,
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
    newestActivityTimestamp,
    FIRST_TRANSACTIONS_LIMIT,
  );

  const confirmedRawActivities = rawActivities.filter((activity) => !getIsActivityPending(activity));
  const result: ApiActivityTimestamps = {};

  if (!rawActivities.length) return result;

  if (confirmedRawActivities.length) {
    result[getChainConfig(chain).nativeToken.slug] = confirmedRawActivities[0].timestamp;
  }

  const activities = await swapReplaceActivities(accountId, rawActivities, undefined, true);

  activities
    .slice()
    .reverse()
    .forEach((activity) => {
      txCallbacks.runCallbacks(activity);
    });

  if (activities.length > 0) {
    onUpdate({
      type: 'newActivities',
      chain,
      activities,
      accountId,
    });
  }

  return result;
}
