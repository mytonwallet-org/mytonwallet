import type { ApiTransactionActivity } from '../../types';

import { TRX } from '../../../config';
import { makeMockSwapActivity, makeMockTransactionActivity } from '../../../../tests/mocks';
import { mergeActivities, parseRawTrxTransaction } from './activities';

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

  it('filters out TRX transactions with shouldHide flag', () => {
    const txsBySlug = {
      [TRX.slug]: [
        makeMockTransactionActivity({ id: 'a', timestamp: 2, shouldHide: false }),
        makeMockTransactionActivity({ id: 'b', timestamp: 1, shouldHide: true }),
      ],
      'mock-token': [
        makeMockTransactionActivity({ id: 'c', timestamp: 3 }),
      ],
    };
    const result = mergeActivities(txsBySlug);
    expect(result.map((a) => a.id)).toEqual(['c', 'a']);
  });

  it('filters out token transfer TRX transaction but keeps token transaction', () => {
    const txsBySlug = {
      [TRX.slug]: [
        makeMockTransactionActivity({ id: 'token-tx', timestamp: 1, fee: 100n, shouldHide: true }),
      ],
      'tron:TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t': [
        makeMockTransactionActivity({ id: 'token-tx', timestamp: 1, fee: 0n }),
      ],
    };
    const result = mergeActivities(txsBySlug);
    expect(result.length).toBe(1);
    expect(result[0].id).toBe('token-tx');
    const resultTx = result[0];
    if (resultTx.kind !== 'transaction') {
      throw new Error('Expected transaction activity');
    }
    expect(resultTx.fee).toBe(100n);
  });
});

describe('parseRawTrxTransaction', () => {
  const testAddress = 'TBgmsoKF7ZV12dkfHqvpjdui3VxxAoN4q4';

  it('marks token transfer transaction (a9059cbb) as shouldHide', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const testTx = require('./testData/tokenTransferTrxTransaction.json');
    const result = parseRawTrxTransaction(testAddress, testTx);
    expect(result.shouldHide).toBe(true);
  });

  it('marks token transferFrom transaction (23b872dd) as shouldHide', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const testTx = require('./testData/tokenTransferFromTrxTransaction.json');
    const result = parseRawTrxTransaction(testAddress, testTx);
    expect(result.shouldHide).toBe(true);
  });

  it('does not mark regular TransferContract as shouldHide (except TransferAssetContract)', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const testTx = require('./testData/regularTrxTransfer.json');
    const result = parseRawTrxTransaction(testAddress, testTx);
    expect(result.shouldHide).toBe(false);
  });

  it('marks TransferAssetContract as shouldHide', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const testTx = require('./testData/assetTransfer.json');
    const result = parseRawTrxTransaction(testAddress, testTx);
    expect(result.shouldHide).toBe(true);
  });

  it('does not mark non-token TriggerSmartContract as shouldHide', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const testTx = require('./testData/smartContractCall.json');
    const result = parseRawTrxTransaction(testAddress, testTx);
    expect(result.shouldHide).toBe(false);
  });
});
