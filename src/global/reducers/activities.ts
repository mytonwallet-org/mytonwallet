import type { ApiActivity, ApiChain } from '../../api/types';
import type { AccountState, GlobalState } from '../types';

import {
  getActivityTokenSlugs,
  getIsActivityPending,
  getIsActivitySuitableForFetchingTimestamp,
  getIsTxIdLocal,
} from '../../util/activities';
import { mergeSortedActivityIds, mergeSortedActivityIdsToMaxTime } from '../../util/activities/order';
import { buildCollectionByKey, extractKey, mapValues, swapKeysAndValues, unique } from '../../util/iteratees';
import { replaceActivityId } from '../helpers/misc';
import { selectAccountOrAuthAccount, selectAccountState } from '../selectors';
import { updateAccountState } from './misc';

/**
 * Handles the `initialActivities` update, which delivers the latest activity history after the account is added.
 * The given activity lists must be sorted and contain no pending or local activities.
 */
export function addInitialActivities(
  global: GlobalState,
  accountId: string,
  mainActivities: ApiActivity[],
  bySlug: Record<string, ApiActivity[]>,
  chain: ApiChain,
) {
  const { activities } = selectAccountState(global, accountId) || {};
  let { byId, idsMain, areInitialActivitiesLoaded } = activities || {};

  byId = { ...byId, ...buildCollectionByKey(mainActivities, 'id') };

  areInitialActivitiesLoaded = {
    ...areInitialActivitiesLoaded,
    [chain]: true,
  };

  // Activities from different blockchains arrive separately, which causes the order to be disrupted
  idsMain = mergeSortedActivityIdsToMaxTime(byId, extractKey(mainActivities, 'id'), idsMain ?? []);

  // Enforcing the requirement to have the id list undefined if it hasn't loaded yet
  if (idsMain.length === 0 && !areAllInitialActivitiesLoaded(global, accountId, areInitialActivitiesLoaded)) {
    idsMain = undefined;
  }

  global = updateAccountState(global, accountId, {
    activities: {
      ...activities,
      idsMain,
      byId,
      areInitialActivitiesLoaded,
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
    idsMain = mergeSortedActivityIds(byId, idsMain ?? [], extractKey(pastActivities, 'id'));

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
    },
  });
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
  // The initial activities may be loaded and added before the authentication completes
  const byChain = selectAccountOrAuthAccount(global, accountId)?.byChain ?? {};
  const chains = Object.keys(byChain) as (keyof typeof byChain)[];

  return chains.every((chain) => newAreInitialActivitiesLoaded[chain]);
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
