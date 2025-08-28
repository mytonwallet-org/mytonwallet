import type {
  ApiAccountAny,
  ApiActivity,
  ApiActivityTimestamps,
  ApiBalanceBySlug,
  ApiUpdatingStatus,
  OnApiUpdate,
} from '../../types';

import { TRX } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { getChainConfig } from '../../../util/chain';
import isEmptyObject from '../../../util/isEmptyObject';
import { logDebugError } from '../../../util/logs';
import { createTaskQueue } from '../../../util/schedulers';
import { getTokenSlugs } from './util/tokens';
import { enrichActivities } from '../../common/activities';
import { activeWalletTiming, inactiveWalletTiming } from '../../common/polling/utils';
import { WalletPolling } from '../../common/polling/walletPolling';
import { buildTokenSlug } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { FIRST_TRANSACTIONS_LIMIT } from '../../constants';
import { getTokenTransactionSlice, mergeActivities } from './transactions';
import { getTrc20Balance, getWalletBalance, isTronAccountMultisig } from './wallet';

type OnUpdatingStatusChange = (kind: ApiUpdatingStatus['kind'], isUpdating: boolean) => void;

const inactiveUpdateConcurrencyLimiter = createTaskQueue();

export function setupActivePolling(
  accountId: string,
  account: ApiAccountAny,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
): NoneToVoidFunction {
  if (!('tron' in account) || !account.tron) {
    return () => {};
  }

  const { address } = account.tron;

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

  let isFirstUpdate = true;

  async function handleUpdate(isConfident: boolean) {
    if (isConfident || isFirstUpdate) {
      await Promise.all([
        balancePolling.update(),
        activityPolling.update(),
        multisigPolling.update(),
      ]);
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
    ...activeWalletTiming,
    chain: 'tron',
    network: parseAccountId(accountId).network,
    address,
    onUpdate: handleUpdate,
  });

  return () => {
    walletPolling.destroy();
  };
}

function setupBalancePolling(
  accountId: string,
  address: string,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);
  const { usdtAddress } = getChainConfig('tron')[network];
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
      } else {
        newestActivityTimestamps = await loadNewActivities(accountId, newestActivityTimestamps, slugs, onUpdate);
      }
    } catch (err) {
      logDebugError('setupActivityPolling update', err);
    } finally {
      onUpdatingStatusChange(false);
    }
  }

  return { update };
}

export function setupInactivePolling(
  accountId: string,
  account: ApiAccountAny,
  onUpdate: OnApiUpdate,
): NoneToVoidFunction {
  if (!('tron' in account) || !account.tron) {
    return () => {};
  }

  const { address } = account.tron;

  const balancePolling = setupBalancePolling(accountId, address, onUpdate);

  const walletPolling = new WalletPolling({
    ...inactiveWalletTiming,
    chain: 'tron',
    network: parseAccountId(accountId).network,
    address,
    onUpdate: inactiveUpdateConcurrencyLimiter.wrap(async () => {
      await balancePolling.update();
    }),
  });

  return () => {
    walletPolling.destroy();
  };
}

async function loadInitialActivities(
  accountId: string,
  tokenSlugs: string[],
  onUpdate: OnApiUpdate,
) {
  const result: ApiActivityTimestamps = {};
  const bySlug: Record<string, ApiActivity[]> = {};

  const chunks = await Promise.all(tokenSlugs.map(async (slug) => {
    let activities: ApiActivity[] = await getTokenTransactionSlice(
      accountId, slug, undefined, undefined, FIRST_TRANSACTIONS_LIMIT,
    );

    activities = await enrichActivities(accountId, activities, slug, true);

    result[slug] = activities[0]?.timestamp;
    bySlug[slug] = activities;

    return activities;
  }));

  const [trxChunk, ...tokenChunks] = chunks;
  const mainActivities = mergeActivities(trxChunk, ...tokenChunks);

  mainActivities.slice().reverse().forEach((transaction) => {
    txCallbacks.runCallbacks(transaction);
  });

  onUpdate({
    type: 'initialActivities',
    chain: 'tron',
    accountId,
    mainActivities,
    bySlug,
  });

  return result;
}

async function loadNewActivities(
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps,
  tokenSlugs: string[],
  onUpdate: OnApiUpdate,
) {
  const result: ApiActivityTimestamps = {};

  const chunks = await Promise.all(tokenSlugs.map(async (slug) => {
    let newestActivityTimestamp = newestActivityTimestamps[slug];
    const activities: ApiActivity[] = await getTokenTransactionSlice(
      accountId, slug, undefined, newestActivityTimestamp, FIRST_TRANSACTIONS_LIMIT,
    );

    newestActivityTimestamp = activities[0]?.timestamp ?? newestActivityTimestamp;
    result[slug] = newestActivityTimestamp;
    return activities;
  }));

  const [trxChunk, ...tokenChunks] = chunks;
  let activities = mergeActivities(trxChunk, ...tokenChunks);

  activities = await enrichActivities(accountId, activities, undefined, true);

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

  return result;
}
