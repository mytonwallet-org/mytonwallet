import type { ApiActivity, ApiActivityReconciliationReason, ApiSwapActivity } from '../../types';

import { Big } from '../../../lib/big.js';
import { getIsBackendSwapId, getIsTxIdLocal, parseTxId } from '../../../util/activities';
import { sortActivities } from '../../../util/activities/order';

/**
 * One swap the wallet knows about is represented up to three times: the local row created at submit
 * (`<backendId>::local`), the backend history row (`<backendId>::backend-swap`) and the actions of the blockchain
 * trace. The swap row is canonical; a chain activity belongs to it when they share an explicit hash (the normalized
 * external message hash or a trace/transaction hash). Nothing else (amounts, addresses, timing) is ever compared.
 */

export type SwapProjectionWindow = {
  fromTime: number;
  toTime: number;
};

const STATUS_RANK: Record<ApiActivity['status'], number> = {
  pending: 1,
  pendingTrusted: 2,
  confirmed: 3,
  completed: 4,
  failed: 4,
  expired: 4,
};

export function preserveActivityStatusProgress<T extends ApiActivity>(
  existing: ApiActivity | undefined,
  incoming: T,
): T {
  if (!existing || existing.kind !== incoming.kind) return incoming;
  if (STATUS_RANK[existing.status] <= STATUS_RANK[incoming.status]) return incoming;
  return { ...incoming, status: existing.status };
}

/** EVM hex identifiers are case-insensitive; TON base64 hashes are not, so only hex is lowercased. */
export function normalizeIdentifier(value: string | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;
  return /^(0x)?[\da-f]{40,}$/iu.test(trimmed) ? trimmed.toLowerCase() : trimmed;
}

/**
 * A swap row stands for a whole exchange made through the built-in swap: the backend history row, or the local row
 * `swapSubmit` creates for it. A local swap predicted for a dapp transaction is a chain action like any other.
 */
export function isSwapRow(activity: ApiActivity): activity is ApiSwapActivity {
  if (activity.kind !== 'swap') return false;
  if (getIsBackendSwapId(activity.id)) return true;
  return getIsTxIdLocal(activity.id) && activity.extra?.reconciliation?.reason === 'local-intent';
}

export function getSwapRowBackendId(swap: ApiSwapActivity) {
  return parseTxId(swap.id).hash;
}

export function getSwapRowKeys(swap: ApiSwapActivity) {
  return unique([...swap.hashes, swap.msgHash, swap.externalMsgHashNorm].map(normalizeIdentifier));
}

function getChainActivityKeys(activity: ApiActivity) {
  const { hash } = parseTxId(activity.id);
  return unique([activity.externalMsgHashNorm, isSwapRow(activity) ? undefined : hash].map(normalizeIdentifier));
}

/**
 * Projects a slice of chain activities against the swap rows that may represent them. Matched chain activities are
 * hidden under their swap row; a swap row is emitted when its timestamp falls inside `window` or when a chain
 * activity of the slice belongs to it. The result is sorted.
 */
export function projectSwapActivities(
  activities: readonly ApiActivity[],
  swapRows: readonly ApiSwapActivity[],
  window: SwapProjectionWindow,
): ApiActivity[] {
  const swapRowById = new Map(swapRows.map((swap) => [swap.id, swap]));
  const swapIdsByKey = new Map<string, Set<string>>();
  for (const swap of swapRows) {
    for (const key of getSwapRowKeys(swap)) {
      swapIdsByKey.set(key, new Set([...(swapIdsByKey.get(key) ?? []), swap.id]));
    }
  }

  const matchedBySwapId = new Map<string, ApiActivity[]>();
  const chainActivities: ApiActivity[] = [];
  for (const activity of activities) {
    if (swapRowById.has(activity.id)) continue;
    chainActivities.push(activity);

    const swapIds = new Set(getChainActivityKeys(activity).flatMap((key) => [...(swapIdsByKey.get(key) ?? [])]));
    // A chain activity claimed by several swap rows stays visible until the backend makes ownership unambiguous
    if (swapIds.size !== 1) continue;
    const [swapId] = swapIds;
    matchedBySwapId.set(swapId, [...(matchedBySwapId.get(swapId) ?? []), activity]);
  }

  const projectedSwaps: ApiSwapActivity[] = [];
  const hiddenById = new Map<string, ApiActivity>();
  for (const swap of swapRows) {
    const sources = matchedBySwapId.get(swap.id) ?? [];
    const isInWindow = swap.timestamp >= window.fromTime && swap.timestamp <= window.toTime;
    if (!sources.length && !isInWindow) continue;

    // A DEX route that failed in part is not summarized: the summary leaves the feed and the actions stay raw
    if (!swap.cex && sources.some(hasFailed)) {
      projectedSwaps.push(buildFailedRouteSummary(swap, sources));
      continue;
    }

    const projectedSwap = buildProjectedSwap(swap, sources);
    projectedSwaps.push(projectedSwap);
    for (const source of sources) {
      hiddenById.set(source.id, {
        ...source,
        shouldHide: true,
        extra: { ...source.extra, reconciliation: projectedSwap.extra!.reconciliation },
      });
    }
  }

  return sortActivities([
    ...projectedSwaps,
    ...chainActivities.map((activity) => hiddenById.get(activity.id) ?? clearSwapProjection(activity)),
  ]);
}

export type ActivityUpdateReconciliation = {
  confirmedActivities: ApiActivity[];
  pendingActivities?: ApiActivity[];
  upsert: ApiActivity[];
  removeIds: string[];
  replacedIds: Record<string, string>;
};

/**
 * Live-update projection. `previous` holds the platform's local and pending rows, `context` the rest of what it
 * shows; `confirmed` and `pending` are the incoming rows (already enriched with backend swap rows where the source
 * fetches them). Swap rows from all of them are candidates, and a visible row the platform already holds becomes a
 * hidden source when an incoming swap row claims it. A row hidden under a swap this update does not know is never
 * touched. Returns the rows to add and the authoritative patch: every incoming row after projection, the swap rows
 * that gained sources, the held rows that got hidden, the previous ids that are replaced by an incoming row, and the
 * ids to remove.
 */
export function reconcileActivityUpdate(
  previous: readonly ApiActivity[],
  confirmed: readonly ApiActivity[],
  pending?: readonly ApiActivity[],
  context: readonly ApiActivity[] = [],
): ActivityUpdateReconciliation {
  const incoming = uniqueById([...(pending ?? []), ...confirmed]);
  const incomingIds = new Set(incoming.map(({ id }) => id));
  const held = uniqueById([...previous, ...context]).filter(({ id }) => !incomingIds.has(id));
  const swapRows = uniqueSwapRows([...incoming.filter(isSwapRow), ...held.filter(isSwapRow)]);
  const incomingChainRows = incoming.filter((activity) => !isSwapRow(activity));
  const heldVisibleChainRows = held.filter((activity) => !isSwapRow(activity) && activity.shouldHide !== true);
  const chainRows = [...incomingChainRows, ...heldVisibleChainRows];

  // Replacements are one to one: an incoming row stands in for at most one previous row
  const replacedIds: Record<string, string> = {};
  const usedNextIds = new Set<string>();
  for (const previousActivity of previous) {
    const replacement = findReplacement(previousActivity, swapRows, incomingChainRows);
    if (!replacement || usedNextIds.has(replacement)) continue;
    replacedIds[previousActivity.id] = replacement;
    usedNextIds.add(replacement);
  }
  const retiredLocalIds = getSupersededLocalTransactionIds(previous, incomingChainRows, replacedIds);

  const previousById = new Map(previous.map((activity) => [activity.id, activity]));
  const previousIdByNextId = new Map(Object.entries(replacedIds).map(([previousId, nextId]) => [nextId, previousId]));
  const projected = projectSwapActivities(chainRows, swapRows, { fromTime: 0, toTime: Infinity })
    .map((activity) => preserveActivityStatusProgress(
      previousById.get(previousIdByNextId.get(activity.id) ?? activity.id),
      activity,
    ));
  const projectedById = new Map(projected.map((activity) => [activity.id, activity]));
  const project = (activity: ApiActivity) => projectedById.get(activity.id) ?? activity;

  return {
    confirmedActivities: confirmed.map(project),
    pendingActivities: pending?.map(project),
    upsert: projected.filter((activity) => {
      if (incomingIds.has(activity.id)) return true;
      return isSwapRow(activity)
        ? Boolean(activity.extra?.reconciliation?.hiddenSourceActionIds.length) || activity.shouldHide === true
        : activity.shouldHide === true;
    }),
    removeIds: unique([...Object.keys(replacedIds), ...retiredLocalIds]),
    replacedIds,
  };
}

/**
 * A local transaction row is this client's prediction of one action of a trace it submitted, and several of them
 * share the trace's external message hash, so no chain action pairs with them one to one. A finalized trace speaks
 * for the whole message: every prediction still standing under its hash is retired. Local swap rows stay: the backend
 * row replaces them.
 */
function getSupersededLocalTransactionIds(
  previous: readonly ApiActivity[],
  incomingChainRows: readonly ApiActivity[],
  replacedIds: Record<string, string>,
) {
  const finalizedHashes = new Set(unique(incomingChainRows
    .filter(({ status }) => status === 'completed' || status === 'failed')
    .map(({ externalMsgHashNorm }) => normalizeIdentifier(externalMsgHashNorm))));

  return previous.filter((activity) => {
    const hash = normalizeIdentifier(activity.externalMsgHashNorm);
    return activity.kind === 'transaction'
      && getIsTxIdLocal(activity.id)
      && !replacedIds[activity.id]
      && Boolean(hash)
      && finalizedHashes.has(hash);
  }).map(({ id }) => id);
}

function findReplacement(
  previousActivity: ApiActivity,
  swapRows: readonly ApiSwapActivity[],
  chainRows: readonly ApiActivity[],
) {
  if (isSwapRow(previousActivity)) {
    if (!getIsTxIdLocal(previousActivity.id)) return undefined;
    const backendId = getSwapRowBackendId(previousActivity);
    const backendRow = swapRows.find((swap) => getIsBackendSwapId(swap.id) && getSwapRowBackendId(swap) === backendId);
    return backendRow?.id;
  }

  const keys = getChainActivityKeys(previousActivity);
  const matches = chainRows.filter((activity) => {
    return activity.kind === previousActivity.kind
      && activity.id !== previousActivity.id
      && getChainActivityKeys(activity).some((key) => keys.includes(key));
  });
  return matches.length === 1 ? matches[0].id : undefined;
}

/**
 * One row per backend swap id: the backend row wins over the local one, an earlier entry over a later one. The
 * identity of the swap is the union of what every row of it knows: the local row learns the submitted hash before
 * the backend echoes it, and a backend row fetched in that gap must not lose it.
 */
export function uniqueSwapRows(swapRows: readonly ApiSwapActivity[]) {
  const byBackendId = new Map<string, ApiSwapActivity>();
  for (const swap of swapRows) {
    const backendId = getSwapRowBackendId(swap);
    const existing = byBackendId.get(backendId);
    if (!existing) {
      byBackendId.set(backendId, swap);
      continue;
    }
    const isBackendOverLocal = getIsTxIdLocal(existing.id) && getIsBackendSwapId(swap.id);
    const [winner, other] = isBackendOverLocal ? [swap, existing] : [existing, swap];
    byBackendId.set(backendId, {
      ...winner,
      hashes: unique([...winner.hashes, ...other.hashes]),
      msgHash: winner.msgHash ?? other.msgHash,
      externalMsgHashNorm: winner.externalMsgHashNorm ?? other.externalMsgHashNorm,
    });
  }
  return [...byBackendId.values()];
}

function uniqueById(activities: readonly ApiActivity[]) {
  const byId = new Map<string, ApiActivity>();
  for (const activity of activities) byId.set(activity.id, activity);
  return [...byId.values()];
}

function buildProjectedSwap(swap: ApiSwapActivity, sources: readonly ApiActivity[]): ApiSwapActivity {
  const backendId = getSwapRowBackendId(swap);
  const hiddenSourceActionIds = sources.map(({ id }) => id);
  const legs = sources.filter((source): source is ApiSwapActivity => source.kind === 'swap');
  const status = swap.cex ? swap.status : getDexStatus(swap, sources, legs);
  const toAmount = status === 'completed' ? getSettledToAmount(swap, legs) ?? swap.toAmount : swap.toAmount;
  const reason: ApiActivityReconciliationReason = swap.cex
    ? 'cex-swap'
    : getIsTxIdLocal(swap.id) ? 'local-intent' : 'ton-aggregated-swap';

  // The trace hash lets the details loader read the trace of a DEX summary
  const externalMsgHashNorm = swap.cex
    ? swap.externalMsgHashNorm
    : sources.find((source) => source.externalMsgHashNorm)?.externalMsgHashNorm ?? swap.externalMsgHashNorm;

  return {
    ...swap,
    status,
    toAmount,
    shouldHide: undefined,
    ...(externalMsgHashNorm && { externalMsgHashNorm }),
    extra: {
      ...swap.extra,
      ...(legs.length && !swap.cex && {
        mtwAggregator: {
          traceId: parseTxId(legs[0].id).hash,
          swapIds: legs.map(({ id }) => id),
          from: swap.from,
          to: swap.to,
        },
      }),
      reconciliation: {
        operationId: `swap:${backendId}`,
        sourceActionIds: [swap.id, ...hiddenSourceActionIds],
        hiddenSourceActionIds,
        reason,
      },
    },
  };
}

function getDexStatus(
  swap: ApiSwapActivity,
  sources: readonly ApiActivity[],
  legs: readonly ApiSwapActivity[],
): ApiActivity['status'] {
  if (!sources.length) return swap.status;
  if (sources.some(({ status }) => status === 'pending' || status === 'pendingTrusted')) return 'pendingTrusted';
  if (sources.some(({ status }) => status === 'confirmed')) return 'confirmed';
  if (legs.some(({ status }) => status === 'completed')) return 'completed';
  return swap.status;
}

function hasFailed(activity: ApiActivity) {
  return activity.status === 'failed'
    || activity.status === 'expired'
    || (activity.kind === 'transaction' && activity.type === 'bounced');
}

function buildFailedRouteSummary(swap: ApiSwapActivity, sources: readonly ApiActivity[]): ApiSwapActivity {
  return {
    ...swap,
    status: 'failed',
    shouldHide: true,
    extra: {
      ...swap.extra,
      reconciliation: {
        operationId: `swap:${getSwapRowBackendId(swap)}`,
        sourceActionIds: [swap.id, ...sources.map(({ id }) => id)],
        hiddenSourceActionIds: [],
        reason: 'ton-partial-failure-deaggregated',
      },
    },
  };
}

/** The amount the wallet actually received: the target token netted over the swap legs of the trace. */
function getSettledToAmount(swap: ApiSwapActivity, legs: readonly ApiSwapActivity[]) {
  let total = Big(0);
  for (const leg of legs) {
    if (leg.to === swap.to) total = total.add(leg.toAmount);
    if (leg.from === swap.to) total = total.minus(leg.fromAmount);
  }
  return total.gt(0) ? total.toString() : undefined;
}

function clearSwapProjection(activity: ApiActivity): ApiActivity {
  const reason = activity.extra?.reconciliation?.reason;
  if (reason !== 'cex-swap' && reason !== 'ton-aggregated-swap' && reason !== 'local-intent') return activity;

  const { reconciliation, mtwAggregator, ...extra } = activity.extra!;
  return {
    ...activity,
    shouldHide: activity.extra?.isOurSwapFee ? true : undefined,
    extra: Object.keys(extra).length ? extra : undefined,
  };
}

function unique(values: readonly (string | undefined)[]) {
  return Array.from(new Set(values.filter((value): value is string => Boolean(value))));
}
