import type { ApiTransactionActivity } from '../../types';

import { TRX } from '../../../config';
import { makeMockSwapActivity, makeMockTransactionActivity } from '../../../../tests/mocks';
import { mergeActivities } from './activities';

describe('mergeActivities', () => {
  it('merges and sorts activities', () => {
    const txsBySlug = {
      [TRX.slug]: [
        makeMockTransactionActivity({ id: 'a', timestamp: 2 }),
        makeMockTransactionActivity({ id: 'b', timestamp: 1 }),
      ],
      'mock-token': [
        makeMockTransactionActivity({ id: 'c', timestamp: 3 }),
      ],
    };
    const result = mergeActivities(txsBySlug);
    expect(result.map((a) => a.id)).toEqual(['c', 'a', 'b']);
  });

  it('takes token transaction fee from corresponding TRX transaction', () => {
    const txsBySlug = {
      [TRX.slug]: [makeMockTransactionActivity({ id: 'a', timestamp: 1, fee: 123n })],
      'mock-token': [makeMockTransactionActivity({ id: 'a', timestamp: 1, fee: 0n })],
    };
    const result = mergeActivities(txsBySlug);
    // tokenTx should have fee from trxTx
    const resultTokenTx = result.find((a) => a.id === 'a') as ApiTransactionActivity;
    expect(resultTokenTx.fee).toBe(123n);
  });

  it('does not duplicate swap activities shared between TRX and token', () => {
    const swap = makeMockSwapActivity({ id: 'swap1', timestamp: 1 });
    const txsBySlug = {
      [TRX.slug]: [swap],
      'mock-token': [swap],
    };
    const result = mergeActivities(txsBySlug);
    // Only one swap activity should be present
    expect(result.filter((a) => a.id === 'swap1').length).toBe(1);
  });
});
