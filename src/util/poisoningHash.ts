import type { ApiActivity, ApiTransaction } from '../api/types';
import type { GlobalState } from '../global/types';

import { TRANSACTION_ADDRESS_SHIFT } from '../config';
import { getIsActivityPendingForUser } from './activities';
import { shortenAddress } from './shortenAddress';

const cache = new Map<string, {
  timestamp: number;
  amount: bigint;
  address: string;
}>();

function getKey(address: string) {
  return shortenAddress(address, TRANSACTION_ADDRESS_SHIFT)!;
}

function addToCache(address: string, amount: bigint, timestamp: number) {
  const key = getKey(address);

  cache.set(key, {
    address,
    amount,
    timestamp,
  });
}

function getFromCache(address: string) {
  const key = getKey(address);

  return cache.get(key);
}

function updatePoisoningCache(tx: ApiTransaction) {
  const {
    fromAddress,
    toAddress,
    isIncoming,
    amount,
    timestamp,
  } = tx;

  const address = isIncoming ? fromAddress : toAddress;
  const cached = getFromCache(address);

  if (!cached || cached.timestamp > timestamp || (cached.timestamp === timestamp && cached.amount < amount)) {
    addToCache(address, amount, timestamp);
  }
}

export function updatePoisoningCacheFromActivities(activities: readonly ApiActivity[]) {
  activities.forEach((activity) => {
    if (activity.kind === 'transaction' && !getIsActivityPendingForUser(activity)) {
      updatePoisoningCache(activity);
    }
  });
}

export function updatePoisoningCacheFromGlobalState(global: GlobalState) {
  if (!global.currentAccountId) return;

  const { byId, newestActivitiesBySlug } = global.byAccountId[global.currentAccountId].activities || {};

  if (byId) {
    updatePoisoningCacheFromActivities(Object.values(byId));
  }

  if (newestActivitiesBySlug) {
    updatePoisoningCacheFromActivities(Object.values(newestActivitiesBySlug));
  }
}

export function getIsTransactionWithPoisoning(tx: ApiTransaction) {
  const { fromAddress: address } = tx;

  const cached = getFromCache(address);

  return cached && cached.address !== address;
}

export function clearPoisoningCache() {
  cache.clear();
}
