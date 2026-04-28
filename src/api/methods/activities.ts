import type {
  ApiActivity,
  ApiChain,
  ApiFetchActivitySliceOptions,
  ApiFetchTransactionByIdOptions,
  ApiTransactionActivity,
} from '../types';

import { DEBUG } from '../../config';
import { getActivityChains, parseTxId } from '../../util/activities';
import { areActivitiesSortedAndUnique, mergeSortedActivitiesToMaxTime } from '../../util/activities/order';
import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
import { unique } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { getChainBySlug } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAccount } from '../common/accounts';
import { swapReplaceActivities } from '../common/swap';

export type ActivitySliceResult = {
  activities: ApiActivity[];
  hasMore: boolean;
};

export async function fetchPastActivities(
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
): Promise<ActivitySliceResult | undefined> {
  try {
    const { activities: rawActivities, hasMore } = tokenSlug
      ? await fetchTokenActivitySlice(accountId, limit, tokenSlug, toTimestamp)
      : await fetchAllActivitySlice(accountId, limit, toTimestamp);

    const activities = await swapReplaceActivities(accountId, rawActivities, tokenSlug);

    return { activities, hasMore };
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
): Promise<ActivitySliceResult> {
  const chain = getChainBySlug(tokenSlug);
  return fetchAndCheckActivitySlice(chain, { accountId, tokenSlug, toTimestamp, limit }, false);
}

async function fetchAllActivitySlice(
  accountId: string,
  limit: number,
  toTimestamp?: number,
): Promise<ActivitySliceResult> {
  const account = await fetchStoredAccount(accountId);
  // `getOrderedAccountChains` drops stored keys absent from CHAIN_CONFIG; without it a stale
  // chain crashes `getChainConfig(...).chainStandard` and silently aborts the whole slice.
  const accountChains = getOrderedAccountChains(account.byChain);

  const deduplicatedChains = unique(accountChains.map((chain) => getChainConfig(chain).chainStandard || chain));

  // `Promise.allSettled` so a single chain failure (transient API error, unknown token, stale account)
  // does not erase the whole batch. Failed chains contribute an empty slice; the rest stay visible.
  const settled = await Promise.allSettled(
    // The `fetchActivitySlice` method of all chains must return sorted activities
    deduplicatedChains.map((chain) =>
      fetchAndCheckActivitySlice(chain, { accountId, toTimestamp, limit }, true),
    ),
  );

  let firstRejection: Error | undefined;
  const results: ActivitySliceResult[] = settled.map((settledResult, index) => {
    if (settledResult.status === 'fulfilled') {
      return settledResult.value;
    }
    logDebugError(`fetchAllActivitySlice ${deduplicatedChains[index]}`, settledResult.reason);
    firstRejection ??= settledResult.reason;
    return { activities: [], hasMore: false };
  });

  // If every chain came back empty and at least one failed, we cannot tell "real end of history"
  // from "transient outage". Surface the failure so `fetchPastActivities` returns `undefined` and
  // the UI retries on the next scroll instead of marking the history as ended.
  if (firstRejection && results.every((r) => !r.activities.length)) {
    throw firstRejection;
  }

  const activities = mergeSortedActivitiesToMaxTime(...results.map((r) => r.activities));
  const hasMore = results.some((r) => r.hasMore);

  return { activities, hasMore };
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

async function fetchAndCheckActivitySlice(
  chain: ApiChain,
  options: ApiFetchActivitySliceOptions,
  isCrossChain: boolean,
): Promise<ActivitySliceResult> {
  const chainStandard = getChainConfig(chain).chainStandard;

  let activities: ApiActivity[] = [];

  if (isCrossChain && chainStandard && !options.tokenSlug) {
    activities = await chains[chain].fetchCrossChainActivitySlice(options);
  } else {
    activities = await chains[chain].fetchActivitySlice(options);
  }

  // const activities = await chains[chain].fetchActivitySlice(options);

  // Sorting is important for `mergeSortedActivities`, so it's checked in the debug mode
  if (DEBUG && !areActivitiesSortedAndUnique(activities)) {
    logDebugError(`The all activity slice of ${chain} is not sorted properly or has duplicates`, options);
  }

  // When we receive exactly `limit` activities, the last trace might be incomplete
  // (e.g., only some swap actions without the fee transfer). We trim that trace
  // so it will be loaded completely on the next page.
  if (options.limit && activities.length === options.limit) {
    return {
      activities: trimLastIncompleteTrace(activities),
      hasMore: true,
    };
  }

  return {
    activities,
    hasMore: false,
  };
}

function trimLastIncompleteTrace(activities: ApiActivity[]): ApiActivity[] {
  if (!activities.length) {
    return activities;
  }

  // TODO: This is actually incorrect, since `sortActivities` may disrupt the grouping of activities by trace.
  // There might also be more than one incomplete trace, but currently we have no way to handle that.
  // We only trim the trace of the last activity (supposing it's the last and only incomplete trace)
  // if it contains fewer than 10 activities.
  // We limit the number of excluded incomplete activities to 10 to prevent UI flickering.
  const lastTraceId = parseTxId(activities[activities.length - 1].id).hash;
  const trimmed = activities.filter((activity) => parseTxId(activity.id).hash !== lastTraceId);
  if (trimmed.length === 0) {
    return activities;
  }
  return activities.length - trimmed.length < 10 ? trimmed : activities;
}
