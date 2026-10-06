import type { ApiSwapHistoryItem } from '../../api/types';

import { CHANGELLY_TRACKING_URL, NEAR_INTENTS_EXPLORER_URL } from '../../config';
import {
  getCexExternalExchangeId,
  getCexTrackingUrl,
  isChangellyCexLabel,
} from './cex';

type ApiSwapCex = NonNullable<ApiSwapHistoryItem['cex']>;

const CEX: ApiSwapCex = {
  payinAddress: '0xDeposit',
  payoutAddress: '0xPayout',
  status: 'finished',
  transactionId: 'swap/id',
};

describe('CEX helpers', () => {
  it('keeps legacy/no-label CEX swaps as Changelly', () => {
    expect(isChangellyCexLabel(undefined)).toBe(true);
    expect(isChangellyCexLabel('changelly')).toBe(true);
  });

  it('uses transactionId as the external exchange ID', () => {
    const cex = { transactionId: 'external-exchange-id' } as ApiSwapCex;

    expect(getCexExternalExchangeId(cex)).toBe('external-exchange-id');
  });

  it('links a Changelly swap by its ID', () => {
    expect(getCexTrackingUrl('changelly', CEX)).toBe(`${CHANGELLY_TRACKING_URL}swap%2Fid`);
    expect(getCexTrackingUrl(undefined, CEX)).toBe(`${CHANGELLY_TRACKING_URL}swap%2Fid`);
  });

  it('links a Near Intents swap by its deposit address', () => {
    expect(getCexTrackingUrl('near-intents', CEX)).toBe(`${NEAR_INTENTS_EXPLORER_URL}0xDeposit`);
  });

  it('does not link a Near Intents swap with a deposit memo', () => {
    expect(getCexTrackingUrl('near-intents', { ...CEX, payinExtraId: '123' })).toBeUndefined();
  });
});
