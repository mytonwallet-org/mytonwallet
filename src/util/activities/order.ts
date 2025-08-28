import type { ApiActivity } from '../../api/types';

import { mergeSortedArrays } from '../iteratees';
import { getIsActivityPending } from './index';

function compareActivities(a: ApiActivity, b: ApiActivity, isAsc = false) {
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
 * Use the `mergeSortedActivities` function instead when possible.
 */
export function sortActivities(activities: ApiActivity[], isAsc?: boolean) {
  return activities.sort((a1, a2) => compareActivities(a1, a2, isAsc));
}

export function mergeSortedActivities(array1: readonly ApiActivity[], array2: readonly ApiActivity[], isAsc?: boolean) {
  return mergeSortedArrays(array1, array2, (a1, a2) => compareActivities(a1, a2, isAsc), true);
}

export function mergeSortedActivityIds(
  ids1: readonly string[],
  ids2: readonly string[],
  activityById: Record<string, ApiActivity>,
  isAsc?: boolean,
) {
  return mergeSortedArrays(
    ids1,
    ids2,
    (id1, id2) => compareActivities(activityById[id1], activityById[id2], isAsc),
    true,
  );
}

export function mergeSortedActivitiesToMaxTime<T extends readonly ApiActivity[]>(array1: T, array2: T) {
  if (!array1.length) return array2;
  if (!array2.length) return array1;

  const fromTimestamp = Math.max(
    array1[array1.length - 1].timestamp,
    array2[array2.length - 1].timestamp,
  );

  const filterPredicate = ({ timestamp }: ApiActivity) => timestamp >= fromTimestamp;

  return mergeSortedActivities(
    array1.filter(filterPredicate),
    array2.filter(filterPredicate),
  );
}

export function mergeSortedActivityIdsToMaxTime<T extends readonly string[]>(
  ids1: T,
  ids2: T,
  activityById: Record<string, ApiActivity>,
) {
  if (!ids1.length) return ids2;
  if (!ids2.length) return ids1;

  const fromTimestamp = Math.max(
    activityById[ids1[ids1.length - 1]].timestamp,
    activityById[ids2[ids2.length - 1]].timestamp,
  );

  const filterPredicate = (id: string) => activityById[id].timestamp >= fromTimestamp;

  return mergeSortedActivityIds(
    ids1.filter(filterPredicate),
    ids2.filter(filterPredicate),
    activityById,
  );
}
