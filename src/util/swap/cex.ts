import type { ApiSwapCexLabel, ApiSwapHistoryItem } from '../../api/types';

import { CHANGELLY_TRACKING_URL, NEAR_INTENTS_EXPLORER_URL } from '../../config';

type ApiSwapCex = NonNullable<ApiSwapHistoryItem['cex']>;

export function isChangellyCexLabel(cexLabel?: ApiSwapCexLabel | null) {
  return !cexLabel || cexLabel === 'changelly';
}

export function getCexExternalExchangeId(cex?: ApiSwapCex) {
  return cex?.transactionId;
}

export function getCexTrackingUrl(cexLabel: ApiSwapCexLabel | undefined, cex: ApiSwapCex) {
  if (isChangellyCexLabel(cexLabel)) {
    return `${CHANGELLY_TRACKING_URL}${encodeURIComponent(cex.transactionId)}`;
  }

  // The explorer finds a swap by its deposit address, not by the swap ID.
  // Its URL format for a deposit with a memo is not documented, so such a swap gets no link.
  if (cexLabel === 'near-intents' && !cex.payinExtraId) {
    return `${NEAR_INTENTS_EXPLORER_URL}${encodeURIComponent(cex.payinAddress)}`;
  }

  return undefined;
}
