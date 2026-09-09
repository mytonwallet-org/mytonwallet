import type {
  ApiActivity,
  ApiChain,
  ApiFetchActivitySliceOptions,
  ApiFetchTransactionByIdOptions,
  ApiSwapActivity,
  ApiTransactionActivity,
} from '../types';

import { DEBUG } from '../../config';
import { throwIfAborted } from '../../util/abortSignal';
import { getActivityChains, getIsActivityPendingForUser, parseTxId } from '../../util/activities';
import { areActivitiesSortedAndUnique, mergeSortedActivitiesToMaxTime } from '../../util/activities/order';
import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
import { unique } from '../../util/iteratees';
import { logDebug, logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import { getChainBySlug } from '../../util/tokens';
import chains from '../chains';
import { fetchStoredAccount } from '../common/accounts';
import {
  getSwapRowBackendId,
  getSwapRowKeys,
  isSwapRow,
  normalizeIdentifier,
  preserveActivityStatusProgress,
  reconcileActivityUpdate as projectActivityUpdate,
} from '../common/activities/swapReconciler';
import {
  getSwapHistoryAddressByChain,
  swapGetHistory,
  swapGetHistoryByAddresses,
  swapItemToActivity,
  swapReplaceActivities,
} from '../common/swap';
import { requireSwapMethods } from './optional';

export type ActivitySliceResult = {
  activities: ApiActivity[];
  hasMore: boolean;
};

export type ReconcileActivityUpdateResult = Awaited<ReturnType<typeof reconcileActivityUpdate>>;

type ActivitiesPatch = {
  accountId: string;
  upsert: ApiActivity[];
  removeIds: string[];
  replacedIds: Record<string, string>;
};

const PRE_RENDER_BACKEND_TIMEOUT_MS = 1500;

export async function fetchPastActivities(
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
  options?: { signal?: AbortSignal; shouldThrowOnError?: boolean },
): Promise<ActivitySliceResult | undefined> {
  const { signal, shouldThrowOnError = false } = options ?? {};
  try {
    if (tokenSlug) {
      const { activities: rawActivities, hasMore } = await fetchTokenActivitySlice(
        accountId, limit, tokenSlug, toTimestamp, signal,
      );
      const activities = await swapReplaceActivities(accountId, rawActivities, tokenSlug, undefined, signal);

      return { activities, hasMore };
    }

    const result = await fetchAllActivitySlice(accountId, limit, toTimestamp, signal);
    return result;
  } catch (err) {
    throwIfAborted(signal);
    logDebugError('fetchPastActivities', tokenSlug, err);
    if (shouldThrowOnError) throw err;
    return undefined;
  }
}

/**
 * Projects a live activity update for a platform store. Two backend lookups happen before render so that rows are
 * hidden under their swap in the same commit instead of flickering as separate rows: a pending trace whose hash no
 * known swap row carries (a swap submitted from another device) is looked up by hash, and a new visible raw
 * transaction arriving while a CEX swap is pending refreshes the provider state.
 */
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
  const incomingActivities = [...(pendingActivities ?? []), ...confirmedActivities];
  const contextActivities = options.contextActivities ?? previousActivities;
  const timeoutMs = options.forceCexRefreshTimeoutMs ?? PRE_RENDER_BACKEND_TIMEOUT_MS;
  const [swapRowsOfPendingTraces, cexPatch] = await Promise.all([
    fetchSwapRowsOfPendingTraces(
      accountId,
      pendingActivities ?? [],
      [...previousActivities, ...contextActivities, ...confirmedActivities],
      timeoutMs,
    ),
    fetchActiveCexPatchBeforeRender(accountId, incomingActivities, contextActivities, timeoutMs),
  ]);
  const result = projectActivityUpdate(
    previousActivities,
    [...confirmedActivities, ...swapRowsOfPendingTraces],
    pendingActivities,
    contextActivities,
  );

  const patch: ActivitiesPatch = {
    accountId,
    upsert: result.upsert,
    removeIds: result.removeIds,
    replacedIds: result.replacedIds,
  };
  if (!cexPatch) {
    return { confirmedActivities: result.confirmedActivities, pendingActivities: result.pendingActivities, patch };
  }

  const mergedPatch = mergeActivityPatches(patch, cexPatch);
  const upsertById = new Map(mergedPatch.upsert.map((activity) => [activity.id, activity]));
  const apply = (activity: ApiActivity) => upsertById.get(activity.id) ?? activity;

  return {
    confirmedActivities: result.confirmedActivities.map(apply),
    pendingActivities: result.pendingActivities?.map(apply),
    patch: mergedPatch,
  };
}

/**
 * The socket delivers a pending trace before any history enrichment. When no known swap row carries its hash, the
 * swap was submitted elsewhere (another device) and its row is fetched by hash so the trace is projected under it
 * from the first render. Both history endpoints answer with rows matching either the hashes or a time window, so
 * the window is collapsed to the current moment.
 */
async function fetchSwapRowsOfPendingTraces(
  accountId: string,
  pendingActivities: readonly ApiActivity[],
  knownActivities: readonly ApiActivity[],
  timeoutMs: number,
): Promise<ApiSwapActivity[]> {
  const knownKeys = new Set(knownActivities.filter(isSwapRow).flatMap(getSwapRowKeys));
  const hashes = unique(pendingActivities
    .filter((activity) => !isSwapRow(activity))
    .flatMap((activity) => [activity.externalMsgHashNorm, parseTxId(activity.id).hash])
    .map(normalizeIdentifier)
    .filter((hash): hash is string => Boolean(hash) && !knownKeys.has(hash)));
  if (!hashes.length) return [];

  const rows = await Promise.race([
    (async () => {
      const addressByChain = getSwapHistoryAddressByChain(await fetchStoredAccount(accountId));
      const now = Date.now();
      const params = { fromTimestamp: now, toTimestamp: now, hashes };
      const [cexRows, dexRows] = await Promise.all([
        Object.keys(addressByChain).length
          ? swapGetHistoryByAddresses(addressByChain, { ...params, isCex: true })
          : [],
        addressByChain.ton ? swapGetHistory(addressByChain.ton, { ...params, isCex: false }) : [],
      ]);
      return [...cexRows, ...dexRows];
    })().catch((err) => {
      logDebugError('fetchSwapRowsOfPendingTraces', err);
      return [];
    }),
    pause(timeoutMs).then(() => []),
  ]);

  return rows.map((row) => swapItemToActivity(row));
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
  if (!hasVisibleRawTransaction) return undefined;

  const pendingCexSwaps = contextActivities.filter((activity): activity is ApiSwapActivity => {
    return isSwapRow(activity) && Boolean(activity.cex) && getIsActivityPendingForUser(activity);
  });
  if (!pendingCexSwaps.length) return undefined;

  const projectionContext = uniqueActivitiesById([...contextActivities, ...incomingActivities]);
  const result = await Promise.race([
    requireSwapMethods().fetchSwaps(
      accountId,
      unique(pendingCexSwaps.map(getSwapRowBackendId)).map((id) => ({ id, chain: 'ton' as const })),
      projectionContext,
      { forceProviderRefresh: true },
    ).catch(() => undefined),
    pause(timeoutMs).then(() => undefined),
  ]);

  const patch = result?.patch;
  return patch && (patch.upsert.length || patch.removeIds.length) ? patch : undefined;
}

function mergeActivityPatches(first: ActivitiesPatch, second: ActivitiesPatch): ActivitiesPatch {
  const upsertById = new Map<string, ApiActivity>();
  for (const activity of first.upsert) upsertById.set(activity.id, activity);
  for (const activity of second.upsert) {
    upsertById.set(activity.id, preserveActivityStatusProgress(upsertById.get(activity.id), activity));
  }

  return {
    ...first,
    upsert: Array.from(upsertById.values()),
    removeIds: unique([...first.removeIds, ...second.removeIds]),
    replacedIds: { ...first.replacedIds, ...second.replacedIds },
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
  signal?: AbortSignal,
): Promise<ActivitySliceResult> {
  const chain = getChainBySlug(tokenSlug);
  return fetchAndCheckActivitySlice(chain, {
    accountId,
    tokenSlug,
    toTimestamp,
    limit,
    ...(signal && { signal }),
  });
}

async function fetchAllActivitySlice(
  accountId: string,
  limit: number,
  toTimestamp?: number,
  signal?: AbortSignal,
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
      fetchAndCheckActivitySlice(chain, {
        accountId,
        toTimestamp,
        limit,
        ...(signal && { signal }),
      }, { shouldFetchCrossChain: true }),
    ),
  );
  throwIfAborted(signal);

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

  const rawActivities = mergeSortedActivitiesToMaxTime(...results.map((r) => r.activities));
  const activities = await swapReplaceActivities(accountId, rawActivities, undefined, undefined, signal);
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

export async function fetchActivityDetails(accountId: string, activity: ApiActivity, signal?: AbortSignal) {
  for (const chain of getActivityChains(activity)) {
    const newActivity = await chains[chain].fetchActivityDetails(accountId, activity, signal);
    throwIfAborted(signal);
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
  {
    shouldFetchCrossChain = false,
  }: { shouldFetchCrossChain?: boolean } = {},
): Promise<ActivitySliceResult> {
  const chainStandard = getChainConfig(chain).chainStandard;

  let activities: ApiActivity[] = [];

  if (shouldFetchCrossChain && chainStandard && !options.tokenSlug) {
    activities = await chains[chain].crosschain!.fetchCrossChainActivitySlice(options);
  } else {
    activities = await chains[chain].fetchActivitySlice(options);
  }
  throwIfAborted(options.signal);

  // Sorting is important for `mergeSortedActivities`, so it's checked in the debug mode
  if (DEBUG && !areActivitiesSortedAndUnique(activities)) {
    logDebugError(`The all activity slice of ${chain} is not sorted properly or has duplicates`, options);
  }

  // A page that hits the limit may cut the last trace (e.g. some swap legs without the rest). The cut trace is
  // trimmed so that the next page loads it whole and the swap summary nets every leg.
  if (options.limit && activities.length === options.limit) {
    return { activities: trimPageBoundaryTrace(activities), hasMore: true };
  }

  return { activities, hasMore: false };
}

const MAX_TRIMMED_BOUNDARY_ACTIVITIES = 10;

function trimPageBoundaryTrace(activities: readonly ApiActivity[]): ApiActivity[] {
  const traceIdOf = (activity: ApiActivity) => parseTxId(activity.id).hash;
  const boundaryTraceId = activities.length ? traceIdOf(activities[activities.length - 1]) : undefined;
  if (!boundaryTraceId) return [...activities];

  let firstTrimmedIndex = activities.length;
  while (firstTrimmedIndex > 0 && traceIdOf(activities[firstTrimmedIndex - 1]) === boundaryTraceId) {
    firstTrimmedIndex--;
  }

  const trimmedCount = activities.length - firstTrimmedIndex;
  // An empty page would stall pagination, and a trace larger than the limit cannot be completed by paging anyway
  if (firstTrimmedIndex === 0 || trimmedCount >= MAX_TRIMMED_BOUNDARY_ACTIVITIES) return [...activities];

  return activities.slice(0, firstTrimmedIndex);
}
