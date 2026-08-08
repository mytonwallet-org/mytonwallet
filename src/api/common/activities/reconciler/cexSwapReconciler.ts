import type { ApiActivity, ApiSwapActivity } from '../../../types';
import type { ReconciledActivitiesPatch, WalletOperationIntent } from './types';

import { getIsBackendSwapId, parseTxId } from '../../../../util/activities';
import { getActivityMatchKeys, preserveActivityStatusProgress } from './matcher';

/** Returns true for SDK-projected CEX/cross-chain swap activities. */
export function isCexSwapActivity(activity: ApiActivity): activity is ApiSwapActivity {
  return activity.kind === 'swap' && Boolean(activity.cex);
}

/**
 * Collect canonical identifiers that a CEX swap may absorb. Backend `hashes` can contain a chain tx hash/signature or a
 * TON externalMsgHashNorm, so callers must compare both forms rather than only `parseTxId(activity.id).hash`.
 */
export function getCexSwapAbsorbableIdentifiers(
  swap: ApiSwapActivity,
  intents: readonly WalletOperationIntent[] = [],
): string[] {
  return unique([
    ...getActivityMatchKeys(swap, intents)
      .filter(({ type }) => type === 'txHash' || type === 'externalMsgHashNorm' || type === 'submittedHash')
      .map(({ value }) => value),
  ]);
}

export function getActivityCexComparableIdentifiers(
  activity: ApiActivity,
  intents: readonly WalletOperationIntent[] = [],
): string[] {
  return unique([
    ...getActivityMatchKeys(activity, intents)
      .filter(({ type }) => {
        return type === 'txHash'
          || type === 'externalMsgHashNorm'
          || type === 'activityId'
          || type === 'submittedHash';
      })
      .map(({ value }) => value),
    // Unlike one-to-one replacement, CEX projection intentionally absorbs every raw action represented by a backend
    // transaction/trace hash. Keep this broader group identifier confined to the projector.
    getIsBackendSwapId(activity.id) ? '' : parseTxId(activity.id).hash,
  ]);
}

/**
 * Returns backend CEX swap ids that are represented by at least one source transaction in the current projection slice.
 * Callers use this to force-emit the canonical swap when a raw payin/payout transaction is present but the backend swap
 * timestamp itself falls just outside the requested activity page.
 */
export function getCexSwapIdsRepresentedBySourceActivities(
  activities: readonly ApiActivity[],
  cexSwaps: readonly ApiSwapActivity[],
  intents: readonly WalletOperationIntent[] = [],
  allowSwapSources = false,
) {
  const swapIdsByIdentifier = buildSwapIdsByIdentifier(cexSwaps, intents);
  const representedSwapIds = new Set<string>();

  for (const activity of activities) {
    if (activity.kind !== 'transaction' && (!allowSwapSources || activity.kind !== 'swap')) continue;

    const matchedSwapId = findUniqueMatchedCexSwapId(activity, swapIdsByIdentifier, intents);
    if (matchedSwapId) representedSwapIds.add(matchedSwapId);
  }

  return representedSwapIds;
}

export function projectCexSwapActivities(
  sourceActivities: readonly ApiActivity[],
  cexSwapActivities: readonly ApiSwapActivity[],
  visibleCexSwapIds: ReadonlySet<string> = new Set(cexSwapActivities.map(({ id }) => id)),
  intents: readonly WalletOperationIntent[] = [],
  allowSwapSources = false,
) {
  const swapIdsByIdentifier = buildSwapIdsByIdentifier(cexSwapActivities, intents);
  const swapsById = new Map(cexSwapActivities.map((swap) => [swap.id, swap]));
  const hiddenSourceIdsBySwapId = new Map<string, string[]>();

  const projectedSourceActivities = sourceActivities.map((activity) => {
    const matchedSwapId = (activity.kind === 'transaction' || (allowSwapSources && activity.kind === 'swap'))
      ? findUniqueMatchedCexSwapId(activity, swapIdsByIdentifier, intents)
      : undefined;

    if (!matchedSwapId || !visibleCexSwapIds.has(matchedSwapId)) {
      return removeCexSourceProjection(activity);
    }

    const matchedSwap = swapsById.get(matchedSwapId);
    if (!matchedSwap || matchedSwap.shouldHide === true) {
      return removeCexSourceProjection(activity);
    }

    hiddenSourceIdsBySwapId.set(matchedSwapId, [
      ...(hiddenSourceIdsBySwapId.get(matchedSwapId) ?? []),
      activity.id,
    ]);

    // Preserve independent SDK visibility decisions (for example staking/NFT filtering). Only CEX-owned source
    // projections may be replaced or later removed by this reconciler.
    if (activity.shouldHide === true && activity.extra?.reconciliation?.reason !== 'cex-swap') {
      return activity;
    }

    return withCexReconciliationMetadata(
      { ...activity, shouldHide: true },
      getCexOperationId(matchedSwap, intents),
      [activity.id],
      [activity.id],
    );
  });

  const projectedSwapActivities = cexSwapActivities
    .filter(({ id }) => visibleCexSwapIds.has(id))
    .map((swap) => {
      const hiddenSourceActionIds = hiddenSourceIdsBySwapId.get(swap.id) ?? [];
      return withCexReconciliationMetadata(
        swap,
        getCexOperationId(swap, intents),
        [swap.id, ...hiddenSourceActionIds],
        hiddenSourceActionIds,
      );
    });

  return { projectedSourceActivities, projectedSwapActivities };
}

export function buildCexSwapRefreshPatch(
  accountId: string,
  fetchedSwaps: readonly ApiSwapActivity[],
  nonExistentIds: readonly string[],
  existingActivities: readonly ApiActivity[],
  intents: readonly WalletOperationIntent[] = [],
): ReconciledActivitiesPatch {
  const existingById = new Map(existingActivities.map((activity) => [activity.id, activity]));
  const refreshedSwaps: ApiSwapActivity[] = [];
  for (const swap of fetchedSwaps) {
    if (!isCexSwapActivity(swap)) continue;
    refreshedSwaps.push(normalizeCexSwapRefreshActivity(swap));
  }

  for (const id of nonExistentIds) {
    const existing = existingById.get(id)
      ?? existingActivities.find((activity) => {
        return isCexSwapActivity(activity) && parseTxId(activity.id).hash === id;
      });

    if (!existing || !isCexSwapActivity(existing)) continue;

    const expiredSwap = withCexReconciliationMetadata(
      {
        ...existing,
        status: 'expired',
        shouldHide: undefined,
      },
      getCexOperationId(existing, intents),
      existing.extra?.reconciliation?.sourceActionIds ?? [existing.id],
      existing.extra?.reconciliation?.hiddenSourceActionIds ?? [],
    );
    refreshedSwaps.push(expiredSwap);
  }

  const cexContextById = new Map<string, ApiSwapActivity>();
  for (const activity of existingActivities) {
    if (isCexSwapActivity(activity)) cexContextById.set(activity.id, activity);
  }
  for (const swap of refreshedSwaps) {
    cexContextById.set(swap.id, swap);
  }

  const { projectedSourceActivities, projectedSwapActivities } = projectCexSwapRefreshActivities({
    existingActivities,
    contextSwaps: [...cexContextById.values()],
    refreshedSwaps,
    intents,
  });

  return {
    accountId,
    upsert: [...projectedSwapActivities, ...projectedSourceActivities],
    removeIds: [],
    replacedIds: {},
  };
}

export function normalizeCexSwapRefreshActivity(swap: ApiSwapActivity): ApiSwapActivity {
  return {
    ...swap,
    status: swap.isCanceled ? 'expired' : swap.status,
    shouldHide: undefined,
  };
}

export function projectCexSwapRefreshActivities({
  existingActivities,
  contextSwaps,
  refreshedSwaps,
  intents = [],
}: {
  existingActivities: readonly ApiActivity[];
  contextSwaps: readonly ApiSwapActivity[];
  refreshedSwaps: readonly ApiSwapActivity[];
  intents?: readonly WalletOperationIntent[];
}) {
  const existingById = new Map(existingActivities.map((activity) => [activity.id, activity]));
  const contextSwapsById = new Map(contextSwaps.map((swap) => [swap.id, swap]));
  for (const swap of refreshedSwaps) contextSwapsById.set(swap.id, swap);

  const allContextSwaps = [...contextSwapsById.values()];
  const swapIdsByIdentifier = buildSwapIdsByIdentifier(allContextSwaps, intents);
  const operationIdBySwapId = new Map(allContextSwaps.map((swap) => [
    swap.id,
    getCexOperationId(swap, intents),
  ]));
  const refreshedOperationIds = new Set(
    refreshedSwaps.map((swap) => getCexOperationId(swap, intents)).filter(Boolean),
  );
  const refreshedSwapIdByOperationId = new Map(
    refreshedSwaps.map((swap) => [getCexOperationId(swap, intents), swap.id]),
  );
  const hiddenSourceIdsBySwapId = new Map<string, string[]>();
  const projectedSourceActivities: ApiActivity[] = [];

  for (const activity of existingActivities) {
    if (activity.kind !== 'transaction') continue;

    const ownerOperationId = getCexSourceOwnerOperationId(activity);
    if (ownerOperationId) {
      if (!refreshedOperationIds.has(ownerOperationId)) continue;

      const ownerSwapId = refreshedSwapIdByOperationId.get(ownerOperationId);
      if (ownerSwapId) {
        appendHiddenSourceId(hiddenSourceIdsBySwapId, ownerSwapId, activity.id);
      }

      if (activity.shouldHide !== true) {
        projectedSourceActivities.push({ ...activity, shouldHide: true });
      }
      continue;
    }

    if (!canAssignNewCexSourceOwnership(activity)) continue;
    const matchedSwapId = findUniqueMatchedCexSwapId(activity, swapIdsByIdentifier, intents);
    if (!matchedSwapId) continue;

    const operationId = operationIdBySwapId.get(matchedSwapId);
    const refreshedSwapId = operationId ? refreshedSwapIdByOperationId.get(operationId) : undefined;
    if (!operationId || !refreshedSwapId) continue;

    appendHiddenSourceId(hiddenSourceIdsBySwapId, refreshedSwapId, activity.id);
    projectedSourceActivities.push(withCexReconciliationMetadata(
      { ...activity, shouldHide: true },
      operationId,
      [activity.id],
      [activity.id],
    ));
  }

  const projectedSwapActivities = refreshedSwaps.map((swap) => {
    const existing = existingById.get(swap.id);
    const existingReconciliation = existing?.extra?.reconciliation?.reason === 'cex-swap'
      ? existing.extra.reconciliation
      : undefined;
    const operationId = getCexOperationId(swap, intents);
    const ownedSourceIds = existingActivities
      .filter((activity) => {
        return activity.kind === 'transaction' && getCexSourceOwnerOperationId(activity) === operationId;
      })
      .map(({ id }) => id);
    const hiddenSourceActionIds = unique([
      ...(existingReconciliation?.hiddenSourceActionIds ?? []),
      ...ownedSourceIds,
      ...(hiddenSourceIdsBySwapId.get(swap.id) ?? []),
    ]);
    const projectedSwap = withCexReconciliationMetadata(
      normalizeCexSwapRefreshActivity(swap),
      operationId,
      unique([
        swap.id,
        ...(existingReconciliation?.sourceActionIds ?? []),
        ...hiddenSourceActionIds,
      ]),
      hiddenSourceActionIds,
    );
    return preserveActivityStatusProgress(existing, projectedSwap);
  });

  return { projectedSourceActivities, projectedSwapActivities };
}

function getCexSourceOwnerOperationId(activity: ApiActivity) {
  const reconciliation = activity.extra?.reconciliation;
  return reconciliation?.reason === 'cex-swap' ? reconciliation.operationId : undefined;
}

function canAssignNewCexSourceOwnership(activity: ApiActivity) {
  if (activity.shouldHide === true) return false;
  if (activity.status === 'failed' || activity.status === 'expired') return false;
  if (activity.kind === 'transaction' && activity.type === 'bounced') return false;

  const reason = activity.extra?.reconciliation?.reason;
  return !reason || reason === 'raw';
}

function appendHiddenSourceId(
  hiddenSourceIdsBySwapId: Map<string, string[]>,
  swapId: string,
  sourceId: string,
) {
  hiddenSourceIdsBySwapId.set(swapId, unique([
    ...(hiddenSourceIdsBySwapId.get(swapId) ?? []),
    sourceId,
  ]));
}

function buildSwapIdsByIdentifier(
  cexSwapActivities: readonly ApiSwapActivity[],
  intents: readonly WalletOperationIntent[] = [],
) {
  const swapIdsByIdentifier = new Map<string, Set<string>>();

  for (const swap of cexSwapActivities) {
    for (const identifier of getCexSwapAbsorbableIdentifiers(swap, intents)) {
      let swapIds = swapIdsByIdentifier.get(identifier);
      if (!swapIds) {
        swapIds = new Set();
        swapIdsByIdentifier.set(identifier, swapIds);
      }
      swapIds.add(swap.id);
    }
  }

  return swapIdsByIdentifier;
}

function findUniqueMatchedCexSwapId(
  activity: ApiActivity,
  swapIdsByIdentifier: Map<string, Set<string>>,
  intents: readonly WalletOperationIntent[] = [],
) {
  const matchedSwapIds = new Set<string>();

  for (const identifier of getActivityCexComparableIdentifiers(activity, intents)) {
    const swapIds = swapIdsByIdentifier.get(identifier);
    if (!swapIds) continue;

    for (const swapId of swapIds) {
      matchedSwapIds.add(swapId);
    }
  }

  // CEX absorption must be conservative. If two backend swaps claim the same raw transaction identifier, keep the raw
  // action visible until backend/intent data makes ownership unambiguous.
  return matchedSwapIds.size === 1 ? [...matchedSwapIds][0] : undefined;
}

function withCexReconciliationMetadata<T extends ApiActivity>(
  activity: T,
  operationId: string | undefined,
  sourceActionIds: string[],
  hiddenSourceActionIds: string[],
): T {
  return {
    ...activity,
    extra: {
      ...activity.extra,
      reconciliation: {
        operationId,
        sourceActionIds,
        hiddenSourceActionIds,
        reason: 'cex-swap',
      },
    },
  };
}

function removeCexSourceProjection<T extends ApiActivity>(activity: T): T {
  if (activity.extra?.reconciliation?.reason !== 'cex-swap') return activity;

  const remainingExtra = { ...activity.extra };
  delete remainingExtra.reconciliation;
  return {
    ...activity,
    shouldHide: undefined,
    extra: Object.keys(remainingExtra).length ? remainingExtra : undefined,
  } as T;
}

function getCexOperationId(swap: ApiSwapActivity, intents: readonly WalletOperationIntent[] = []) {
  const swapHash = parseTxId(swap.id).hash;
  const operationId = swap.extra?.reconciliation?.operationId;
  const cexTransactionId = swap.cex?.transactionId;
  // Two swaps that both lack an identifier are not the same swap. Comparing an absent field to an absent one would
  // claim every intent owns every DEX swap, since only a cross-chain swap has a provider transaction at all.
  const intent = intents.find((intent) => {
    return (operationId !== undefined && intent.operationId === operationId)
      || (Boolean(swapHash) && intent.swap?.backendSwapId === swapHash)
      || (cexTransactionId !== undefined && intent.swap?.cexTransactionId === cexTransactionId);
  });

  if (intent) return intent.operationId;
  return `swap:${swapHash}`;
}

function unique(values: readonly string[]) {
  return Array.from(new Set(values.filter(Boolean)));
}
