import type { ApiActivity, ApiSwapActivity } from '../../api/types';
import type { AccountState, GlobalState } from '../types';

import { getIsActivityPendingForUser, getIsBackendSwapId } from '../../util/activities';
import { getChainBySlug } from '../../util/tokens';
import { selectAccountState } from '../selectors';

const CEX_SWAP_REFRESH_CONTEXT_LIMIT = 250;

/** CEX and cross-chain swaps settle on the backend after their source transaction, so pending ones are polled */
export function selectPendingBackendSwapActivities(global: GlobalState, accountId: string) {
  const { activities } = selectAccountState(global, accountId) ?? {};
  if (!activities) return [];

  return Object.values(activities.byId).filter((activity) => {
    return activity.kind === 'swap'
      && (Boolean(activity.cex) || getIsCrossChainBackendSwap(activity))
      && getIsActivityPendingForUser(activity);
  });
}

export function getIsCrossChainBackendSwap(activity: ApiSwapActivity) {
  return getIsBackendSwapId(activity.id) && getChainBySlug(activity.from) !== getChainBySlug(activity.to);
}

export function selectCexSwapRefreshContextActivities(
  activities: NonNullable<AccountState['activities']>,
  pendingCexSwaps: ApiActivity[],
  extraActivities: ApiActivity[] = [],
) {
  const byId = { ...activities.byId };
  const ids = new Set<string>();
  const context: ApiActivity[] = [];
  const include = (activity: ApiActivity | undefined) => {
    if (!activity || ids.has(activity.id) || context.length >= CEX_SWAP_REFRESH_CONTEXT_LIMIT) return;
    ids.add(activity.id);
    context.push(activity);
  };
  const includeId = (id: string) => include(byId[id]);

  // Active CEX/local/pending context is needed to decide whether an incoming row requires a forced refresh and to
  // apply the resulting identity-only projection. It must win over a bulk incoming/history slice.
  const activeCexSwaps = [
    ...pendingCexSwaps,
    ...Object.values(byId).filter((activity) => activity.kind === 'swap'
      && Boolean(activity.cex) && getIsActivityPendingForUser(activity)),
  ];
  activeCexSwaps.forEach(include);
  // Hidden SDK-owned CEX sources are intentionally absent from some presentation indexes. Keep them in refresh context
  // so a later provider response can issue an authoritative unhide patch.
  Object.values(byId)
    .filter((activity) => activity.extra?.reconciliation?.reason === 'cex-swap')
    .forEach(include);
  (activities.localActivityIds ?? []).forEach(includeId);
  Object.values(activities.pendingActivityIds ?? {}).forEach((pendingIds) => pendingIds?.forEach(includeId));
  for (const activity of extraActivities) {
    byId[activity.id] = activity;
    include(activity);
  }
  (activities.idsMain ?? []).forEach(includeId);
  Object.values(activities.idsBySlug ?? {}).forEach((slugIds) => slugIds.forEach(includeId));

  return context;
}
