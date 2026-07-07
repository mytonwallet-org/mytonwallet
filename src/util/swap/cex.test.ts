import type { ApiSwapHistoryItem } from '../../api/types';

import {
  getCexExternalExchangeId,
  isChangellyCexLabel,
} from './cex';

type ApiSwapCex = NonNullable<ApiSwapHistoryItem['cex']>;

describe('CEX helpers', () => {
  it('keeps legacy/no-label CEX swaps as Changelly', () => {
    expect(isChangellyCexLabel(undefined)).toBe(true);
    expect(isChangellyCexLabel('changelly')).toBe(true);
  });

  it('uses transactionId as the external exchange ID', () => {
    const cex = { transactionId: 'external-exchange-id' } as ApiSwapCex;

    expect(getCexExternalExchangeId(cex)).toBe('external-exchange-id');
  });
});
