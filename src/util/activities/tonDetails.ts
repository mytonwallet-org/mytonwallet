import type { ApiSwapActivity } from '../../api/types';

import { getChainBySlug } from '../tokens';
import { getIsBackendSwapId, getIsTxIdLocal, parseTxId } from './index';

const DETAILS_RECONCILIATION_REASONS = new Set(['local-intent', 'ton-aggregated-swap']);

/**
 * Returns a TON trace id/msg hash suitable for TransactionInfo when a visible swap row represents multiple
 * underlying TON blockchain actions. The function intentionally fails closed unless the trace identity is explicit or
 * unambiguous; reducers/reconcilers must not infer a details trace from amount ordering or other presentation hints.
 */
export function getTonAggregatedSwapDetailsTraceId(activity: ApiSwapActivity) {
  if (!isTonSwap(activity)) return undefined;

  const aggregator = activity.extra?.mtwAggregator;
  if (aggregator) return aggregator.swapIds.length > 1 ? aggregator.traceId : undefined;

  const reconciliation = activity.extra?.reconciliation;
  if (!reconciliation?.hiddenSourceActionIds.length) return undefined;
  if (!DETAILS_RECONCILIATION_REASONS.has(reconciliation.reason)) return undefined;

  const representedTraceIds = unique([
    activity.id,
    ...reconciliation.sourceActionIds,
  ].flatMap((id) => {
    if (getIsTxIdLocal(id) || getIsBackendSwapId(id)) return [];

    const { hash, subId } = parseTxId(id);
    return subId ? [hash] : [];
  }));

  if (representedTraceIds.length === 1) return representedTraceIds[0];

  // During the socket transition a local representative may temporarily know only the submitted TON message hash while
  // raw actions from more than one trace id are being folded into it. `fetchTraceByIdOrHash` accepts this hash too.
  return activity.externalMsgHashNorm;
}

function isTonSwap(activity: ApiSwapActivity) {
  try {
    return getChainBySlug(activity.from) === 'ton' && getChainBySlug(activity.to) === 'ton';
  } catch {
    return false;
  }
}

function unique<T>(values: readonly T[]) {
  return Array.from(new Set(values.filter(Boolean)));
}
