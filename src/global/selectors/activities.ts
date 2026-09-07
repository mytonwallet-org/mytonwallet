import type { ApiActivity, ApiActivityTimestamps, ApiChain } from '../../api/types';
import type { GlobalState } from '../types';

import { getActivityContinuationTimestamp, getIsTxIdLocal } from '../../util/activities';
import { compact, mapValues } from '../../util/iteratees';
import { selectAccountState } from './accounts';

export function selectNewestActivityTimestamps(global: GlobalState, accountId: string): ApiActivityTimestamps {
  return mapValues(
    selectAccountState(global, accountId)?.activities?.newestActivitiesBySlug || {},
    ({ timestamp }) => timestamp,
  );
}

export function selectLastActivityTimestamp(
  global: GlobalState,
  accountId: string,
  tokenSlug?: string,
): number | undefined {
  const activities = selectAccountState(global, accountId)?.activities;
  if (!activities) return undefined;

  const { byId, idsMain, idsBySlug } = activities;
  const ids = (tokenSlug ? idsBySlug?.[tokenSlug] : idsMain) || [];

  return getActivityContinuationTimestamp(ids, (id) => byId[id]);
}

export function selectLocalActivitiesSlow(global: GlobalState, accountId: string) {
  const { byId = {}, localActivityIds = [] } = global.byAccountId[accountId]?.activities ?? {};

  return compact(localActivityIds.map((id) => byId[id]));
}

/** Doesn't include local activities */
export function selectPendingActivitiesSlow(global: GlobalState, accountId: string, chain: ApiChain) {
  const { byId = {}, pendingActivityIds = {} } = global.byAccountId[accountId]?.activities ?? {};
  const ids = pendingActivityIds[chain] ?? [];

  return compact(ids.map((id) => byId[id]));
}

export function selectRecentNonLocalActivitiesSlow(global: GlobalState, accountId: string, maxCount: number) {
  const { byId = {}, idsMain = [] } = global.byAccountId[accountId]?.activities ?? {};
  const result: ApiActivity[] = [];

  for (const id of idsMain) {
    if (result.length >= maxCount) {
      break;
    }
    if (getIsTxIdLocal(id)) {
      continue;
    }
    const activity = byId[id];
    if (activity) {
      result.push(activity);
    }
  }

  return result;
}

export function selectIsHistoryEndReached(global: GlobalState, accountId: string, tokenSlug?: string) {
  const accountState = selectAccountState(global, accountId);
  const { isMainHistoryEndReached, isHistoryEndReachedBySlug } = accountState?.activities ?? {};

  return tokenSlug
    ? !!isHistoryEndReachedBySlug?.[tokenSlug]
    : !!isMainHistoryEndReached;
}

/** If returns `undefined`, the activities haven't been loaded yet. If returns `[]`, there are no activities. */
export function selectActivityHistoryIds(global: GlobalState, accountId: string, tokenSlug?: string) {
  const { idsMain, idsBySlug } = selectAccountState(global, accountId)?.activities ?? {};

  return tokenSlug
    ? idsBySlug?.[tokenSlug]
    : idsMain;
}

/** Whether the last activity history request failed. Tells an empty list apart from a failed one. */
export function selectHasActivityHistoryError(global: GlobalState, accountId: string, tokenSlug?: string) {
  const { hasMainHistoryError, hasHistoryErrorBySlug } = selectAccountState(global, accountId)?.activities ?? {};

  return tokenSlug
    ? !!hasHistoryErrorBySlug?.[tokenSlug]
    : !!hasMainHistoryError;
}
