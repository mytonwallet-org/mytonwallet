import type { ApiActivity } from '../../api/types';

import { mergeSortedArrays, unique, uniqueByKey } from '../iteratees';
import { logDebugError } from '../logs';
import { getIsActivityPending } from './index';

function compareActivities(a: ApiActivity, b: ApiActivity, isAsc = false) {
  // When called from ID-based functions, `activityById[id]` may be `undefined`
  // if `byId` was updated before the merge (e.g., activity removed or not yet added)
  if (!a || !b) {
    if (!a && !b) return 0;
    return !a ? 1 : -1;
  }

  // The activity sorting is tuned to match the Toncenter API sorting as close as possible.
  // Putting the pending activities first, because when they get confirmed, their timestamp gets bigger than any current
  // confirmed activity timestamp. This reduces the movement in the activity list.
  let value = (getIsActivityPending(a) ? 1 : 0) - (getIsActivityPending(b) ? 1 : 0);
  if (value === 0) {
    value = a.timestamp - b.timestamp;
    if (value === 0) {
      value = a.id > b.id ? 1 : a.id < b.id ? -1 : 0;
    }
  }
  return isAsc ? value : -value;
}

/**
 * Makes sure `activities` are suitable for `mergeSortedActivities` input.
 * Use the `mergeSortedActivities` function instead when possible.
 */
export function sortActivities(activities: readonly ApiActivity[], isAsc?: boolean) {
  const uniqueActivities = uniqueByKey(activities, 'id');
  return uniqueActivities.sort((a1, a2) => compareActivities(a1, a2, isAsc));
}

/**
 * Makes sure `ids` are suitable for `mergeSortedActivityIds` input.
 * Use the `mergeSortedActivityIds` function instead when possible.
 */
function sortActivityIds(activityById: Record<string, ApiActivity>, ids: readonly string[], isAsc?: boolean) {
  const uniqueIds = unique(ids);
  return uniqueIds.sort((id1, id2) => compareActivities(activityById[id1], activityById[id2], isAsc));
}

export function mergeSortedActivities(...lists: (readonly ApiActivity[])[]) {
  // Input lists may be unsorted when `byId` is updated before the merge (e.g., pending status changed).
  // This is expected — we detect and re-sort to ensure correct merge behavior.
  for (let i = 0; i < lists.length; i++) {
    if (!areActivitiesSortedAndUnique(lists[i])) {
      logDebugError(`Activity list ${i} is unsorted or has duplicates`, { stack: new Error().stack });
      lists[i] = sortActivities(lists[i]);
    }
  }

  return uniqueByKey(
    mergeSortedArrays(lists, (a1, a2) => compareActivities(a1, a2), true),
    'id',
  );
}

export function mergeSortedActivityIds(activityById: Record<string, ApiActivity>, ...lists: (readonly string[])[]) {
  // Input lists may be unsorted when `byId` is updated before the merge (e.g., pending status changed).
  // This is expected — we detect and re-sort to ensure correct merge behavior.
  for (let i = 0; i < lists.length; i++) {
    if (!areActivityIdsSortedAndUnique(activityById, lists[i])) {
      logDebugError(`Activity id list ${i} is unsorted or has duplicates`, { stack: new Error().stack });
      lists[i] = sortActivityIds(activityById, lists[i]);
    }
  }

  return unique(mergeSortedArrays(
    lists,
    (id1, id2) => compareActivities(activityById[id1], activityById[id2]),
    true,
  ));
}

export function mergeSortedActivitiesToMaxTime(...lists: (readonly ApiActivity[])[]) {
  const fromTimestamp = Math.max(
    ...lists.map((activities) => activities.length ? activities[activities.length - 1].timestamp : -Infinity),
  );

  const filterPredicate = ({ timestamp }: ApiActivity) => timestamp >= fromTimestamp;

  return mergeSortedActivities(
    ...lists.map((activities) => activities.filter(filterPredicate)),
  );
}

export function mergeSortedActivityIdsToMaxTime(
  activityById: Record<string, ApiActivity>,
  ...lists: (readonly string[])[]
) {
  const fromTimestamp = Math.max(
    ...lists.map((ids) => ids.length ? activityById[ids[ids.length - 1]]?.timestamp ?? -Infinity : -Infinity),
  );

  const filterPredicate = (id: string) => (activityById[id]?.timestamp ?? -Infinity) >= fromTimestamp;

  return mergeSortedActivityIds(
    activityById,
    ...lists.map((ids) => ids.filter(filterPredicate)),
  );
}

export function areActivitiesSortedAndUnique(activities: readonly ApiActivity[], isAsc?: boolean) {
  for (let i = 1; i < activities.length; i++) {
    if (compareActivities(activities[i - 1], activities[i], isAsc) >= 0) {
      return false;
    }
  }

  return true;
}

function areActivityIdsSortedAndUnique(
  activityById: Record<string, ApiActivity>,
  ids: readonly string[],
  isAsc?: boolean,
) {
  for (let i = 1; i < ids.length; i++) {
    if (compareActivities(activityById[ids[i - 1]], activityById[ids[i]], isAsc) >= 0) {
      return false;
    }
  }

  return true;
}
