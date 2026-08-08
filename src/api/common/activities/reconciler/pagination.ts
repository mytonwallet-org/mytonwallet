import type { ApiActivity } from '../../../types';

import { parseTxId } from '../../../../util/activities';

/** Trace id used by the reconciler for page-boundary consistency checks. */
export function getActivityTraceBoundaryId(activity: ApiActivity) {
  return activity.extra?.mtwAggregator?.traceId ?? parseTxId(activity.id).hash;
}

export function getLastPageTraceBoundaryId(activities: readonly ApiActivity[]) {
  const lastActivity = activities[activities.length - 1];
  return lastActivity ? getActivityTraceBoundaryId(lastActivity) : undefined;
}

export function trimPageBoundaryTraceActivities(
  activities: readonly ApiActivity[],
  maxTrimmedActivities = 10,
): ApiActivity[] {
  if (!activities.length) return [...activities];

  const boundaryTraceId = getLastPageTraceBoundaryId(activities);
  if (!boundaryTraceId) return [...activities];

  let firstTrimmedIndex = activities.length;
  while (firstTrimmedIndex > 0) {
    const activity = activities[firstTrimmedIndex - 1];
    if (getActivityTraceBoundaryId(activity) !== boundaryTraceId) break;
    firstTrimmedIndex--;
  }

  const trimmed = activities.slice(0, firstTrimmedIndex);
  const trimmedCount = activities.length - trimmed.length;

  // Returning an empty page causes pagination flicker/retries with no progress. If the entire page is one large trace,
  // keep it raw and let the conservative TON reconciler refuse unsafe aggregation unless the slice proves a clean route.
  if (trimmed.length === 0) return [...activities];

  // A very large boundary trace is likely an unusually busy block/trace or malformed input. Keep it raw rather than
  // dropping too much visible history from the page.
  return trimmedCount > 0 && trimmedCount < maxTrimmedActivities ? trimmed : [...activities];
}
