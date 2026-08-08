import type { ApiSwapActivity } from '../../../types';

import { getActivityIdReplacementsFromSdkMatcher } from './matcher';
import {
  buildCexSwapOperationIntent,
  buildDexSwapOperationIntent,
  buildSwapOperationId,
  getWalletOperationIntents,
  rememberCexSwapOperationIntent,
  rememberWalletOperationSubmittedHashes,
  upsertWalletOperationIntent,
} from './operationIntentStore';

const mockStorageState: Record<string, any> = {};

jest.mock('../../../storages', () => ({
  storage: {
    getItem: jest.fn((key: string) => Promise.resolve(mockStorageState[key])),
    mutateItem: jest.fn(async (key: string, mutate: AnyFunction) => {
      const snapshot = mockStorageState[key];
      await new Promise((resolve) => {
        setTimeout(resolve, 1);
      });
      const nextValue = mutate(snapshot);
      if (nextValue === undefined) {
        delete mockStorageState[key];
      } else {
        mockStorageState[key] = nextValue;
      }
      return nextValue;
    }),
  },
}));

const BASE_TIMESTAMP = 1_700_000_000_000;

beforeEach(() => {
  Object.keys(mockStorageState).forEach((key) => {
    delete mockStorageState[key];
  });
});

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'swap-id::local',
    timestamp: BASE_TIMESTAMP,
    from: 'toncoin',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'ton-usdt',
    toAmount: '20',
    networkFee: '0.1',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    transactionIds: {},
    ...overrides,
  };
}

describe('wallet operation intent store helpers', () => {
  it('builds a TON DEX swap intent with gasless and expected external message metadata', () => {
    const intent = buildDexSwapOperationIntent('account-1', makeSwap(), {
      gasless: true,
      expectedExternalMsgHashNorm: 'external-message-hash',
    });

    expect(intent).toEqual(expect.objectContaining({
      operationId: 'swap:swap-id',
      accountId: 'account-1',
      kind: 'swap',
      status: 'pendingTrusted',
      from: expect.objectContaining({ slug: 'toncoin', amount: '10', chain: 'ton' }),
      to: expect.objectContaining({ slug: 'ton-usdt', amount: '20', chain: 'ton' }),
      swap: expect.objectContaining({
        type: 'dex',
        backendSwapId: 'swap-id',
        gasless: true,
        expectedExternalMsgHashNorm: 'external-message-hash',
      }),
    }));
  });

  it('links a local TON swap to a later confirmed swap by SDK operation id', () => {
    const localSwap = makeSwap({
      id: 'swap-id::local',
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const confirmedSwap = makeSwap({
      id: 'trace-id:0',
      status: 'completed',
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['trace-id:0'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });

    expect(getActivityIdReplacementsFromSdkMatcher([localSwap], [confirmedSwap])).toEqual({
      [localSwap.id]: confirmedSwap.id,
    });
  });

  it('normalizes projected CEX swap ids so create and submit paths merge into one intent', async () => {
    const projectedCexSwap = makeSwap({
      id: 'cex-backend-id::backend-swap',
      hashes: [],
      transactionIds: {},
      cex: {
        payinAddress: 'payin-address',
        payoutAddress: 'payout-address',
        status: 'waiting',
        transactionId: 'cex-transaction-id',
      },
    });

    expect(buildCexSwapOperationIntent('account-1', projectedCexSwap)).toEqual(expect.objectContaining({
      operationId: 'swap:cex-backend-id',
      swap: expect.objectContaining({ backendSwapId: 'cex-backend-id' }),
    }));
    expect(buildSwapOperationId(projectedCexSwap.id)).toBe('swap:cex-backend-id');

    await rememberCexSwapOperationIntent('account-1', projectedCexSwap);
    await rememberWalletOperationSubmittedHashes(
      'account-1',
      buildSwapOperationId(projectedCexSwap.id),
      ['submitted-hash'],
    );

    const intents = await getWalletOperationIntents('account-1');
    expect(intents).toHaveLength(1);
    expect(intents[0]).toEqual(expect.objectContaining({
      operationId: 'swap:cex-backend-id',
      swap: expect.objectContaining({
        backendSwapId: 'cex-backend-id',
        submittedHashes: ['submitted-hash'],
      }),
    }));
  });

  it('serializes concurrent wallet operation intent mutations per storage key', async () => {
    const firstIntent = buildDexSwapOperationIntent('account-1', makeSwap({ id: 'swap-a::local' }));
    const secondIntent = buildDexSwapOperationIntent('account-1', makeSwap({ id: 'swap-b::local' }));

    await Promise.all([
      upsertWalletOperationIntent(firstIntent),
      upsertWalletOperationIntent(secondIntent),
      rememberWalletOperationSubmittedHashes('account-1', firstIntent.operationId, ['submitted-a']),
    ]);

    const intents = await getWalletOperationIntents('account-1');

    expect(intents.map(({ operationId }) => operationId).sort()).toEqual([
      firstIntent.operationId,
      secondIntent.operationId,
    ].sort());
    expect(intents.find(({ operationId }) => operationId === firstIntent.operationId)?.swap?.submittedHashes)
      .toContain('submitted-a');
  });
});
