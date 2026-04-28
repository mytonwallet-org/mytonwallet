import type { ApiActivity, ApiChain } from '../../api/types';
import type { AccountState, GlobalState } from '../types';

import {
  getActivityChains,
  getActivityTokenSlugs,
  getIsActivityPending,
  getIsActivitySuitableForFetchingTimestamp,
  getIsTxIdLocal,
} from '../../util/activities';
import { mergeSortedActivityIds } from '../../util/activities/order';
import { getOrderedAccountChains } from '../../util/chain';
import { buildCollectionByKey, extractKey, mapValues, swapKeysAndValues, unique } from '../../util/iteratees';
import { replaceActivityId } from '../helpers/misc';
import { selectAccountOrAuthAccount, selectAccountState } from '../selectors';
import { updateAccountState } from './misc';

/**
 * Handles the `initialActivities` update, which delivers the latest activity history after the account is added.
 * The given activity lists must be sorted and contain no pending or local activities.
 *
 * Each chain reports its initial slice independently. The merged main feed (`idsMain`) is only
 * built once all chains have reported, so partial multi-chain history isn't shown out of order.
 * Until then, only local/pending ids remain visible. Per-chain ids are kept in `mainActivityIdsByChain`
 * (along with each chain's `hasMore` flag) to enable boundary recomputation on subsequent pagination.
 */
export function addInitialActivities(
  global: GlobalState,
  accountId: string,
  mainActivities: ApiActivity[],
  bySlug: Record<string, ApiActivity[]>,
  chain: ApiChain,
  mainHistoryHasMore?: boolean,
) {
  const { activities } = selectAccountState(global, accountId) || {};
  let {
    byId,
    idsMain,
    isMainHistoryEndReached,
    areInitialActivitiesLoaded,
    mainActivityIdsByChain,
    mainHistoryHasMoreByChain,
  } = activities || {};

  // If the chain has already been marked as loaded and this update carries no data, skip the work
  // to avoid re-rendering on every retry of a persistently failing chain (per-chain pollings
  // emit empty `initialActivities` on each failed attempt to unblock `waitInitialActivityLoading`).
  if (
    areInitialActivitiesLoaded?.[chain]
    && mainActivities.length === 0
    && Object.keys(bySlug).length === 0
  ) {
    return global;
  }

  const mainActivityIds = extractKey(mainActivities, 'id');

  byId = { ...byId, ...buildCollectionByKey(mainActivities, 'id') };

  areInitialActivitiesLoaded = {
    ...areInitialActivitiesLoaded,
    [chain]: true,
  };

  mainActivityIdsByChain = {
    ...mainActivityIdsByChain,
    [chain]: mainActivityIds,
  };

  mainHistoryHasMoreByChain = {
    ...mainHistoryHasMoreByChain,
    [chain]: mainHistoryHasMore,
  };

  const areAllLoaded = areAllInitialActivitiesLoaded(global, accountId, areInitialActivitiesLoaded);
  if (areAllLoaded) {
    const initialIdsMain = buildMainActivityIds(byId, mainActivityIdsByChain, mainHistoryHasMoreByChain);
    const initialIds = new Set(Object.values(mainActivityIdsByChain).flat());
    const nonInitialIdsMain = (idsMain ?? []).filter((id) => !initialIds.has(id));

    idsMain = mergeSortedActivityIds(byId, initialIdsMain, nonInitialIdsMain);

    if (areAllMainHistoriesEndReached(global, accountId, mainHistoryHasMoreByChain)) {
      isMainHistoryEndReached = true;
    } else {
      isMainHistoryEndReached = undefined;
    }
  } else {
    // Keep local/pending activities visible while initial multi-chain history is still loading;
    // initial ids are dropped to avoid showing partial history before all chains report in.
    const initialIds = new Set(Object.values(mainActivityIdsByChain).flat());
    const nonInitialIdsMain = (idsMain ?? []).filter((id) => !initialIds.has(id));
    idsMain = nonInitialIdsMain.length > 0 ? nonInitialIdsMain : undefined;
  }

  global = updateAccountState(global, accountId, {
    activities: {
      ...activities,
      idsMain,
      byId,
      isMainHistoryEndReached,
      areInitialActivitiesLoaded,
      mainActivityIdsByChain,
      mainHistoryHasMoreByChain,
    },
  });

  for (const [slug, activities] of Object.entries(bySlug)) {
    global = addPastActivities(global, accountId, slug, activities, activities.length === 0);
  }

  return global;
}

/**
 * Should be used to add only newly created activities. Otherwise, there can occur gaps in the history, because the
 * given activities are added to all the matching token histories.
 */
export function addNewActivities(
  global: GlobalState,
  accountId: string,
  newActivities: readonly ApiActivity[], // Must be sorted
  chain?: ApiChain, // Necessary when adding pending activities
) {
  if (newActivities.length === 0) {
    return global;
  }

  const { activities } = selectAccountState(global, accountId) || {};
  let { byId, idsBySlug, idsMain, newestActivitiesBySlug, localActivityIds, pendingActivityIds } = activities || {};

  byId = { ...byId, ...buildCollectionByKey(newActivities, 'id') };

  // Activities from different blockchains arrive separately, which causes the order to be disrupted
  idsMain = mergeSortedActivityIds(byId, idsMain ?? [], extractKey(newActivities, 'id'));

  const newIdsBySlug = buildActivityIdsBySlug(newActivities);
  idsBySlug = mergeIdsBySlug(idsBySlug, newIdsBySlug, byId);

  newestActivitiesBySlug = getNewestActivitiesBySlug(
    { byId, idsBySlug, newestActivitiesBySlug },
    Object.keys(newIdsBySlug),
  );

  localActivityIds = unique([
    ...(localActivityIds ?? []),
    ...extractKey(newActivities, 'id').filter(getIsTxIdLocal)],
  );

  if (chain) {
    pendingActivityIds = {
      ...pendingActivityIds,
      [chain]: unique([
        ...(pendingActivityIds?.[chain] ?? []),
        ...extractKey(
          newActivities.filter((activity) => getIsActivityPending(activity) && !getIsTxIdLocal(activity.id)),
          'id',
        ),
      ]),
    };
  }

  return updateAccountState(global, accountId, {
    activities: {
      ...activities,
      idsMain,
      byId,
      idsBySlug,
      newestActivitiesBySlug,
      localActivityIds,
      pendingActivityIds,
    },
  });
}

export function addPastActivities(
  global: GlobalState,
  accountId: string,
  tokenSlug: string | undefined, // undefined for main activities
  pastActivities: ApiActivity[], // Must be sorted and contain no pending or local activities
  isEndReached?: boolean,
) {
  const { activities } = selectAccountState(global, accountId) || {};
  let {
    byId, idsBySlug, idsMain, newestActivitiesBySlug, isMainHistoryEndReached, isHistoryEndReachedBySlug,
    mainActivityIdsByChain, mainHistoryHasMoreByChain,
  } = activities || {};

  byId = { ...byId, ...buildCollectionByKey(pastActivities, 'id') };

  if (tokenSlug) {
    idsBySlug = mergeIdsBySlug(idsBySlug, { [tokenSlug]: extractKey(pastActivities, 'id') }, byId);
    newestActivitiesBySlug = getNewestActivitiesBySlug({ byId, idsBySlug, newestActivitiesBySlug }, [tokenSlug]);

    if (isEndReached) {
      isHistoryEndReachedBySlug = {
        ...isHistoryEndReachedBySlug,
        [tokenSlug]: true,
      };
    }
  } else {
    // Track per-chain main-feed ids continuously so the boundary can be recomputed on each
    // pagination event. Otherwise items trimmed at initial load could never come back to the
    // merged feed even though they live in `byId`.
    const newIdsByChain = groupMainPastIdsByChain(pastActivities);
    for (const [chain, chainIds] of Object.entries(newIdsByChain) as [ApiChain, string[]][]) {
      const prev = mainActivityIdsByChain?.[chain] ?? [];
      mainActivityIdsByChain = {
        ...mainActivityIdsByChain,
        [chain]: mergeSortedActivityIds(byId, prev, chainIds),
      };
    }

    // `isEndReached` for the main feed means every chain returned no more activities; promote
    // that to per-chain hasMore=false so the boundary collapses and previously trimmed items
    // can be re-included on the recompute below.
    if (isEndReached && mainHistoryHasMoreByChain) {
      mainHistoryHasMoreByChain = mapValues(mainHistoryHasMoreByChain, () => false);
    }

    if (mainActivityIdsByChain) {
      const recomputedMainIds = buildMainActivityIds(
        byId,
        mainActivityIdsByChain,
        mainHistoryHasMoreByChain ?? {},
      );
      const trackedIds = new Set(Object.values(mainActivityIdsByChain).flat());
      const untrackedIdsMain = (idsMain ?? []).filter((id) => !trackedIds.has(id));
      idsMain = mergeSortedActivityIds(byId, recomputedMainIds, untrackedIdsMain);
    } else {
      idsMain = mergeSortedActivityIds(byId, idsMain ?? [], extractKey(pastActivities, 'id'));
    }

    if (isEndReached) {
      isMainHistoryEndReached = true;
    }
  }

  return updateAccountState(global, accountId, {
    activities: {
      ...activities,
      idsMain,
      byId,
      idsBySlug,
      newestActivitiesBySlug,
      isMainHistoryEndReached,
      isHistoryEndReachedBySlug,
      mainActivityIdsByChain,
      mainHistoryHasMoreByChain,
    },
  });
}

function groupMainPastIdsByChain(pastActivities: ApiActivity[]) {
  // A swap activity touches multiple chains, but it must be attributed to exactly one of them
  // for boundary computation. Attributing it to all of its chains would push its timestamp into
  // every chain's perceived "oldest loaded item", artificially advancing chains that haven't
  // actually paginated that deep — breaking the invariant that the boundary represents a
  // uniform depth across paginating chains and producing a feed with chain-shaped gaps.
  const byChain: Partial<Record<ApiChain, string[]>> = {};
  for (const activity of pastActivities) {
    const [primaryChain] = getActivityChains(activity);
    if (!primaryChain) continue;
    (byChain[primaryChain] ??= []).push(activity.id);
  }
  return byChain;
}

function buildActivityIdsBySlug(activities: readonly ApiActivity[]) {
  return activities.reduce<Record<string, string[]>>((acc, activity) => {
    for (const slug of getActivityTokenSlugs(activity)) {
      acc[slug] ??= [];
      acc[slug].push(activity.id);
    }

    return acc;
  }, {});
}

export function removeActivities(
  global: GlobalState,
  accountId: string,
  _ids: Iterable<string>,
) {
  const { activities } = selectAccountState(global, accountId) || {};
  if (!activities) {
    return global;
  }

  const ids = new Set(_ids); // Don't use `_ids` again, because the iterable may be disposable
  if (ids.size === 0) {
    return global;
  }

  let { byId, idsBySlug, idsMain, newestActivitiesBySlug, localActivityIds, pendingActivityIds } = activities;
  const affectedTokenSlugs = getActivityListTokenSlugs(ids, byId);

  idsBySlug = { ...idsBySlug };
  for (const tokenSlug of affectedTokenSlugs) {
    if (tokenSlug in idsBySlug) {
      idsBySlug[tokenSlug] = idsBySlug[tokenSlug].filter((id) => !ids.has(id));

      if (!idsBySlug[tokenSlug].length) {
        delete idsBySlug[tokenSlug];
      }
    }
  }

  newestActivitiesBySlug = getNewestActivitiesBySlug({ byId, idsBySlug, newestActivitiesBySlug }, affectedTokenSlugs);

  idsMain = idsMain?.filter((id) => !ids.has(id));

  byId = { ...byId };
  for (const id of ids) {
    delete byId[id];
  }

  localActivityIds = localActivityIds?.filter((id) => !ids.has(id));

  pendingActivityIds = pendingActivityIds
    && mapValues(pendingActivityIds, (pendingIds) => pendingIds.filter((id) => !ids.has(id)));

  return updateAccountState(global, accountId, {
    activities: {
      ...activities,
      byId,
      idsBySlug,
      idsMain,
      newestActivitiesBySlug,
      localActivityIds,
      pendingActivityIds,
    },
  });
}

export function updateActivity(global: GlobalState, accountId: string, activity: ApiActivity) {
  const { id } = activity;

  const { activities } = selectAccountState(global, accountId) || {};
  const { byId } = activities ?? {};

  if (!byId || !(id in byId)) {
    return global;
  }

  return updateAccountState(global, accountId, {
    activities: {
      ...activities,
      byId: {
        ...byId,
        [id]: activity,
      },
    },
  });
}

/** Replaces all pending activities in the given account and chain */
export function replacePendingActivities(
  global: GlobalState,
  accountId: string,
  chain: ApiChain,
  pendingActivities: readonly ApiActivity[],
) {
  const { pendingActivityIds } = selectAccountState(global, accountId)?.activities || {};
  global = removeActivities(global, accountId, pendingActivityIds?.[chain] ?? []);
  global = addNewActivities(global, accountId, pendingActivities, chain);
  return global;
}

function getNewestActivitiesBySlug(
  {
    byId, idsBySlug, newestActivitiesBySlug,
  }: Pick<Exclude<AccountState['activities'], undefined>, 'byId' | 'idsBySlug' | 'newestActivitiesBySlug'>,
  tokenSlugs: Iterable<string>,
) {
  newestActivitiesBySlug = { ...newestActivitiesBySlug };

  for (const tokenSlug of tokenSlugs) {
    // The `idsBySlug` arrays must be sorted from the newest to the oldest
    const ids = idsBySlug?.[tokenSlug] ?? [];
    const newestActivityId = ids.find((id) => getIsActivitySuitableForFetchingTimestamp(byId[id]));
    if (newestActivityId) {
      newestActivitiesBySlug[tokenSlug] = byId[newestActivityId];
    } else {
      delete newestActivitiesBySlug[tokenSlug];
    }
  }

  return newestActivitiesBySlug;
}

function getActivityListTokenSlugs(activityIds: Iterable<string>, byId: Record<string, ApiActivity>) {
  const tokenSlugs = new Set<string>();

  for (const id of activityIds) {
    const activity = byId[id];
    if (activity) {
      for (const tokenSlug of getActivityTokenSlugs(activity)) {
        tokenSlugs.add(tokenSlug);
      }
    }
  }

  return tokenSlugs;
}

/** replaceMap: keys - old (removed) activity ids, value - new (added) activity ids */
export function replaceCurrentActivityId(global: GlobalState, accountId: string, replaceMap: Record<string, string>) {
  return updateAccountState(global, accountId, {
    currentActivityId: replaceActivityId(selectAccountState(global, accountId)?.currentActivityId, replaceMap),
  });
}

function mergeIdsBySlug(
  oldIdsBySlug: Record<string, string[]> | undefined,
  newIdsBySlug: Record<string, string[]>,
  activityById: Record<string, ApiActivity>,
) {
  return {
    ...oldIdsBySlug,
    ...mapValues(newIdsBySlug, (newIds, slug) => {
      // There may be newer local transactions in `idsBySlug`, so a sorting is needed
      return mergeSortedActivityIds(activityById, newIds, oldIdsBySlug?.[slug] ?? []);
    }),
  };
}

function areAllInitialActivitiesLoaded(
  global: GlobalState,
  accountId: string,
  newAreInitialActivitiesLoaded: Partial<Record<ApiChain, boolean>>,
) {
  // The initial activities may be loaded and added before the authentication completes.
  // `getOrderedAccountChains` filters stored keys to those still in CHAIN_CONFIG, so a key
  // for a removed chain (whose `loaded` flag is never delivered) doesn't pin this at `false`.
  const byChain = selectAccountOrAuthAccount(global, accountId)?.byChain ?? {};
  const chains = getOrderedAccountChains(byChain);

  return chains.every((chain) => newAreInitialActivitiesLoaded[chain]);
}

function areAllMainHistoriesEndReached(
  global: GlobalState,
  accountId: string,
  mainHistoryHasMoreByChain: Partial<Record<ApiChain, boolean>>,
) {
  const byChain = selectAccountOrAuthAccount(global, accountId)?.byChain ?? {};
  const chains = getOrderedAccountChains(byChain);

  return chains.every((chain) => mainHistoryHasMoreByChain[chain] === false);
}

/**
 * Builds the merged main-feed id list across all chains, applying a pagination boundary
 * to chains that still have unloaded history.
 *
 * The boundary is the latest "oldest known timestamp" among chains still paginating. Below
 * that boundary, any of those chains might have intermediate items not yet loaded, so we
 * trim their below-boundary ids to avoid showing a partial slice of their history.
 *
 * Exhausted chains are exempt: we know their full history, so their oldest items are kept
 * and become visible immediately. They will reappear in correct chronological order as the
 * paginating chains catch up via `addPastActivities`.
 */
function buildMainActivityIds(
  byId: Record<string, ApiActivity>,
  mainActivityIdsByChain: Partial<Record<ApiChain, string[]>>,
  mainHistoryHasMoreByChain: Partial<Record<ApiChain, boolean>>,
) {
  const loadedIdLists = Object.entries(mainActivityIdsByChain) as [ApiChain, string[]][];
  const paginationBoundary = Math.max(
    -Infinity,
    ...loadedIdLists
      .filter(([chain, ids]) => mainHistoryHasMoreByChain[chain] === true && ids.length)
      .map(([, ids]) => byId[ids[ids.length - 1]]?.timestamp ?? -Infinity),
  );

  const idLists = loadedIdLists.map(([chain, chainIds]) => {
    if (mainHistoryHasMoreByChain[chain] !== true) return chainIds;
    return chainIds.filter((id) => (byId[id]?.timestamp ?? -Infinity) >= paginationBoundary);
  });

  return mergeSortedActivityIds(byId, ...idLists);
}

export function updatePendingActivitiesToTrustedByReplacements(
  global: GlobalState,
  accountId: string,
  localActivities: ApiActivity[],
  replacedIds: Record<string, string>,
): GlobalState {
  const accountState = selectAccountState(global, accountId);
  const activitiesState = accountState?.activities;

  if (!activitiesState?.byId) return global;

  const newById = { ...activitiesState.byId } as Record<string, ApiActivity>;

  for (const localActivity of localActivities) {
    const chainActivityId = replacedIds[localActivity.id];

    if (chainActivityId && localActivity.status === 'pendingTrusted') {
      const chainActivity = activitiesState.byId[chainActivityId];

      if (chainActivity?.status === 'pending') {
        newById[chainActivityId] = { ...chainActivity, status: 'pendingTrusted' };
      }
    }
  }

  return updateAccountState(global, accountId, {
    activities: { ...activitiesState, byId: newById },
  });
}

export function updatePendingActivitiesWithTrustedStatus(
  global: GlobalState,
  accountId: string,
  chain: ApiChain | undefined,
  pendingActivities: readonly ApiActivity[] | undefined,
  replacedIds: Record<string, string>,
  prevActivitiesForReplacement: ApiActivity[],
): GlobalState {
  if (!chain || pendingActivities === undefined) return global;

  const reversedReplacedIds: Record<string, string> = swapKeysAndValues(replacedIds);
  const prevById = buildCollectionByKey(prevActivitiesForReplacement, 'id');

  // For pending activities, we need to check the status of the corresponding local activity
  // Only convert 'pending' status to 'pendingTrusted', not 'confirmed' status
  const adjustedPendingActivities = pendingActivities.map((a) => {
    const oldId = reversedReplacedIds[a.id];
    const oldActivity = oldId ? prevById[oldId] : undefined;
    if (oldActivity && oldActivity.status === 'pendingTrusted' && a.status === 'pending') {
      return { ...a, status: 'pendingTrusted' } as ApiActivity;
    }

    return a;
  });

  global = replacePendingActivities(global, accountId, chain, adjustedPendingActivities);

  return global;
}
