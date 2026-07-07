import type { ApiSwapCexLabel, ApiSwapHistoryItem } from '../../api/types';

type ApiSwapCex = NonNullable<ApiSwapHistoryItem['cex']>;

export function isChangellyCexLabel(cexLabel?: ApiSwapCexLabel | null) {
  return !cexLabel || cexLabel === 'changelly';
}

export function getCexExternalExchangeId(cex?: ApiSwapCex) {
  return cex?.transactionId;
}
