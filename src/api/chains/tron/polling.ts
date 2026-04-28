import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  ApiBalanceBySlug,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { TRX } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { areDeepEqual } from '../../../util/areDeepEqual';
import isEmptyObject from '../../../util/isEmptyObject';
import { logDebugError } from '../../../util/logs';
import { getTokenSlugs } from './util/tokens';
import { fetchStoredWallet } from '../../common/accounts';
import { setupInactiveChainPolling } from '../../common/polling/setupInactiveChainPolling';
import { activeWalletTiming, withDoubleCheck } from '../../common/polling/utils';
import { WalletPolling } from '../../common/polling/walletPolling';
import { swapReplaceActivities } from '../../common/swap';
import { buildTokenSlug } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { FIRST_TRANSACTIONS_LIMIT, SEC } from '../../constants';
import { getTokenActivitySlice, mergeActivities } from './activities';
import { NETWORK_CONFIG } from './constants';
import { getTrc20Balance, getWalletBalance, isTronAccountMultisig } from './wallet';

const DOUBLE_CHECK_ACTIVITY_PAUSE = 3 * SEC;

export function setupActivePolling(
  accountId: string,
  account: ApiAccountWithChain<'tron'>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
  shouldResetBalances?: boolean,
): NoneToVoidFunction {
  const { address } = account.byChain.tron;

  const balancePolling = setupBalancePolling(
    accountId,
    address,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'balance'),
  );
  const activityPolling = setupActivityPolling(
    accountId,
    newestActivityTimestamps,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
  );
  const multisigPolling = setupMultisigPolling(
    accountId,
    address,
    onUpdate,
  );

  const activityDoubleCheck = withDoubleCheck(
    [DOUBLE_CHECK_ACTIVITY_PAUSE],
    () => activityPolling.update(),
  );

  let isFirstUpdate = true;

  async function handleUpdate(isConfident: boolean) {
    if (isConfident || isFirstUpdate) {
      const [hasBalanceChanged, hadActivities] = await Promise.all([
        balancePolling.update(),
        activityPolling.update(),
        multisigPolling.update(),
      ]);
      // If the balance has changed, but no new activity has arrived, it means that the socket was triggered before the API
      // had time to index the transaction (for example, when activating new wallets). Try again after a short delay.
      if (isConfident && hasBalanceChanged && !hadActivities) {
        await activityDoubleCheck.run();
      }
    } else {
      // Legacy (timer) polling mode.
      // The balance is checked before the activities, because the backend throttling for balance is much looser.
      const hasBalanceChanged = await balancePolling.update();
      if (hasBalanceChanged) {
        await Promise.all([
          activityPolling.update(),
          multisigPolling.update(),
        ]);
      }
    }

    isFirstUpdate = false;
  }

  const walletPolling = new WalletPolling({
    chain: 'tron',
    network: parseAccountId(accountId).network,
    address,
    pollingOptions: activeWalletTiming,
    onUpdate: handleUpdate,
  });

  return () => {
    walletPolling.destroy();
    activityDoubleCheck.cancel();
  };
}

function setupBalancePolling(
  accountId: string,
  address: string,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);
  const { usdtAddress } = NETWORK_CONFIG[network];
  const usdtSlug = buildTokenSlug('tron', usdtAddress);

  let balances: ApiBalanceBySlug | undefined;

  /** Returns `true` if the balances have changed since the last update */
  async function update() {
    onUpdatingStatusChange?.(true);

    try {
      const [trxBalance, usdtBalance] = await Promise.all([
        getWalletBalance(network, address),
        getTrc20Balance(network, usdtAddress, address),
      ]);
      const newBalances = {
        [TRX.slug]: trxBalance,
        [usdtSlug]: usdtBalance,
      };
      const hasChanged = !areDeepEqual(balances, newBalances);
      balances = newBalances;

      if (hasChanged) {
        onUpdate({
          type: 'updateBalances',
          accountId,
          chain: 'tron',
          balances,
        });
      }

      return hasChanged;
    } catch (err) {
      logDebugError('setupBalancePolling update', err);
    } finally {
      onUpdatingStatusChange?.(false);
    }

    return false;
  }

  return { update };
}

function setupMultisigPolling(
  accountId: string,
  address: string,
  onUpdate: OnApiUpdate,
) {
  const { network } = parseAccountId(accountId);
  let isMultisig: boolean | undefined;

  async function update() {
    try {
      const multisigStatus = await isTronAccountMultisig(network, address);
      const hasChanged = isMultisig !== multisigStatus;
      isMultisig = multisigStatus;

      if (hasChanged) {
        onUpdate({
          type: 'updateAccount',
          accountId,
          chain: 'tron',
          isMultisig: multisigStatus,
        });
      }

      return hasChanged;
    } catch (err) {
      logDebugError('setupMultisigPolling update', err);
      return false;
    }
  }

  return { update };
}

function setupActivityPolling(
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);
  const slugs = getTokenSlugs(network);

  async function update() {
    onUpdatingStatusChange(true);

    try {
      if (isEmptyObject(newestActivityTimestamps)) {
        newestActivityTimestamps = await loadInitialActivities(accountId, slugs, onUpdate);
        return false;
      } else {
        const { timestamps, hadActivities } = await loadNewActivities(
          accountId, newestActivityTimestamps, slugs, onUpdate,
        );
        newestActivityTimestamps = timestamps;
        return hadActivities;
      }
    } catch (err) {
      logDebugError('setupActivityPolling update', err);
      return false;
    } finally {
      onUpdatingStatusChange(false);
    }
  }

  return { update };
}

export function setupInactivePolling(
  accountId: string,
  account: ApiAccountWithChain<'tron'>,
  onUpdate: OnApiUpdate,
): NoneToVoidFunction {
  const { network } = parseAccountId(accountId);
  const { address } = account.byChain.tron;

  const balancePolling = setupBalancePolling(accountId, address, onUpdate);

  return setupInactiveChainPolling('tron', network, address, balancePolling.update);
}

async function loadInitialActivities(
  accountId: string,
  tokenSlugs: string[],
  onUpdate: OnApiUpdate,
) {
  try {
    const { network } = parseAccountId(accountId);
    const { address } = await fetchStoredWallet(accountId, 'tron');
    const result: ApiActivityTimestamps = {};
    const bySlug: Record<string, ApiActivity[]> = {};
    let mainHistoryHasMore = false;

    await Promise.all(tokenSlugs.map(async (slug) => {
      const slice = await getTokenActivitySlice(
        network, address, slug, undefined, undefined, FIRST_TRANSACTIONS_LIMIT,
      );
      mainHistoryHasMore ||= slice.hasMore;

      const activities = await swapReplaceActivities(accountId, slice.activities, slug, true);

      result[slug] = activities[0]?.timestamp;
      bySlug[slug] = activities;
    }));

    const mainActivities = mergeActivities(bySlug);

    mainActivities.slice().reverse().forEach((transaction) => {
      txCallbacks.runCallbacks(transaction);
    });

    onUpdate({
      type: 'initialActivities',
      chain: 'tron',
      accountId,
      mainActivities,
      mainHistoryHasMore,
      bySlug,
    });

    return result;
  } catch (err) {
    // Ensure `areInitialActivitiesLoaded.tron = true` even on failure so
    // `waitInitialActivityLoading` unblocks and other chains stay visible.
    onUpdate({
      type: 'initialActivities',
      chain: 'tron',
      accountId,
      mainActivities: [],
      bySlug: {},
    });
    throw err;
  }
}

async function loadNewActivities(
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  tokenSlugs: string[],
  onUpdate: OnApiUpdate,
): Promise<{ timestamps: ApiActivityTimestamps; hadActivities: boolean }> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'tron');
  const result: ApiActivityTimestamps = {};
  const bySlug: Record<string, ApiActivity[]> = {};

  await Promise.all(tokenSlugs.map(async (slug) => {
    let newestActivityTimestamp = newestActivityTimestamps[slug];
    const { activities } = await getTokenActivitySlice(
      network, address, slug, undefined, newestActivityTimestamp, FIRST_TRANSACTIONS_LIMIT,
    );

    newestActivityTimestamp = activities[0]?.timestamp ?? newestActivityTimestamp;
    result[slug] = newestActivityTimestamp;
    bySlug[slug] = activities;
  }));

  let activities = mergeActivities(bySlug);

  activities = await swapReplaceActivities(accountId, activities, undefined, true);

  activities.slice().reverse().forEach((activity) => {
    txCallbacks.runCallbacks(activity);
  });

  if (activities.length > 0) {
    onUpdate({
      type: 'newActivities',
      chain: 'tron',
      activities,
      pendingActivities: [],
      accountId,
    });
  }

  return { timestamps: result, hadActivities: activities.length > 0 };
}
