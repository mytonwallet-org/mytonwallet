import type { ApiActivity, ApiSwapActivity, ApiTransactionActivity } from '../../../types';

import { DIESEL_ADDRESS, MW_AGGREGATOR_QUERY_ID, SWAP_FEE_ADDRESS } from '../../../../config';
import { Big } from '../../../../lib/big.js';
import { getIsBackendSwapId, parseTxId } from '../../../../util/activities';
import { sortActivities } from '../../../../util/activities/order';
import { areDeepEqual } from '../../../../util/areDeepEqual';
import { toDecimal } from '../../../../util/decimals';
import { unique } from '../../../../util/iteratees';
import { logDebugError } from '../../../../util/logs';
import { getChainBySlug } from '../../../../util/tokens';
import { toBase64Address } from '../../../chains/ton/util/tonCore';
import { storage } from '../../../storages';
import { getTokenBySlug } from '../../tokens';
import { preserveActivityStatusProgress } from './matcher';
import { mutateReconcilerStorageItem } from './storageMutationQueue';

const KNOWN_TON_AGGREGATOR_TRACES_STORAGE_KEY = 'knownTonAggregatorTraceIds';
const KNOWN_TON_AGGREGATOR_PROJECTIONS_STORAGE_KEY = 'knownTonAggregatorTraceProjections';
const MAX_KNOWN_TRACES_PER_ACCOUNT = 500;

export type KnownTonAggregatorTraceProjection = {
  traceId: string;
  aggregatedActivity?: ApiSwapActivity;
  sourceActionIds: string[];
  hiddenSourceActionIds: string[];
  updatedAt: number;
  isTerminalFailure?: boolean;
};

export type TonAggregatorProjectionResult = {
  activities: ApiActivity[];
  knownAggregatorTraceIds: string[];
  newlyKnownAggregatorTraceIds: string[];
  knownAggregatorTraceProjections: KnownTonAggregatorTraceProjection[];
  newlyKnownAggregatorTraceProjections: KnownTonAggregatorTraceProjection[];
  deaggregatedTraceIds: string[];
  deaggregatedExternalMsgHashes: string[];
};

/** Conservative marker detection for TON aggregator traces. */
export function hasTonAggregatorMarker(activities: readonly ApiActivity[]) {
  return activities.some((activity) => {
    return activity.extra?.queryId === MW_AGGREGATOR_QUERY_ID
      || activity.extra?.isOurSwapFee
      || Boolean(activity.extra?.mtwAggregator);
  });
}

/** Every non-failed lifecycle state is eligible once a complete aggregator trace has been identified. */
export function areAllTraceActivitiesEligibleForAggregation(activities: readonly ApiActivity[]) {
  return activities.length > 0 && activities.every(isActivityEligibleForAggregation);
}

export async function getKnownTonAggregatorTraceIds(accountId: string): Promise<string[]> {
  const byAccount = await storage.getItem(KNOWN_TON_AGGREGATOR_TRACES_STORAGE_KEY);
  return byAccount?.[accountId] ?? [];
}

export async function rememberKnownTonAggregatorTraceIds(accountId: string, traceIds: readonly string[]) {
  if (!traceIds.length) return;

  await mutateReconcilerStorageItem<Record<string, string[]>>(KNOWN_TON_AGGREGATOR_TRACES_STORAGE_KEY, (
    byAccount: Record<string, string[]> | undefined,
  ) => {
    const nextByAccount = { ...byAccount };
    nextByAccount[accountId] = unique([
      ...traceIds,
      ...(nextByAccount[accountId] ?? []),
    ]).slice(0, MAX_KNOWN_TRACES_PER_ACCOUNT);
    return nextByAccount;
  });
}

export async function getKnownTonAggregatorTraceProjections(
  accountId: string,
): Promise<KnownTonAggregatorTraceProjection[]> {
  const byAccount = await storage.getItem(KNOWN_TON_AGGREGATOR_PROJECTIONS_STORAGE_KEY);
  return byAccount?.[accountId] ?? [];
}

export async function rememberKnownTonAggregatorTraceProjections(
  accountId: string,
  projections: readonly KnownTonAggregatorTraceProjection[],
) {
  if (!projections.length) return;

  await mutateReconcilerStorageItem<Record<string, KnownTonAggregatorTraceProjection[]>>(
    KNOWN_TON_AGGREGATOR_PROJECTIONS_STORAGE_KEY,
    (byAccount) => {
      const nextByAccount = { ...byAccount };
      nextByAccount[accountId] = uniqueTraceProjections([
        ...projections,
        ...(nextByAccount[accountId] ?? []),
      ]).slice(0, MAX_KNOWN_TRACES_PER_ACCOUNT);
      return nextByAccount;
    },
  );
}

export async function reconcileTonAggregatorActivitiesForAccount(
  accountId: string,
  activities: readonly ApiActivity[],
  options: {
    incompleteTraceIds?: readonly string[];
    isLiveUpdate?: boolean;
  } = {},
) {
  const [knownTraceIds, knownTraceProjections] = await Promise.all([
    getKnownTonAggregatorTraceIds(accountId),
    getKnownTonAggregatorTraceProjections(accountId),
  ]);
  const result = projectTonAggregatorActivities(
    activities,
    [...knownTraceProjections, ...knownTraceIds],
    options,
  );

  await Promise.all([
    rememberKnownTonAggregatorTraceIds(accountId, result.newlyKnownAggregatorTraceIds),
    rememberKnownTonAggregatorTraceProjections(accountId, result.newlyKnownAggregatorTraceProjections),
  ]);

  return result;
}

export function projectTonAggregatorActivities(
  activities: readonly ApiActivity[],
  knownAggregatorTraces: readonly (string | KnownTonAggregatorTraceProjection)[] = [],
  options: {
    incompleteTraceIds?: readonly string[];
    isLiveUpdate?: boolean;
  } = {},
): TonAggregatorProjectionResult {
  const knownAggregatorTraceProjections = normalizeKnownAggregatorTraceProjections(knownAggregatorTraces);
  const knownProjectionByTraceId = new Map(knownAggregatorTraceProjections.map((projection) => [
    projection.traceId,
    projection,
  ]));

  if (!activities.length) {
    return {
      activities: [],
      knownAggregatorTraceIds: [...knownProjectionByTraceId.keys()],
      newlyKnownAggregatorTraceIds: [],
      knownAggregatorTraceProjections,
      newlyKnownAggregatorTraceProjections: [],
      deaggregatedTraceIds: [],
      deaggregatedExternalMsgHashes: [],
    };
  }

  const knownTraceSet = new Set(knownProjectionByTraceId.keys());
  const incompleteTraceIds = new Set(options.incompleteTraceIds ?? []);
  const traceMap = new Map<string, {
    swaps: { activity: ApiSwapActivity; index: number }[];
    activities: { activity: ApiActivity; index: number }[];
    hasAggregatorMarker: boolean;
  }>();

  activities.forEach((activity, index) => {
    const traceId = getActivityTraceId(activity);
    const group = traceMap.get(traceId) ?? { swaps: [], activities: [], hasAggregatorMarker: false };
    group.activities.push({ activity, index });

    if (isTonSwapLeg(activity)) {
      group.swaps.push({ activity, index });
    }

    if (hasTonAggregatorMarker([activity])) {
      group.hasAggregatorMarker = true;
    }

    traceMap.set(traceId, group);
  });

  const replacements = new Map<number, ApiActivity>();
  const skippedIndices = new Set<number>();
  const additionalActivities: ApiActivity[] = [];
  const newlyKnownAggregatorTraceIds: string[] = [];
  const newlyKnownAggregatorTraceProjections: KnownTonAggregatorTraceProjection[] = [];
  const deaggregatedTraceIds: string[] = [];
  const deaggregatedExternalMsgHashes: string[] = [];

  traceMap.forEach((originalGroup, traceId) => {
    if (incompleteTraceIds.has(traceId)) return;

    const isKnownAggregatorTrace = knownTraceSet.has(traceId);
    const knownProjection = knownProjectionByTraceId.get(traceId);
    let group = originalGroup;

    if (knownProjection?.sourceActionIds.length) {
      const knownSourceIds = new Set(knownProjection.sourceActionIds);
      const unknownActivities = group.activities.filter(({ activity }) => !knownSourceIds.has(activity.id));

      if (unknownActivities.length) {
        if (options.isLiveUpdate) {
          logDebugError('TON aggregator trace action-set invariant violation', {
            traceId,
            knownSourceActionIds: knownProjection.sourceActionIds,
            unexpectedSourceActionIds: unknownActivities.map(({ activity }) => activity.id),
          });
        }
        unknownActivities.forEach(({ index }) => skippedIndices.add(index));

        const activities = group.activities.filter(({ activity }) => knownSourceIds.has(activity.id));
        const swaps = group.swaps.filter(({ activity }) => knownSourceIds.has(activity.id));
        group = {
          activities,
          swaps,
          hasAggregatorMarker: group.hasAggregatorMarker,
        };

        if (!activities.length) {
          if (knownProjection.aggregatedActivity && !knownProjection.isTerminalFailure) {
            if (options.isLiveUpdate) additionalActivities.push(knownProjection.aggregatedActivity);
          }
          return;
        }
      }
    }

    const traceActivities = group.activities.map(({ activity }) => activity);
    const deaggregateTrace = () => {
      const sourceActionIds = knownProjection?.sourceActionIds.length
        ? knownProjection.sourceActionIds
        : getStableSourceActionIds(traceActivities);
      const terminalProjection: KnownTonAggregatorTraceProjection = {
        traceId,
        sourceActionIds,
        hiddenSourceActionIds: [],
        updatedAt: Date.now(),
        isTerminalFailure: true,
      };

      if (!isKnownAggregatorTrace) {
        newlyKnownAggregatorTraceIds.push(traceId);
        knownTraceSet.add(traceId);
      }
      const shouldRememberProjection = !areKnownTraceProjectionsEqual(knownProjection, terminalProjection);
      knownProjectionByTraceId.set(traceId, terminalProjection);
      if (shouldRememberProjection) {
        newlyKnownAggregatorTraceProjections.push(terminalProjection);
      }

      group.activities.forEach(({ activity, index }) => {
        replacements.set(index, removeTonAggregateSourceProjection(activity));
      });
      deaggregatedTraceIds.push(traceId);
      deaggregatedExternalMsgHashes.push(...traceActivities.flatMap(({ externalMsgHashNorm }) => {
        return externalMsgHashNorm ? [externalMsgHashNorm] : [];
      }));
    };
    const hasCompleteKnownActionSet = !knownProjection?.sourceActionIds.length
      || knownProjection.sourceActionIds.every((id) => traceActivities.some((activity) => activity.id === id));
    const shouldDeaggregateForFailure = (
      isKnownAggregatorTrace || group.hasAggregatorMarker
    ) && (
      knownProjection?.isTerminalFailure
      || (
        hasExplicitTraceFailure(traceActivities)
        && (options.isLiveUpdate || hasCompleteKnownActionSet)
      )
    );

    if (shouldDeaggregateForFailure) {
      deaggregateTrace();
      return;
    }

    const projectionMode = getKnownProjectionMode(
      traceActivities,
      knownProjection,
    );
    const aggregated = projectionMode === 'reuse'
      ? buildTonAggregatedSwapFromKnownProjection(group, knownProjection)
      : projectionMode === 'reject'
        ? undefined
        : buildTonAggregatedSwap(traceId, group, knownProjection)
          ?? buildTonAggregatedSwapFromKnownProjection(group, knownProjection);
    if (!aggregated) {
      if (
        projectionMode === 'reject'
        || !shouldTreatIrreducibleTraceAsFailure(group, isKnownAggregatorTrace)
      ) {
        return;
      }

      deaggregateTrace();
      return;
    }

    if (!isKnownAggregatorTrace) {
      newlyKnownAggregatorTraceIds.push(traceId);
      knownTraceSet.add(traceId);
    }

    if (aggregated.knownProjection) {
      const previousProjection = knownProjectionByTraceId.get(traceId);
      const shouldRememberProjection = !areKnownTraceProjectionsEqual(previousProjection, aggregated.knownProjection);
      knownProjectionByTraceId.set(traceId, aggregated.knownProjection);
      if (shouldRememberProjection) {
        newlyKnownAggregatorTraceProjections.push(aggregated.knownProjection);
      }
    }

    const hiddenActivities = (aggregated as {
      hiddenActivities?: { activity: ApiActivity; index: number }[];
      additionalActivities?: ApiActivity[];
    }).hiddenActivities;
    if (hiddenActivities) {
      hiddenActivities.forEach(({ activity, index }) => {
        replacements.set(index, activity);
      });
      additionalActivities.push(...(
        (aggregated as { additionalActivities?: ApiActivity[] }).additionalActivities ?? []
      ));
      return;
    }

    const { aggregatedActivity, primaryIndex, hiddenSourceActivities } = aggregated as {
      aggregatedActivity: ApiSwapActivity;
      primaryIndex: number;
      hiddenSourceActivities: { activity: ApiActivity; index: number }[];
    };
    replacements.set(primaryIndex, aggregatedActivity);
    hiddenSourceActivities.forEach(({ activity, index }) => {
      if (index !== primaryIndex) replacements.set(index, activity);
    });
  });

  if (!replacements.size && !skippedIndices.size && !additionalActivities.length) {
    return {
      activities: [...activities],
      knownAggregatorTraceIds: [...knownTraceSet],
      newlyKnownAggregatorTraceIds,
      knownAggregatorTraceProjections: [...knownProjectionByTraceId.values()],
      newlyKnownAggregatorTraceProjections,
      deaggregatedTraceIds: unique(deaggregatedTraceIds),
      deaggregatedExternalMsgHashes: unique(deaggregatedExternalMsgHashes),
    };
  }

  const projectedActivities: ApiActivity[] = [];
  activities.forEach((activity, index) => {
    if (skippedIndices.has(index)) return;
    projectedActivities.push(replacements.get(index) ?? activity);
  });
  projectedActivities.push(...additionalActivities);

  return {
    activities: sortActivities(projectedActivities),
    knownAggregatorTraceIds: [...knownTraceSet],
    newlyKnownAggregatorTraceIds,
    knownAggregatorTraceProjections: [...knownProjectionByTraceId.values()],
    newlyKnownAggregatorTraceProjections,
    deaggregatedTraceIds: unique(deaggregatedTraceIds),
    deaggregatedExternalMsgHashes: unique(deaggregatedExternalMsgHashes),
  };
}

function getKnownProjectionMode(
  activities: readonly ApiActivity[],
  knownProjection: KnownTonAggregatorTraceProjection | undefined,
): 'rebuild' | 'reuse' | 'reject' {
  if (!knownProjection?.aggregatedActivity || !knownProjection.sourceActionIds.length) return 'rebuild';

  const knownIds = new Set(knownProjection.sourceActionIds);
  const currentIds = new Set(activities.map(({ id }) => id));
  const containsOnlyKnownIds = [...currentIds].every((id) => knownIds.has(id));
  const containsAllKnownIds = [...knownIds].every((id) => currentIds.has(id));

  if (containsOnlyKnownIds && currentIds.size < knownIds.size) return 'reuse';
  if (containsAllKnownIds) return 'rebuild';

  // A mixed slice with unknown actions cannot prove that it is a complete newer trace projection.
  return 'reject';
}

function buildTonAggregatedSwap(
  traceId: string,
  group: {
    swaps: { activity: ApiSwapActivity; index: number }[];
    activities: { activity: ApiActivity; index: number }[];
    hasAggregatorMarker: boolean;
  },
  knownProjection: KnownTonAggregatorTraceProjection | undefined,
) {
  const { swaps, hasAggregatorMarker } = group;
  const incomingAggregate = swaps.find(({ activity }) => isTonAggregatedSwap(activity))?.activity;

  if (incomingAggregate) {
    return buildTonProjectionFromIncomingAggregate(traceId, group, incomingAggregate, knownProjection);
  }

  // Known trace ids allow token-specific slices to aggregate even when they miss the marker, but the slice still needs
  // enough swap legs to prove a clean route. When in doubt, leave raw actions visible.
  if (!knownProjection && !hasAggregatorMarker) return undefined;
  const traceActivities = group.activities.map(({ activity }) => activity);
  if (!isFullTraceSafeForAggregation(traceActivities)) return undefined;
  const swapActivities = swaps.map(({ activity }) => activity);
  const representedActivities = group.activities.map(({ activity, index }) => ({ activity, index }));
  const aggregatedAmounts = resolveCleanRouteAmounts(swapActivities);
  if (!aggregatedAmounts) return undefined;
  const includedFeeAmount = getIncludedFeeTransferAmount(traceActivities, aggregatedAmounts.from);
  if (swaps.length < 2 && !includedFeeAmount) return undefined;
  const displayAmounts = {
    ...aggregatedAmounts,
    fromAmount: Big(aggregatedAmounts.fromAmount).add(includedFeeAmount ?? 0).toString(),
  };

  const swapIds = getStableActionIds(
    swapActivities.map(({ id }) => id),
    knownProjection?.aggregatedActivity?.extra?.mtwAggregator?.swapIds,
  );
  const preferredPrimaryId = knownProjection?.aggregatedActivity?.id;
  const primaryEntry = swaps.find(({ activity }) => activity.id === preferredPrimaryId)
    ?? [...swaps].sort(({ activity: first }, { activity: second }) => first.id.localeCompare(second.id))[0];
  const primaryIndex = primaryEntry.index;
  const primarySwap = primaryEntry.activity;
  const sourceActionIds = getStableActionIds(
    representedActivities.map(({ activity }) => activity.id),
    knownProjection?.sourceActionIds,
  );
  const hiddenSourceActionIds = unique(
    sourceActionIds.filter((id) => id !== primarySwap.id),
  );

  let timestamp = 0;
  let networkFee = Big(0);
  let swapFee = Big(0);
  let ourFee = Big(0);

  swapActivities.forEach((activity) => {
    timestamp = Math.max(timestamp, activity.timestamp);
    networkFee = networkFee.add(activity.networkFee);
    swapFee = swapFee.add(activity.swapFee);
    ourFee = ourFee.add(activity.ourFee || '0');
  });

  const aggregateStatus = getAggregateStatus(representedActivities.map(({ activity }) => activity));

  const incomingAggregatedActivity: ApiSwapActivity = {
    ...primarySwap,
    ...displayAmounts,
    status: aggregateStatus,
    shouldHide: undefined,
    timestamp,
    networkFee: networkFee.toString(),
    swapFee: swapFee.toString(),
    ourFee: ourFee.toString(),
    hashes: unique(swapActivities.flatMap(({ hashes }) => hashes)),
    extra: {
      ...primarySwap.extra,
      mtwAggregator: {
        traceId,
        swapIds,
        from: displayAmounts.from,
        to: displayAmounts.to,
      },
      reconciliation: {
        operationId: knownProjection?.aggregatedActivity?.extra?.reconciliation?.operationId
          ?? primarySwap.extra?.reconciliation?.operationId,
        sourceActionIds,
        hiddenSourceActionIds,
        reason: 'ton-aggregated-swap',
      },
    },
  };
  const aggregatedActivity = preserveActivityStatusProgress(
    knownProjection?.aggregatedActivity,
    incomingAggregatedActivity,
  );

  const nextKnownProjection: KnownTonAggregatorTraceProjection = {
    traceId,
    aggregatedActivity,
    sourceActionIds,
    hiddenSourceActionIds,
    updatedAt: Date.now(),
  };

  return {
    aggregatedActivity,
    primaryIndex,
    hiddenSourceActivities: representedActivities
      .filter(({ index }) => index !== primaryIndex)
      .map(({ activity, index }) => ({
        index,
        activity: hideKnownProjectionSourceActivity(activity, nextKnownProjection),
      })),
    knownProjection: nextKnownProjection,
  };
}

function buildTonProjectionFromIncomingAggregate(
  traceId: string,
  group: {
    swaps: { activity: ApiSwapActivity; index: number }[];
    activities: { activity: ApiActivity; index: number }[];
  },
  incomingAggregate: ApiSwapActivity,
  knownProjection: KnownTonAggregatorTraceProjection | undefined,
) {
  const incomingReconciliation = incomingAggregate.extra?.reconciliation;
  const sourceActionIds = getStableActionIds(
    incomingReconciliation?.sourceActionIds.length
      ? incomingReconciliation.sourceActionIds
      : group.activities.map(({ activity }) => activity.id),
    knownProjection?.sourceActionIds,
  );
  const hiddenSourceActionIds = sourceActionIds.filter((id) => id !== incomingAggregate.id);
  const aggregatedActivity = preserveActivityStatusProgress(
    knownProjection?.aggregatedActivity,
    {
      ...incomingAggregate,
      shouldHide: undefined,
      extra: {
        ...incomingAggregate.extra,
        reconciliation: {
          operationId: incomingReconciliation?.operationId
            ?? knownProjection?.aggregatedActivity?.extra?.reconciliation?.operationId,
          sourceActionIds,
          hiddenSourceActionIds,
          reason: 'ton-aggregated-swap',
        },
      },
    },
  );
  const nextKnownProjection: KnownTonAggregatorTraceProjection = {
    traceId,
    aggregatedActivity,
    sourceActionIds,
    hiddenSourceActionIds,
    updatedAt: Date.now(),
  };
  const primaryEntry = group.activities.find(({ activity }) => activity.id === aggregatedActivity.id);
  if (!primaryEntry) return undefined;

  return {
    aggregatedActivity,
    primaryIndex: primaryEntry.index,
    hiddenSourceActivities: group.activities
      .filter(({ activity }) => activity.id !== aggregatedActivity.id && sourceActionIds.includes(activity.id))
      .map(({ activity, index }) => ({
        index,
        activity: hideKnownProjectionSourceActivity(activity, nextKnownProjection),
      })),
    knownProjection: nextKnownProjection,
  };
}

function buildTonAggregatedSwapFromKnownProjection(
  group: {
    swaps: { activity: ApiSwapActivity; index: number }[];
    activities: { activity: ApiActivity; index: number }[];
  },
  knownProjection: KnownTonAggregatorTraceProjection | undefined,
) {
  const aggregatedActivity = knownProjection?.aggregatedActivity;
  if (!aggregatedActivity) return undefined;

  const knownSourceActionIds = new Set(knownProjection.sourceActionIds);
  const knownHiddenSourceActionIds = new Set(knownProjection.hiddenSourceActionIds);

  const hasOnlyKnownHiddenSourceActivities = group.activities.length > 0 && group.activities.every(({ activity }) => {
    return knownHiddenSourceActionIds.has(activity.id);
  });
  if (hasOnlyKnownHiddenSourceActivities) {
    return {
      hiddenActivities: group.activities.map(({ activity, index }) => ({
        index,
        activity: hideKnownProjectionSourceActivity(activity, knownProjection),
      })),
      // A history slice may contain only a non-primary swap leg after a cold start. Emit the durable canonical
      // aggregate as well as the explicit hidden source patch so the result is self-contained for every client.
      additionalActivities: group.swaps.length
        ? [aggregatedActivity]
        : [],
      knownProjection: undefined,
    };
  }

  if (group.activities.some(({ activity }) => !knownSourceActionIds.has(activity.id))) return undefined;

  const knownActivitiesInSlice = group.activities.filter(({ activity }) => knownSourceActionIds.has(activity.id));
  const primaryEntry = knownActivitiesInSlice.find(({ activity }) => {
    return activity.id === aggregatedActivity.id;
  });
  if (!primaryEntry) return undefined;

  const primaryIndex = primaryEntry.index;
  return {
    aggregatedActivity,
    primaryIndex,
    hiddenSourceActivities: knownActivitiesInSlice
      .filter(({ index }) => index !== primaryIndex)
      .map(({ activity, index }) => ({
        index,
        activity: hideKnownProjectionSourceActivity(activity, knownProjection),
      })),
    knownProjection: undefined,
  };
}

function resolveCleanRouteAmounts(swaps: readonly ApiSwapActivity[]) {
  const totals = new Map<string, Big>();

  swaps.forEach((activity) => {
    totals.set(activity.from, (totals.get(activity.from) || Big(0)).minus(activity.fromAmount));
    totals.set(activity.to, (totals.get(activity.to) || Big(0)).add(activity.toAmount));
  });

  const negativeEntries: [string, Big][] = [];
  const positiveEntries: [string, Big][] = [];

  totals.forEach((value, slug) => {
    if (value.lt(0)) negativeEntries.push([slug, value]);
    if (value.gt(0)) positiveEntries.push([slug, value]);
  });

  // Exactly one source and one final output means intermediates netted to zero. Extra positive/negative balances are
  // partial failure or an irreducible route, so the UI should show honest raw actions.
  if (negativeEntries.length !== 1 || positiveEntries.length !== 1) return undefined;

  const [from, fromDelta] = negativeEntries[0];
  const [to, toDelta] = positiveEntries[0];
  if (from === to) return undefined;

  return {
    from,
    to,
    fromAmount: fromDelta.times(-1).toString(),
    toAmount: toDelta.toString(),
  };
}

function getIncludedFeeTransferAmount(activities: readonly ApiActivity[], slug: string) {
  const token = getTokenBySlug(slug);
  if (!token) return undefined;

  const feeTransfers = activities.filter((activity): activity is ApiTransactionActivity => {
    if (
      activity.kind !== 'transaction'
      || activity.isIncoming
      || activity.amount >= 0n
      || activity.slug !== slug
      || !activity.extra?.isOurSwapFee
    ) {
      return false;
    }

    try {
      return [SWAP_FEE_ADDRESS, DIESEL_ADDRESS].includes(toBase64Address(activity.toAddress, false));
    } catch {
      return false;
    }
  });
  if (feeTransfers.length !== 1) return undefined;

  return toDecimal(-feeTransfers[0].amount, token.decimals);
}

function isTonSwapLeg(activity: ApiActivity): activity is ApiSwapActivity {
  return !getIsBackendSwapId(activity.id)
    && activity.kind === 'swap'
    && getChainBySlug(activity.from) === 'ton'
    && getChainBySlug(activity.to) === 'ton';
}

function isFullTraceSafeForAggregation(activities: readonly ApiActivity[]) {
  return activities.every((activity) => {
    return isActivityEligibleForAggregation(activity);
  });
}

function isActivityEligibleForAggregation(activity: ApiActivity) {
  return activity.status !== 'failed'
    && activity.status !== 'expired'
    && (activity.kind !== 'transaction' || activity.type !== 'bounced');
}

function getAggregateStatus(activities: readonly ApiActivity[]): ApiActivity['status'] {
  if (activities.some(({ status }) => status === 'pending')) return 'pending';
  if (activities.some(({ status }) => status === 'pendingTrusted')) return 'pendingTrusted';
  if (activities.some(({ status }) => status === 'confirmed')) return 'confirmed';
  return 'completed';
}

function hasExplicitTraceFailure(activities: readonly ApiActivity[]) {
  return activities.some((activity) => {
    return activity.status === 'failed'
      || activity.status === 'expired'
      || (activity.kind === 'transaction' && activity.type === 'bounced');
  });
}

function shouldTreatIrreducibleTraceAsFailure(
  group: {
    swaps: { activity: ApiSwapActivity }[];
    activities: { activity: ApiActivity }[];
    hasAggregatorMarker: boolean;
  },
  isKnownAggregatorTrace: boolean,
) {
  if (!isKnownAggregatorTrace && !group.hasAggregatorMarker) return false;
  if (group.swaps.length < 2) return false;
  return areAllTraceActivitiesEligibleForAggregation(group.activities.map(({ activity }) => activity))
    && !resolveCleanRouteAmounts(group.swaps.map(({ activity }) => activity));
}

function getStableSourceActionIds(activities: readonly ApiActivity[]) {
  return getStableActionIds(activities.map(({ id }) => id));
}

function getStableActionIds(ids: readonly string[], preferredIds: readonly string[] = []) {
  const uniqueIds = unique(ids);
  const currentIdSet = new Set(uniqueIds);
  const preferredIdSet = new Set(preferredIds);
  if (
    preferredIds.length === uniqueIds.length
    && preferredIds.every((id) => currentIdSet.has(id))
    && uniqueIds.every((id) => preferredIdSet.has(id))
  ) {
    return [...preferredIds];
  }

  return uniqueIds.sort((first, second) => first.localeCompare(second));
}

function hideKnownProjectionSourceActivity(
  activity: ApiActivity,
  knownProjection: KnownTonAggregatorTraceProjection,
): ApiActivity {
  return {
    ...activity,
    shouldHide: true,
    extra: {
      ...activity.extra,
      reconciliation: {
        operationId: activity.extra?.reconciliation?.operationId,
        sourceActionIds: knownProjection.sourceActionIds,
        hiddenSourceActionIds: knownProjection.hiddenSourceActionIds,
        reason: 'ton-aggregated-swap',
      },
    },
  };
}

function removeTonAggregateSourceProjection(activity: ApiActivity): ApiActivity {
  const remainingExtra = { ...activity.extra };
  delete remainingExtra.mtwAggregator;
  if (
    remainingExtra.reconciliation?.reason === 'ton-aggregated-swap'
    || remainingExtra.reconciliation?.reason === 'ton-partial-failure-deaggregated'
  ) {
    delete remainingExtra.reconciliation;
  }

  return {
    ...activity,
    shouldHide: undefined,
    extra: Object.keys(remainingExtra).length ? remainingExtra : undefined,
  };
}

function isTonAggregatedSwap(activity: ApiSwapActivity) {
  return activity.extra?.reconciliation?.reason === 'ton-aggregated-swap'
    && Boolean(activity.extra.mtwAggregator);
}

function getActivityTraceId(activity: ApiActivity) {
  return activity.extra?.mtwAggregator?.traceId ?? parseTxId(activity.id).hash;
}

function normalizeKnownAggregatorTraceProjections(
  knownAggregatorTraces: readonly (string | KnownTonAggregatorTraceProjection)[],
) {
  return uniqueTraceProjections(knownAggregatorTraces.map((knownTrace): KnownTonAggregatorTraceProjection => {
    return typeof knownTrace === 'string'
      ? {
        traceId: knownTrace,
        sourceActionIds: [],
        hiddenSourceActionIds: [],
        updatedAt: 0,
      }
      : knownTrace;
  }));
}

function uniqueTraceProjections(projections: readonly KnownTonAggregatorTraceProjection[]) {
  const seenTraceIds = new Set<string>();
  return projections.filter((projection) => {
    if (seenTraceIds.has(projection.traceId)) return false;
    seenTraceIds.add(projection.traceId);
    return true;
  });
}

function areKnownTraceProjectionsEqual(
  first: KnownTonAggregatorTraceProjection | undefined,
  second: KnownTonAggregatorTraceProjection,
) {
  if (!first) return false;
  if (Boolean(first.isTerminalFailure) !== Boolean(second.isTerminalFailure)) return false;
  if (!areStringArraysEqual(first.sourceActionIds, second.sourceActionIds)) return false;
  if (!areStringArraysEqual(first.hiddenSourceActionIds, second.hiddenSourceActionIds)) return false;

  const firstActivity = first.aggregatedActivity;
  const secondActivity = second.aggregatedActivity;
  if (!firstActivity || !secondActivity) return firstActivity === secondActivity;

  return areDeepEqual(firstActivity, secondActivity);
}

function areStringArraysEqual(first: readonly string[], second: readonly string[]) {
  return first.length === second.length && first.every((value, index) => value === second[index]);
}
