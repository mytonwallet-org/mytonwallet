import type { ApiActivity } from '../../../types';
import type {
  ActivityMatch,
  ActivityMatchKey,
  ActivityMatchKeyType,
  WalletOperationIntent,
} from './types';

import { getIsBackendSwapId, parseTxId } from '../../../../util/activities';

const MATCH_PRIORITY: Record<ActivityMatchKeyType, number> = {
  operationId: 1,
  backendSwapId: 2,
  cexTransactionId: 2,
  sourceId: 3,
  activityId: 3,
  txHash: 4,
  externalMsgHashNorm: 5,
  traceId: 6,
  submittedHash: 7,
};

const STATUS_RANK: Record<ApiActivity['status'], number> = {
  pending: 1,
  pendingTrusted: 2,
  confirmed: 3,
  completed: 4,
  failed: 4,
  expired: 4,
};
type MatchableActivity = ApiActivity & {
  extra?: ApiActivity['extra'] & {
    reconciliation?: { operationId?: string };
  };
};

type FindActivityMatchesOptions = {
  previousIntents?: readonly WalletOperationIntent[];
  nextIntents?: readonly WalletOperationIntent[];
};

function makeActivityMatchKey(
  type: ActivityMatchKeyType,
  value: string | undefined,
): ActivityMatchKey | undefined {
  const normalizedValue = normalizeIdentifier(value);
  if (!normalizedValue) return undefined;

  return {
    type,
    value: normalizedValue,
    priority: MATCH_PRIORITY[type],
  };
}

export function getActivityMatchKeys(
  activity: ApiActivity,
  intents: readonly WalletOperationIntent[] = [],
): ActivityMatchKey[] {
  const matchableActivity = activity as MatchableActivity;
  const isBackendSwapActivityId = getIsBackendSwapId(activity.id);
  const parsedActivityId = parseTxId(activity.id);
  const keys: (ActivityMatchKey | undefined)[] = [
    makeActivityMatchKey('operationId', matchableActivity.extra?.reconciliation?.operationId),
    makeActivityMatchKey('activityId', activity.id),
    makeActivityMatchKey('externalMsgHashNorm', activity.externalMsgHashNorm),
    makeActivityMatchKey('submittedHash', activity.externalMsgHashNorm),
  ];

  // A TON action id (`trace:sub-action`) identifies one action, while its parsed hash identifies the whole trace.
  // Trace membership is useful to project source actions, but it is not a safe one-to-one replacement key.
  // A local sub-id (`submitted-hash:0:local`) still carries the submitted transaction identity.
  if (!isBackendSwapActivityId && (!parsedActivityId.subId || parsedActivityId.type === 'local')) {
    keys.push(
      makeActivityMatchKey('txHash', parsedActivityId.hash),
      makeActivityMatchKey('submittedHash', parsedActivityId.hash),
    );
  }

  for (const sourceActionId of activity.extra?.reconciliation?.sourceActionIds ?? []) {
    keys.push(makeActivityMatchKey('sourceId', sourceActionId));
  }

  if (isBackendSwapActivityId) {
    keys.push(makeActivityMatchKey('backendSwapId', parseTxId(activity.id).hash));
  }

  if (activity.kind === 'swap') {
    keys.push(
      makeActivityMatchKey('cexTransactionId', activity.cex?.transactionId),
    );

    for (const hash of activity.hashes) {
      // Backend CEX hashes may contain either a chain transaction hash or TON externalMsgHashNorm.
      keys.push(
        makeActivityMatchKey('txHash', hash),
        makeActivityMatchKey('externalMsgHashNorm', hash),
        makeActivityMatchKey('submittedHash', hash),
      );
    }
  }

  keys.push(...getIntentSubmittedHashKeysForActivity(activity, intents));

  return uniqueMatchKeys(keys.filter(Boolean));
}

/**
 * Returns replacements from previous activity ids to next activity ids using SDK-owned deterministic priorities.
 * This is the pure matcher foundation; platform stores should ultimately consume SDK patches instead of duplicating it.
 */
export function getActivityIdReplacementsFromSdkMatcher(
  prevActivities: readonly ApiActivity[],
  nextActivities: readonly ApiActivity[],
  options: FindActivityMatchesOptions = {},
): Record<string, string> {
  const replacements: Record<string, string> = {};
  const usedNextIds = new Set<string>();
  const sortedPrev = [...prevActivities].sort(compareActivitiesById);
  const nextCandidates = [...nextActivities]
    .sort(compareActivitiesById)
    .map((activity) => ({ id: activity.id, keys: getActivityMatchKeys(activity, options.nextIntents), activity }));

  for (const prevActivity of sortedPrev) {
    const directMatch = nextCandidates.find(({ id }) => id === prevActivity.id);
    if (directMatch) {
      replacements[prevActivity.id] = directMatch.id;
      usedNextIds.add(directMatch.id);
      continue;
    }

    const match = findUniqueBestKeyMatch(
      prevActivity.id,
      getActivityMatchKeys(prevActivity, options.previousIntents),
      nextCandidates.filter(({ id, activity }) => {
        return !usedNextIds.has(id) && activity?.kind === prevActivity.kind;
      }),
    );

    if (match) {
      replacements[prevActivity.id] = match.matchedId;
      usedNextIds.add(match.matchedId);
    }
  }

  return replacements;
}

export function preserveActivityStatusProgress<T extends ApiActivity>(
  existing: ApiActivity | undefined,
  incoming: T,
): T {
  if (!existing) return incoming;
  if (existing.kind !== incoming.kind) return incoming;

  const mergedIncoming = mergeActivityReconciliationMetadata(existing, incoming);
  const existingRank = STATUS_RANK[existing.status];
  const incomingRank = STATUS_RANK[incoming.status];

  if (existingRank > incomingRank) {
    return { ...mergedIncoming, status: existing.status } as T;
  }

  return mergedIncoming;
}

function findUniqueBestKeyMatch(
  id: string,
  keys: readonly ActivityMatchKey[],
  candidates: readonly { id: string; keys: readonly ActivityMatchKey[]; activity?: ApiActivity }[],
): ActivityMatch | undefined {
  const sortedKeys = [...keys].sort(compareMatchKeys);

  for (const key of sortedKeys) {
    const matchedCandidates = candidates.filter((candidate) => {
      return candidate.keys.some((candidateKey) => areMatchKeysEqualAtPriority(key, candidateKey));
    });

    if (matchedCandidates.length === 1) {
      return {
        id,
        matchedId: matchedCandidates[0].id,
        key,
      };
    }

    const visibleMatchedCandidates = matchedCandidates.filter(({ activity }) => activity?.shouldHide !== true);
    if (visibleMatchedCandidates.length === 1) {
      return {
        id,
        matchedId: visibleMatchedCandidates[0].id,
        key,
      };
    }
  }

  return undefined;
}

function areMatchKeysEqualAtPriority(a: ActivityMatchKey, b: ActivityMatchKey) {
  return a.priority === b.priority && a.type === b.type && a.value === b.value;
}

function compareMatchKeys(a: ActivityMatchKey, b: ActivityMatchKey) {
  return a.priority - b.priority || a.type.localeCompare(b.type) || a.value.localeCompare(b.value);
}

function compareActivitiesById(a: ApiActivity, b: ApiActivity) {
  return a.id.localeCompare(b.id);
}

function mergeActivityReconciliationMetadata<T extends ApiActivity>(existing: ApiActivity, incoming: T): T {
  const existingReconciliation = existing.extra?.reconciliation;
  const incomingReconciliation = incoming.extra?.reconciliation;
  if (!existingReconciliation || !incomingReconciliation) return incoming;

  const operationId = incomingReconciliation.operationId ?? existingReconciliation.operationId;
  if (
    existingReconciliation.reason !== incomingReconciliation.reason
    || (existingReconciliation.operationId && operationId !== existingReconciliation.operationId)
    || (incomingReconciliation.operationId && operationId !== incomingReconciliation.operationId)
  ) {
    return incoming;
  }

  return {
    ...incoming,
    extra: {
      ...incoming.extra,
      reconciliation: {
        ...incomingReconciliation,
        operationId,
        sourceActionIds: uniqueStrings([
          ...existingReconciliation.sourceActionIds,
          ...incomingReconciliation.sourceActionIds,
        ]),
        hiddenSourceActionIds: uniqueStrings([
          ...existingReconciliation.hiddenSourceActionIds,
          ...incomingReconciliation.hiddenSourceActionIds,
        ]),
      },
    },
  };
}

function uniqueStrings(values: readonly string[]) {
  return Array.from(new Set(values));
}

function uniqueMatchKeys(keys: ActivityMatchKey[]) {
  const seen = new Set<string>();
  return keys.filter((key) => {
    const keyId = `${key.priority}:${key.type}:${key.value}`;
    if (seen.has(keyId)) return false;
    seen.add(keyId);
    return true;
  });
}

export function normalizeIdentifier(value: string | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;

  // EVM hex identifiers are case-insensitive. TON base64/base64url hashes are not, so do not lowercase blindly.
  if (/^0x[\da-f]+$/iu.test(trimmed) || /^[\da-f]{64}$/iu.test(trimmed)) {
    return trimmed.toLowerCase();
  }

  return trimmed;
}

function getIntentSubmittedHashKeysForActivity(
  activity: ApiActivity,
  intents: readonly WalletOperationIntent[],
): (ActivityMatchKey | undefined)[] {
  if (!intents.length) return [];

  const matchableActivity = activity as MatchableActivity;
  const operationId = matchableActivity.extra?.reconciliation?.operationId;
  const backendSwapId = getIsBackendSwapId(activity.id) ? parseTxId(activity.id).hash : undefined;
  const cexTransactionId = activity.kind === 'swap' ? activity.cex?.transactionId : undefined;
  const parsedActivityId = parseTxId(activity.id);
  const activityHashes = new Set([
    backendSwapId || parsedActivityId.subId ? undefined : parsedActivityId.hash,
    activity.externalMsgHashNorm,
    ...(activity.kind === 'swap' ? activity.hashes : []),
  ]
    .map((hash) => normalizeIdentifier(hash))
    .filter((hash): hash is string => Boolean(hash)));

  const keys: (ActivityMatchKey | undefined)[] = [];
  for (const intent of intents) {
    const isRelated = Boolean(
      (operationId && intent.operationId === operationId)
      || (backendSwapId && intent.swap?.backendSwapId === backendSwapId)
      || (cexTransactionId && intent.swap?.cexTransactionId === cexTransactionId)
      || (intent.swap?.submittedHashes ?? []).some((hash) => {
        const normalizedHash = normalizeIdentifier(hash);
        return normalizedHash ? activityHashes.has(normalizedHash) : false;
      }),
    );

    if (!isRelated) continue;

    keys.push(
      makeActivityMatchKey('operationId', intent.operationId),
      makeActivityMatchKey('backendSwapId', intent.swap?.backendSwapId),
      makeActivityMatchKey('cexTransactionId', intent.swap?.cexTransactionId),
      makeActivityMatchKey('externalMsgHashNorm', intent.swap?.expectedExternalMsgHashNorm),
      makeActivityMatchKey('traceId', intent.swap?.expectedTraceId),
      ...(intent.swap?.submittedHashes ?? []).map((hash) => makeActivityMatchKey('submittedHash', hash)),
    );
  }

  return keys;
}
