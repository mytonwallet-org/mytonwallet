import type { ApiSwapActivity } from '../../api/types';

import { TONCOIN } from '../../config';
import { getSwapTransactionIdRows } from './transactionIds';

function makeSwapActivity(activity: Partial<ApiSwapActivity>): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'fallback-hash:backend-swap',
    timestamp: 0,
    from: TONCOIN.slug,
    fromAmount: '1',
    to: TONCOIN.slug,
    toAmount: '1',
    networkFee: '0',
    status: 'completed',
    hashes: [],
    transactionIds: {},
    ...activity,
  } as ApiSwapActivity;
}

describe('getSwapTransactionIdRows', () => {
  it('renders outgoing and incoming rows when both hashes differ', () => {
    expect(getSwapTransactionIdRows(makeSwapActivity({
      transactionIds: {
        outgoing: { hash: 'outgoing-hash', chain: 'ton' },
        incoming: { hash: 'incoming-hash', chain: 'solana' },
      },
    }))).toEqual([
      { label: 'Outgoing Transaction ID', hash: 'outgoing-hash', chain: 'ton' },
      { label: 'Incoming Transaction ID', hash: 'incoming-hash', chain: 'solana' },
    ]);
  });

  it('renders a single transaction row when only one structured hash exists', () => {
    expect(getSwapTransactionIdRows(makeSwapActivity({
      transactionIds: {
        outgoing: { hash: 'outgoing-hash', chain: 'ton' },
      },
    }))).toEqual([
      { label: 'Transaction ID', hash: 'outgoing-hash', chain: 'ton' },
    ]);
  });

  it('renders a single transaction row when structured hashes are equal', () => {
    expect(getSwapTransactionIdRows(makeSwapActivity({
      transactionIds: {
        outgoing: { hash: 'same-hash', chain: 'ton' },
        incoming: { hash: 'same-hash', chain: 'ton' },
      },
    }))).toEqual([
      { label: 'Transaction ID', hash: 'same-hash', chain: 'ton' },
    ]);
  });

  it('falls back to the legacy CEX hash', () => {
    expect(getSwapTransactionIdRows(makeSwapActivity({
      cex: {} as ApiSwapActivity['cex'],
      hashes: ['legacy-hash'],
    }))).toEqual([
      { label: 'Transaction ID', hash: 'legacy-hash', chain: 'ton' },
    ]);
  });
});
