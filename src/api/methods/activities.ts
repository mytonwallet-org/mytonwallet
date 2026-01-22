import type {
  ApiActivity,
  ApiChain,
  ApiFetchActivitySliceOptions,
  ApiFetchTransactionByIdOptions,
  ApiTransactionActivity,
} from '../types';

import { DEBUG } from '../../config';
import { getActivityChains } from '../../util/activities';
import { areActivitiesSortedAndUnique, mergeSortedActivitiesToMaxTime } from '../../util/activities/order';
import { logDebug, logDebugError } from '../../util/logs';
import { getChainBySlug } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAccount } from '../common/accounts';
import { swapReplaceCexActivities } from '../common/swap';

export async function fetchPastActivities(
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
): Promise<ApiActivity[] | undefined> {
  try {
    let activities = tokenSlug
      ? await fetchTokenActivitySlice(accountId, limit, tokenSlug, toTimestamp)
      : await fetchAllActivitySlice(accountId, limit, toTimestamp);

    activities = await swapReplaceCexActivities(accountId, activities, tokenSlug);

    return activities;
  } catch (err) {
    logDebugError('fetchPastActivities', tokenSlug, err);
    return undefined;
  }
}

function fetchTokenActivitySlice(
  accountId: string,
  limit: number,
  tokenSlug: string,
  toTimestamp?: number,
) {
  const chain = getChainBySlug(tokenSlug);
  return fetchAndCheckActivitySlice(chain, { accountId, tokenSlug, toTimestamp, limit });
}

async function fetchAllActivitySlice(
  accountId: string,
  limit: number,
  toTimestamp?: number,
): Promise<ApiActivity[]> {
  const account = await fetchStoredAccount(accountId);
  const accountChains = Object.keys(account.byChain) as (keyof typeof account.byChain)[];

  const activityChunks = await Promise.all(
    // The `fetchActivitySlice` method of all chains must return sorted activities
    accountChains.map((chain) => fetchAndCheckActivitySlice(chain, { accountId, toTimestamp, limit })),
  );

  return mergeSortedActivitiesToMaxTime(...activityChunks);
}

export function decryptComment(accountId: string, activity: ApiTransactionActivity, password?: string) {
  const { encryptedComment } = activity;
  if (!encryptedComment) {
    return activity.comment ?? '';
  }

  const chain = getActivityChains(activity)[0];
  if (chain) {
    return chains[chain].decryptComment({ accountId, activity: { ...activity, encryptedComment }, password });
  }

  return '';
}

export async function fetchActivityDetails(accountId: string, activity: ApiActivity) {
  for (const chain of getActivityChains(activity)) {
    const newActivity = await chains[chain].fetchActivityDetails(accountId, activity);
    if (newActivity) {
      return newActivity;
    }
  }

  return activity;
}

export async function fetchTransactionById(
  { chain, network, walletAddress, ...restOptions }: ApiFetchTransactionByIdOptions & { chain: ApiChain },
): Promise<ApiActivity[]> {
  const isTxId = 'txId' in restOptions;
  const options = isTxId
    ? { chain, network, txId: restOptions.txId, walletAddress }
    : { chain, network, txHash: restOptions.txHash, walletAddress };

  logDebug('fetchTransactionById', options);

  return chains[chain].fetchTransactionById(options);
}

async function fetchAndCheckActivitySlice(chain: ApiChain, options: ApiFetchActivitySliceOptions) {
  const activities = await chains[chain].fetchActivitySlice(options);

  // Sorting is important for `mergeSortedActivities`, so it's checked in the debug mode
  if (DEBUG && !areActivitiesSortedAndUnique(activities)) {
    logDebugError(`The all activity slice of ${chain} is not sorted properly or has duplicates`, options);
  }

  return activities;
}
