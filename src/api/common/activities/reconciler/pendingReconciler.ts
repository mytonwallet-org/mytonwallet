import type { ApiActivity, ApiSwapActivity } from '../../../types';
import type { ReconciledActivitiesPatch, WalletOperationIntent } from './types';

import { parseTxId } from '../../../../util/activities';
import {
  getActivityIdReplacementsFromSdkMatcher,
  normalizeIdentifier,
  preserveActivityStatusProgress,
} from './matcher';

export type PendingReconciliationResult = {
  pendingActivities: ApiActivity[];
  replacedIds: Record<string, string>;
};

export type NewActivitiesReconciliationResult = {
  confirmedActivities: ApiActivity[];
  pendingActivities?: ApiActivity[];
  patch: ReconciledActivitiesPatch;
};

type ReconciliationMatchContext = {
  previousIntents?: readonly WalletOperationIntent[];
  nextIntents?: readonly WalletOperationIntent[];
  terminalTonTraceIds?: readonly string[];
  terminalTonExternalMsgHashes?: readonly string[];
};

/** Pure pending/local replacement foundation. Integration will move platform store callers to SDK patches. */
export function reconcilePendingActivities(
  previousActivities: readonly ApiActivity[],
  incomingPendingActivities: readonly ApiActivity[],
  matchContext: ReconciliationMatchContext = {},
) {
  const replacedIds = getActivityIdReplacementsFromSdkMatcher(
    previousActivities,
    incomingPendingActivities,
    matchContext,
  );
  const previousByNextId = new Map<string, ApiActivity>();

  for (const previousActivity of previousActivities) {
    const nextId = replacedIds[previousActivity.id];
    if (nextId) previousByNextId.set(nextId, previousActivity);
  }

  return {
    pendingActivities: incomingPendingActivities.map((activity) => {
      return preserveActivityStatusProgress(previousByNextId.get(activity.id), activity);
    }),
    replacedIds,
  } satisfies PendingReconciliationResult;
}

/**
 * Builds the SDK-owned deterministic reconciliation projection for an incoming activity update. Platform stores still
 * decide how to merge ids into their presentation caches, but matching, status preservation and old-id removals come
 * from this patch instead of app-specific swap/pending heuristics.
 */
export function reconcileNewActivitiesUpdate(
  accountId: string,
  previousActivities: readonly ApiActivity[],
  incomingConfirmedActivities: readonly ApiActivity[],
  incomingPendingActivities: readonly ApiActivity[] | undefined,
  matchContext: ReconciliationMatchContext = {},
): NewActivitiesReconciliationResult {
  const incomingActivities = [
    ...(incomingPendingActivities ?? []),
    ...incomingConfirmedActivities,
  ];
  const replacedIds = getActivityIdReplacementsFromSdkMatcher(previousActivities, incomingActivities, matchContext);
  const previousByNextId = new Map<string, ApiActivity>();

  for (const previousActivity of previousActivities) {
    const nextId = replacedIds[previousActivity.id];
    if (nextId) previousByNextId.set(nextId, previousActivity);
  }

  const pendingActivities = incomingPendingActivities?.map((activity) => {
    return preserveActivityStatusProgress(previousByNextId.get(activity.id), activity);
  });
  const confirmedActivities = incomingConfirmedActivities.map((activity) => {
    return preserveActivityStatusProgress(previousByNextId.get(activity.id), activity);
  });

  const terminalizedLocalIds = new Set(getTerminalizedLocalActivityIds(
    previousActivities,
    incomingActivities,
    matchContext,
  ));
  const effectiveReplacedIds = Object.fromEntries(
    Object.entries(replacedIds).filter(([previousId]) => {
      return !terminalizedLocalIds.has(previousId);
    }),
  );

  return {
    confirmedActivities,
    pendingActivities,
    patch: {
      accountId,
      upsert: [...(pendingActivities ?? []), ...confirmedActivities],
      removeIds: unique([
        ...Object.entries(effectiveReplacedIds)
          .filter(([previousId, nextId]) => previousId !== nextId)
          .map(([previousId]) => previousId),
        ...terminalizedLocalIds,
      ]),
      replacedIds: effectiveReplacedIds,
    },
  };
}

function getTerminalizedLocalActivityIds(
  previousActivities: readonly ApiActivity[],
  incomingActivities: readonly ApiActivity[],
  matchContext: ReconciliationMatchContext,
) {
  const terminalTraceIds = new Set(matchContext.terminalTonTraceIds ?? []);
  const terminalHashes = new Set(
    (matchContext.terminalTonExternalMsgHashes ?? []).map(normalizeIdentifier).filter(Boolean),
  );

  for (const activity of incomingActivities) {
    const hasTerminalEvidence = activity.status === 'failed'
      || activity.status === 'expired'
      || (activity.kind === 'transaction' && activity.type === 'bounced');
    if (!hasTerminalEvidence) continue;

    terminalTraceIds.add(parseTxId(activity.id).hash);
    const externalMsgHashNorm = normalizeIdentifier(activity.externalMsgHashNorm);
    if (externalMsgHashNorm) terminalHashes.add(externalMsgHashNorm);
  }

  if (!terminalTraceIds.size && !terminalHashes.size) return [];

  return previousActivities.filter(isSubmittedLocalSwapIntent).filter((localSwap) => {
    const operationId = localSwap.extra?.reconciliation?.operationId;
    const intent = matchContext.previousIntents?.find((candidate) => candidate.operationId === operationId);
    const submittedHashes = [
      localSwap.externalMsgHashNorm,
      intent?.swap?.expectedExternalMsgHashNorm,
      ...(intent?.swap?.submittedHashes ?? []),
    ].map(normalizeIdentifier).filter(Boolean);

    return submittedHashes.some((hash) => terminalHashes.has(hash))
      || Boolean(intent?.swap?.expectedTraceId && terminalTraceIds.has(intent.swap.expectedTraceId));
  }).map(({ id }) => id);
}

function isSubmittedLocalSwapIntent(activity: ApiActivity): activity is ApiSwapActivity {
  return activity.kind === 'swap'
    && activity.extra?.reconciliation?.reason === 'local-intent'
    && Boolean(activity.externalMsgHashNorm)
    && activity.status !== 'failed'
    && activity.status !== 'expired';
}

function unique(values: readonly string[]) {
  return Array.from(new Set(values.filter(Boolean)));
}
