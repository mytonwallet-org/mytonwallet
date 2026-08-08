import type {
  ApiActivity,
  ApiChain,
  ApiFetchActivitySliceOptions,
  ApiFetchTransactionByIdOptions,
  ApiSwapActivity,
  ApiTransactionActivity,
} from '../types';

import { DEBUG } from '../../config';
import { getActivityChains, getIsBackendSwapId } from '../../util/activities';
import { areActivitiesSortedAndUnique, mergeSortedActivitiesToMaxTime } from '../../util/activities/order';
import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
import { unique } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import { getChainBySlug } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAccount } from '../common/accounts';
import { getActiveCexSwapStates } from '../common/activities/reconciler/activeCexSwapState';
import { preserveActivityStatusProgress } from '../common/activities/reconciler/matcher';
import { getWalletOperationIntents } from '../common/activities/reconciler/operationIntentStore';
import {
  getLastPageTraceBoundaryId,
  trimPageBoundaryTraceActivities,
} from '../common/activities/reconciler/pagination';
import { reconcileNewActivitiesUpdate } from '../common/activities/reconciler/pendingReconciler';
import { reconcileTonAggregatorActivitiesForAccount } from '../common/activities/reconciler/tonTraceReconciler';
import {
  getBackendDexSwapIdsDuplicatedByTonAggregates as findBackendDexSwapIdsDuplicatedByTonAggregates,
  swapReplaceActivities,
} from '../common/swap';
import { fetchSwaps } from './swap';

export type ActivitySliceResult = {
  activities: ApiActivity[];
  hasMore: boolean;
};

type RawActivitySliceResult = ActivitySliceResult & {
  incompleteTraceIds: string[];
};

export type ReconcileActivityUpdateResult = Awaited<ReturnType<typeof reconcileActivityUpdate>>;

const CEX_PRE_RENDER_FORCE_REFRESH_TIMEOUT_MS = 1500;

export async function getBackendDexSwapIdsDuplicatedByTonAggregates(
  accountId: string,
  activities: readonly ApiActivity[],
) {
  // The store hands over its own copy of a page next to the freshly projected one, and an aggregate listed twice reads
  // as two aggregates answering to one row, which is the ambiguity that keeps suppression from ever firing.
  const uniqueActivities = uniqueActivitiesById(activities);
  const backendSwaps = uniqueActivities.filter((activity): activity is ApiSwapActivity => {
    return activity.kind === 'swap' && !activity.cex && getIsBackendSwapId(activity.id);
  });
  if (!backendSwaps.length) return [];

  const intents = await getWalletOperationIntents(accountId);

  return [...findBackendDexSwapIdsDuplicatedByTonAggregates(uniqueActivities, backendSwaps, intents)];
}

export async function fetchPastActivities(
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
): Promise<ActivitySliceResult | undefined> {
  try {
    if (tokenSlug) {
      const { activities: rawActivities, hasMore, incompleteTraceIds } = await fetchTokenActivitySlice(
        accountId, limit, tokenSlug, toTimestamp,
      );
      const activities = await swapReplaceActivities(
        accountId,
        rawActivities,
        tokenSlug,
        undefined,
        { incompleteTonTraceIds: incompleteTraceIds },
      );

      return { activities, hasMore };
    }

    return fetchAllActivitySlice(accountId, limit, toTimestamp);
  } catch (err) {
    logDebugError('fetchPastActivities', tokenSlug, err);
    return undefined;
  }
}

export async function reconcileActivityUpdate(
  accountId: string,
  previousActivities: readonly ApiActivity[],
  confirmedActivities: readonly ApiActivity[],
  pendingActivities?: readonly ApiActivity[],
  options: {
    contextActivities?: readonly ApiActivity[];
    forceCexRefreshTimeoutMs?: number;
  } = {},
) {
  const incomingActivities = uniqueActivitiesById([...(pendingActivities ?? []), ...confirmedActivities]);
  const [intents, tonProjection, cexPatch] = await Promise.all([
    getWalletOperationIntents(accountId),
    reconcileTonAggregatorActivitiesForAccount(accountId, incomingActivities, { isLiveUpdate: true }),
    fetchActiveCexPatchBeforeRender(
      accountId,
      incomingActivities,
      options.contextActivities ?? previousActivities,
      options.forceCexRefreshTimeoutMs ?? CEX_PRE_RENDER_FORCE_REFRESH_TIMEOUT_MS,
    ),
  ]);
  const projectedActivities = partitionLiveProjectedActivities(
    tonProjection.activities,
    pendingActivities,
  );
  const previousActivitiesWithBackendDexSwaps = uniqueActivitiesById([
    ...previousActivities,
    ...(options.contextActivities ?? []).filter((activity) => {
      return activity.kind === 'swap' && !activity.cex && getIsBackendSwapId(activity.id);
    }),
  ]);

  const baseResult = reconcileNewActivitiesUpdate(
    accountId,
    previousActivitiesWithBackendDexSwaps,
    projectedActivities.confirmedActivities,
    projectedActivities.pendingActivities,
    {
      previousIntents: intents,
      nextIntents: intents,
      terminalTonTraceIds: tonProjection.deaggregatedTraceIds,
      terminalTonExternalMsgHashes: tonProjection.deaggregatedExternalMsgHashes,
    },
  );
  if (!cexPatch) return baseResult;

  const patch = mergeActivityPatches(baseResult.patch, cexPatch);
  const nextPendingActivities = baseResult.pendingActivities
    ? applyPatchToActivityList(baseResult.pendingActivities, patch)
    : undefined;
  const pendingIds = new Set((nextPendingActivities ?? []).map(({ id }) => id));

  return {
    ...baseResult,
    pendingActivities: nextPendingActivities,
    confirmedActivities: patch.upsert.filter((activity) => !pendingIds.has(activity.id)),
    patch,
  };
}

function partitionLiveProjectedActivities(
  activities: readonly ApiActivity[],
  incomingPendingActivities: readonly ApiActivity[] | undefined,
) {
  if (!incomingPendingActivities) {
    return {
      confirmedActivities: [...activities],
      pendingActivities: undefined,
    };
  }

  const incomingPendingIds = new Set(incomingPendingActivities.map(({ id }) => id));
  const confirmedActivities: ApiActivity[] = [];
  const pendingActivities: ApiActivity[] = [];

  for (const activity of activities) {
    const isTonProjection = activity.extra?.reconciliation?.reason === 'ton-aggregated-swap';
    const isPending = isTonProjection
      ? activity.status === 'pending' || activity.status === 'pendingTrusted'
      : incomingPendingIds.has(activity.id)
        && (activity.status === 'pending' || activity.status === 'pendingTrusted');

    (isPending ? pendingActivities : confirmedActivities).push(activity);
  }

  return { confirmedActivities, pendingActivities };
}

async function fetchActiveCexPatchBeforeRender(
  accountId: string,
  incomingActivities: readonly ApiActivity[],
  contextActivities: readonly ApiActivity[],
  timeoutMs: number,
) {
  const hasVisibleRawTransaction = incomingActivities.some((activity) => {
    return activity.kind === 'transaction' && activity.shouldHide !== true;
  });
  if (!hasVisibleRawTransaction) {
    return undefined;
  }

  const activeCexSwaps = await getActiveCexSwapStates(accountId);
  if (!activeCexSwaps.length) return undefined;

  const projectionContext = uniqueActivitiesById([...contextActivities, ...incomingActivities]);
  const result = await Promise.race([
    fetchSwaps(
      accountId,
      activeCexSwaps.map(({ backendSwapId }) => ({ id: backendSwapId, chain: 'ton' as const })),
      projectionContext,
      { forceProviderRefresh: true },
    ).catch(() => undefined),
    pause(timeoutMs).then(() => undefined),
  ]);

  const patch = result?.patch;
  return patch && (patch.upsert.length || patch.removeIds.length) ? patch : undefined;
}

function applyPatchToActivityList(
  activities: readonly ApiActivity[],
  patch: ReturnType<typeof reconcileNewActivitiesUpdate>['patch'],
) {
  const upsertById = new Map(patch.upsert.map((activity) => [activity.id, activity]));
  const removeIds = new Set(patch.removeIds);
  return activities
    .filter((activity) => !removeIds.has(activity.id))
    .map((activity) => upsertById.get(activity.id) ?? activity);
}

function mergeActivityPatches(
  first: ReturnType<typeof reconcileNewActivitiesUpdate>['patch'],
  second: ReturnType<typeof reconcileNewActivitiesUpdate>['patch'],
) {
  const upsertById = new Map<string, ApiActivity>();
  for (const activity of first.upsert) upsertById.set(activity.id, activity);
  for (const activity of second.upsert) {
    upsertById.set(activity.id, preserveActivityStatusProgress(upsertById.get(activity.id), activity));
  }

  return {
    ...first,
    upsert: Array.from(upsertById.values()),
    removeIds: unique([...first.removeIds, ...second.removeIds]),
    replacedIds: {
      ...(first.replacedIds ?? {}),
      ...(second.replacedIds ?? {}),
    },
  };
}

function uniqueActivitiesById(activities: readonly ApiActivity[]) {
  const byId = new Map<string, ApiActivity>();
  for (const activity of activities) byId.set(activity.id, activity);
  return Array.from(byId.values());
}

function fetchTokenActivitySlice(
  accountId: string,
  limit: number,
  tokenSlug: string,
  toTimestamp?: number,
): Promise<RawActivitySliceResult> {
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
  const results: RawActivitySliceResult[] = settled.map((settledResult, index) => {
    if (settledResult.status === 'fulfilled') {
      return settledResult.value;
    }
    logDebugError(`fetchAllActivitySlice ${deduplicatedChains[index]}`, settledResult.reason);
    firstRejection ??= settledResult.reason;
    return { activities: [], hasMore: false, incompleteTraceIds: [] };
  });

  // If every chain came back empty and at least one failed, we cannot tell "real end of history"
  // from "transient outage". Surface the failure so `fetchPastActivities` returns `undefined` and
  // the UI retries on the next scroll instead of marking the history as ended.
  if (firstRejection && results.every((r) => !r.activities.length)) {
    throw firstRejection;
  }

  const rawActivities = mergeSortedActivitiesToMaxTime(...results.map((r) => r.activities));
  const incompleteTraceIds = unique(results.flatMap((result) => result.incompleteTraceIds));
  const activities = await swapReplaceActivities(
    accountId,
    rawActivities,
    undefined,
    undefined,
    { incompleteTonTraceIds: incompleteTraceIds },
  );
  const hasMore = results.some((r) => r.hasMore);

  return { activities, hasMore };
}

export function decryptComment(accountId: string, activity: ApiTransactionActivity, enclaveToken?: string) {
  const { encryptedComment } = activity;
  if (!encryptedComment) {
    return activity.comment ?? '';
  }

  const chain = getActivityChains(activity)[0];
  if (chain) {
    return chains[chain].decryptComment({ accountId, activity: { ...activity, encryptedComment }, enclaveToken });
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
): Promise<RawActivitySliceResult> {
  const chainStandard = getChainConfig(chain).chainStandard;

  let activities: ApiActivity[] = [];

  if (isCrossChain && chainStandard && !options.tokenSlug) {
    activities = await chains[chain].crosschain!.fetchCrossChainActivitySlice(options);
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
  // so it will be loaded completely on the next page. Sorting may move another
  // action from the same trace outside the contiguous tail, so the reconciler
  // must still treat the boundary trace as incomplete in the current slice.
  if (options.limit && activities.length === options.limit) {
    const trimmedActivities = trimPageBoundaryTraceActivities(activities);
    const incompleteTraceId = getLastPageTraceBoundaryId(activities);
    return {
      activities: trimmedActivities,
      hasMore: true,
      incompleteTraceIds: incompleteTraceId ? [incompleteTraceId] : [],
    };
  }

  return {
    activities,
    hasMore: false,
    incompleteTraceIds: [],
  };
}
