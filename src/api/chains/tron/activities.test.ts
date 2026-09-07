import type { ApiTransactionActivity } from '../../types';

import { TRC20_USDT_MAINNET, TRX } from '../../../config';
import { fetchJson } from '../../../util/fetch';
import { makeMockSwapActivity, makeMockTransactionActivity } from '../../../../tests/mocks';
import {
  getTokenActivitySlice,
  mergeActivities,
  parseRawTrxTransaction,
} from './activities';

jest.mock('../../../util/fetch', () => ({
  fetchJson: jest.fn(),
}));

const fetchJsonMock = jest.mocked(fetchJson);

const TEST_TRC20_ADDRESS = 'TBgmsoKF7ZV12dkfHqvpjdui3VxxAoN4q4';
const TEST_OWNER_ADDRESS = 'TKk2k4trTUSksCiA3k8Aq5WAsUo3b8FCKj';
const MAX_UINT256_STRING = '115792089237316195423570985008687907853269984665640564039457584007913129639935';

describe('getTokenActivitySlice', () => {
  beforeEach(() => {
    fetchJsonMock.mockReset();
  });

  it('keeps unlimited approvals as non-monetary activities', async () => {
    fetchJsonMock.mockResolvedValue({
      data: [{
        transaction_id: 'approval-tx',
        block_timestamp: 1,
        from: TEST_OWNER_ADDRESS,
        to: TEST_TRC20_ADDRESS,
        type: 'Approval',
        value: MAX_UINT256_STRING,
        token_info: {
          address: TRC20_USDT_MAINNET.tokenAddress,
        },
      }],
    });

    await expect(getTokenActivitySlice(
      'mainnet',
      TEST_TRC20_ADDRESS,
      TRC20_USDT_MAINNET.slug,
      undefined,
      undefined,
      1,
    )).resolves.toMatchObject({
      activities: [{
        id: 'approval-tx',
        amount: BigInt(MAX_UINT256_STRING),
        fromAddress: TEST_OWNER_ADDRESS,
        toAddress: TEST_TRC20_ADDRESS,
        isIncoming: true,
        slug: TRC20_USDT_MAINNET.slug,
        type: 'approval',
        isApprovalUnlimited: true,
      }],
      hasMore: true,
    });
  });

  it('keeps finite outgoing approvals unsigned', async () => {
    fetchJsonMock.mockResolvedValue({
      data: [{
        transaction_id: 'approval-tx',
        block_timestamp: 1,
        from: TEST_OWNER_ADDRESS,
        to: TEST_TRC20_ADDRESS,
        type: 'Approval',
        value: '1000000',
        token_info: {
          address: TRC20_USDT_MAINNET.tokenAddress,
        },
      }],
    });

    await expect(getTokenActivitySlice(
      'mainnet',
      TEST_OWNER_ADDRESS,
      TRC20_USDT_MAINNET.slug,
    )).resolves.toMatchObject({
      activities: [{
        id: 'approval-tx',
        amount: 1000000n,
        isIncoming: false,
        type: 'approval',
        isApprovalUnlimited: false,
      }],
    });
  });

  it('keeps transfers as token activities', async () => {
    fetchJsonMock.mockResolvedValue({
      data: [{
        transaction_id: 'transfer-tx',
        block_timestamp: 2,
        from: TEST_OWNER_ADDRESS,
        to: TEST_TRC20_ADDRESS,
        type: 'Transfer',
        value: '1000000',
        token_info: {
          address: TRC20_USDT_MAINNET.tokenAddress,
        },
      }],
    });

    await expect(getTokenActivitySlice(
      'mainnet',
      TEST_TRC20_ADDRESS,
      TRC20_USDT_MAINNET.slug,
      undefined,
      undefined,
      2,
    )).resolves.toMatchObject({
      activities: [{
        id: 'transfer-tx',
        amount: 1000000n,
        isIncoming: true,
        slug: TRC20_USDT_MAINNET.slug,
      }],
      hasMore: false,
    });
  });

  it('prefers a transfer when the same transaction also emits approvals', async () => {
    fetchJsonMock.mockResolvedValue({
      data: [
        {
          transaction_id: 'compound-tx',
          block_timestamp: 3,
          from: TEST_OWNER_ADDRESS,
          to: TEST_TRC20_ADDRESS,
          type: 'Approval',
          value: '0',
          token_info: {
            address: TRC20_USDT_MAINNET.tokenAddress,
          },
        },
        {
          transaction_id: 'compound-tx',
          block_timestamp: 3,
          from: TEST_OWNER_ADDRESS,
          to: TEST_TRC20_ADDRESS,
          type: 'Transfer',
          value: '97435484671',
          token_info: {
            address: TRC20_USDT_MAINNET.tokenAddress,
          },
        },
        {
          transaction_id: 'compound-tx',
          block_timestamp: 3,
          from: TEST_OWNER_ADDRESS,
          to: TEST_TRC20_ADDRESS,
          type: 'Approval',
          value: '97435484671',
          token_info: {
            address: TRC20_USDT_MAINNET.tokenAddress,
          },
        },
      ],
    });

    const result = await getTokenActivitySlice(
      'mainnet',
      TEST_OWNER_ADDRESS,
      TRC20_USDT_MAINNET.slug,
    );

    expect(result.activities).toHaveLength(1);
    expect(result.activities[0]).toMatchObject({
      id: 'compound-tx',
      amount: -97435484671n,
      isIncoming: false,
    });
    expect(result.activities[0]).not.toMatchObject({ type: 'approval' });
  });
});

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

  it('prefers a transfer over an approval emitted for another token in the same transaction', () => {
    const txsBySlug = {
      'approval-token': [makeMockTransactionActivity({
        id: 'compound-tx',
        timestamp: 1,
        slug: 'approval-token',
        amount: 0n,
        type: 'approval',
      })],
      'transfer-token': [makeMockTransactionActivity({
        id: 'compound-tx',
        timestamp: 1,
        slug: 'transfer-token',
        amount: -100n,
      })],
    };

    const result = mergeActivities(txsBySlug);

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: 'compound-tx',
      slug: 'transfer-token',
      amount: -100n,
    });
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
