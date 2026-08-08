import type { WalletOperationIntent } from '../common/activities/reconciler/types';
import type { ApiSwapActivity, ApiTransactionActivity } from '../types';

import { fetchPastActivities, reconcileActivityUpdate } from './activities';

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

jest.mock('../common/swap', () => ({
  swapReplaceActivities: jest.fn((_accountId: string, activities: unknown[]) => activities),
}));

jest.mock('../common/activities/reconciler/activeCexSwapState', () => ({
  getActiveCexSwapStates: jest.fn(),
}));

jest.mock('../common/activities/reconciler/operationIntentStore', () => ({
  getWalletOperationIntents: jest.fn(),
}));

jest.mock('../common/activities/reconciler/tonTraceReconciler', () => ({
  reconcileTonAggregatorActivitiesForAccount: jest.fn((_accountId: string, activities: unknown[]) => ({
    activities,
    knownAggregatorTraceIds: [],
    newlyKnownAggregatorTraceIds: [],
    knownAggregatorTraceProjections: [],
    newlyKnownAggregatorTraceProjections: [],
    deaggregatedTraceIds: [],
    deaggregatedExternalMsgHashes: [],
  })),
}));

jest.mock('./swap', () => ({
  fetchSwaps: jest.fn(),
}));

// Proxy returns a stable stub per chain key, so the mock survives additions and removals
// of chains in `CHAIN_CONFIG` without a manual list, and `expect(stub).toHaveBeenCalled()`
// keeps working across multiple accesses to the same chain.
jest.mock('../chains', () => {
  const stubsByChain = new Map<string, unknown>();
  return {
    __esModule: true,
    default: new Proxy({}, {
      get: (_target, chain: string) => {
        if (!stubsByChain.has(chain)) {
          stubsByChain.set(chain, {
            fetchActivitySlice: jest.fn().mockResolvedValue([]),
            crosschain: {
              fetchCrossChainActivitySlice: jest.fn().mockResolvedValue([]),
            },
          });
        }
        return stubsByChain.get(chain);
      },
    }),
  };
});

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchStoredAccount } = require('../common/accounts') as {
  fetchStoredAccount: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as Record<string, {
  fetchActivitySlice: jest.Mock;
  crosschain: { fetchCrossChainActivitySlice: jest.Mock };
}>;

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { swapReplaceActivities } = require('../common/swap') as {
  swapReplaceActivities: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getActiveCexSwapStates } = require('../common/activities/reconciler/activeCexSwapState') as {
  getActiveCexSwapStates: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { getWalletOperationIntents } = require('../common/activities/reconciler/operationIntentStore') as {
  getWalletOperationIntents: jest.Mock;
};

const {
  reconcileTonAggregatorActivitiesForAccount,
// eslint-disable-next-line @typescript-eslint/no-require-imports
} = require('../common/activities/reconciler/tonTraceReconciler') as {
  reconcileTonAggregatorActivitiesForAccount: jest.Mock;
};

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchSwaps } = require('./swap') as {
  fetchSwaps: jest.Mock;
};

describe('fetchPastActivities', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // Persisted `account.byChain` may outlive a chain being removed from CHAIN_CONFIG.
  // The slice fetcher must skip such stored keys; otherwise the whole slice rejects and
  // the past-activity loader silently returns undefined, leaving the UI on a skeleton.
  it('survives a stale chain key in account.byChain', async () => {
    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: {
        ton: { address: 'EQ-test', publicKey: '00' },
        polygon: { address: '0x-test', publicKey: '00' },
      },
    });

    const result = await fetchPastActivities('0-mainnet', 50);

    expect(result).toBeDefined();
    expect(result!.activities).toEqual([]);
    expect(result!.hasMore).toBe(false);
  });

  it('marks the boundary trace incomplete when sorting made its activities non-contiguous', async () => {
    const boundaryA = makeTransaction({ id: 'boundary-trace:0', timestamp: 1_700_000_000_003 });
    const other = makeTransaction({ id: 'other-trace:0', timestamp: 1_700_000_000_002 });
    const boundaryB = makeTransaction({ id: 'boundary-trace:1', timestamp: 1_700_000_000_001 });

    fetchStoredAccount.mockResolvedValue({
      type: 'mnemonic',
      byChain: { ton: { address: 'EQ-test', publicKey: '00' } },
    });
    chains.ton.fetchActivitySlice.mockResolvedValue([boundaryA, other, boundaryB]);

    const result = await fetchPastActivities('0-mainnet', 3);

    expect(result).toEqual({ activities: [boundaryA, other], hasMore: true });
    expect(swapReplaceActivities).toHaveBeenCalledWith(
      '0-mainnet',
      [boundaryA, other],
      undefined,
      undefined,
      { incompleteTonTraceIds: ['boundary-trace'] },
    );
  });
});

describe('reconcileActivityUpdate', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    getActiveCexSwapStates.mockResolvedValue([]);
    getWalletOperationIntents.mockResolvedValue([]);
    reconcileTonAggregatorActivitiesForAccount.mockImplementation((_accountId: string, activities: unknown[]) => ({
      activities,
      knownAggregatorTraceIds: [],
      newlyKnownAggregatorTraceIds: [],
      knownAggregatorTraceProjections: [],
      newlyKnownAggregatorTraceProjections: [],
      deaggregatedTraceIds: [],
      deaggregatedExternalMsgHashes: [],
    }));
  });

  it('exposes the SDK new-activity reconciliation patch through the API bridge', async () => {
    const localActivity = makeTransaction({
      id: 'local::local',
      status: 'pendingTrusted',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['local::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const pendingActivity = makeTransaction({
      id: 'pending',
      status: 'pending',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['pending'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });

    const result = await reconcileActivityUpdate('account-1', [localActivity], [], [pendingActivity]);

    expect(result.patch).toEqual(expect.objectContaining({
      accountId: 'account-1',
      removeIds: [localActivity.id],
      replacedIds: { [localActivity.id]: pendingActivity.id },
      upsert: [expect.objectContaining({ id: pendingActivity.id, status: 'pendingTrusted' })],
    }));
  });

  it('projects a full pending TON trace before matching and immediately replaces the local swap', async () => {
    const externalMsgHashNorm = 'ton-external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
      status: 'pendingTrusted',
      cex: undefined,
      externalMsgHashNorm,
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const aggregate = makeSwap({
      id: 'trace-id:0',
      status: 'pending',
      cex: undefined,
      externalMsgHashNorm,
      extra: {
        mtwAggregator: {
          traceId: 'trace-id',
          swapIds: ['trace-id:0', 'trace-id:1'],
          from: 'toncoin',
          to: 'ton-usdt',
        },
        reconciliation: {
          sourceActionIds: ['trace-id:0', 'trace-id:1', 'trace-id:fee'],
          hiddenSourceActionIds: ['trace-id:1', 'trace-id:fee'],
          reason: 'ton-aggregated-swap',
        },
      },
    });
    const hiddenLeg = makeSwap({
      id: 'trace-id:1',
      status: 'pending',
      cex: undefined,
      externalMsgHashNorm,
      shouldHide: true,
      extra: aggregate.extra,
    });
    const hiddenSupport = makeTransaction({
      id: 'trace-id:fee',
      status: 'pending',
      externalMsgHashNorm,
      shouldHide: true,
      extra: {
        reconciliation: aggregate.extra!.reconciliation,
      },
    });
    reconcileTonAggregatorActivitiesForAccount.mockResolvedValue({
      activities: [aggregate, hiddenLeg, hiddenSupport],
      knownAggregatorTraceIds: ['trace-id'],
      newlyKnownAggregatorTraceIds: ['trace-id'],
      knownAggregatorTraceProjections: [],
      newlyKnownAggregatorTraceProjections: [],
      deaggregatedTraceIds: [],
      deaggregatedExternalMsgHashes: [],
    });

    const result = await reconcileActivityUpdate(
      'account-1',
      [localSwap],
      [],
      [
        { ...aggregate, extra: undefined },
        { ...hiddenLeg, shouldHide: undefined, extra: undefined },
        { ...hiddenSupport, shouldHide: undefined, extra: undefined },
      ],
    );

    expect(reconcileTonAggregatorActivitiesForAccount).toHaveBeenCalledWith(
      'account-1',
      expect.arrayContaining([
        expect.objectContaining({ id: aggregate.id }),
        expect.objectContaining({ id: hiddenLeg.id }),
        expect.objectContaining({ id: hiddenSupport.id }),
      ]),
      { isLiveUpdate: true },
    );
    expect(result.patch.removeIds).toEqual([localSwap.id]);
    expect(result.patch.replacedIds).toEqual({ [localSwap.id]: aggregate.id });
    expect(result.patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: aggregate.id, status: 'pendingTrusted' }),
      expect.objectContaining({ id: hiddenLeg.id, shouldHide: true }),
      expect.objectContaining({ id: hiddenSupport.id, shouldHide: true }),
    ]));
    expect(result.patch.upsert.find(({ id }) => id === aggregate.id)?.shouldHide).not.toBe(true);
  });

  it('replaces an existing backend DEX row with the matching TON aggregate', async () => {
    const externalMsgHashNorm = 'ton-external-message-hash';
    const backendSwap = makeSwap({
      id: '1456::backend-swap', cex: undefined, hashes: [externalMsgHashNorm], status: 'completed',
    });
    const aggregate = makeSwap({ id: 'trace-id:0', cex: undefined, externalMsgHashNorm, status: 'completed' });
    reconcileTonAggregatorActivitiesForAccount.mockResolvedValue({ activities: [aggregate] });
    const { patch } = await reconcileActivityUpdate('account-1', [], [aggregate], [], {
      contextActivities: [backendSwap],
    });
    expect(patch.replacedIds?.[backendSwap.id]).toBe(aggregate.id);
  });

  it('removes a local TON swap without a replacement when the first projected trace is failed', async () => {
    const externalMsgHashNorm = 'failed-ton-external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
      status: 'pendingTrusted',
      cex: undefined,
      externalMsgHashNorm,
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const failedRaw = makeTransaction({
      id: 'failed-trace:0',
      status: 'failed',
      externalMsgHashNorm,
    });
    reconcileTonAggregatorActivitiesForAccount.mockResolvedValue({
      activities: [failedRaw],
      knownAggregatorTraceIds: ['failed-trace'],
      newlyKnownAggregatorTraceIds: ['failed-trace'],
      knownAggregatorTraceProjections: [],
      newlyKnownAggregatorTraceProjections: [],
      deaggregatedTraceIds: ['failed-trace'],
      deaggregatedExternalMsgHashes: [externalMsgHashNorm],
    });

    const result = await reconcileActivityUpdate('account-1', [localSwap], [], [failedRaw]);

    expect(result.patch.removeIds).toEqual([localSwap.id]);
    expect(result.patch.replacedIds).toEqual({});
    expect(result.patch.upsert).toEqual([failedRaw]);
  });

  it('uses persisted SDK operation intent hashes instead of amount/address heuristics', async () => {
    const localActivity = makeTransaction({
      id: 'local::local',
      status: 'pendingTrusted',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['local::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const confirmedActivity = makeTransaction({
      id: 'submitted-chain-hash',
      status: 'completed',
    });
    const intent: WalletOperationIntent = {
      operationId: 'op-1',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: confirmedActivity.timestamp - 1_000,
      status: 'pendingTrusted',
      swap: {
        type: 'dex',
        submittedHashes: [confirmedActivity.id],
      },
    };
    getWalletOperationIntents.mockResolvedValue([intent]);

    const result = await reconcileActivityUpdate('account-1', [localActivity], [confirmedActivity], []);

    expect(result.patch.replacedIds).toEqual({ [localActivity.id]: confirmedActivity.id });
    expect(result.patch.removeIds).toEqual([localActivity.id]);
  });

  it('force-refreshes active CEX swaps before projecting incoming raw transactions', async () => {
    const rawReceive = makeTransaction({
      id: 'ton-payout-hash',
      status: 'completed',
      isIncoming: true,
    });
    const canonicalSwap = makeSwap({
      id: 'backend-id::backend-swap',
      status: 'completed',
      hashes: [rawReceive.id],
    });
    getActiveCexSwapStates.mockResolvedValue([{ backendSwapId: 'backend-id', status: 'pendingTrusted' }]);
    fetchSwaps.mockResolvedValue({
      patch: {
        accountId: 'account-1',
        upsert: [canonicalSwap, { ...rawReceive, shouldHide: true }],
        removeIds: [],
      },
    });

    const result = await reconcileActivityUpdate(
      'account-1',
      [],
      [rawReceive],
      [],
      { contextActivities: [canonicalSwap], forceCexRefreshTimeoutMs: 10 },
    );

    expect(fetchSwaps).toHaveBeenCalledWith(
      'account-1',
      [{ id: 'backend-id', chain: 'ton' }],
      expect.arrayContaining([expect.objectContaining({ id: rawReceive.id })]),
      { forceProviderRefresh: true },
    );
    expect(result.patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: canonicalSwap.id }),
      expect.objectContaining({ id: rawReceive.id, shouldHide: true }),
    ]));
  });

  it('handles incoming pending raw transactions in CEX pre-render refresh', async () => {
    const rawPendingPayin = makeTransaction({
      id: 'tron-payin-hash',
      status: 'pending',
    });
    const canonicalSwap = makeSwap({
      id: 'backend-id::backend-swap',
      status: 'pendingTrusted',
      hashes: [rawPendingPayin.id],
    });
    getActiveCexSwapStates.mockResolvedValue([{ backendSwapId: 'backend-id', status: 'pendingTrusted' }]);
    fetchSwaps.mockResolvedValue({
      patch: {
        accountId: 'account-1',
        upsert: [canonicalSwap, { ...rawPendingPayin, shouldHide: true }],
        removeIds: [],
      },
    });

    const result = await reconcileActivityUpdate(
      'account-1',
      [],
      [],
      [rawPendingPayin],
      { contextActivities: [canonicalSwap], forceCexRefreshTimeoutMs: 10 },
    );

    expect(fetchSwaps).toHaveBeenCalledWith(
      'account-1',
      [{ id: 'backend-id', chain: 'ton' }],
      expect.arrayContaining([expect.objectContaining({ id: rawPendingPayin.id })]),
      { forceProviderRefresh: true },
    );
    expect(result.pendingActivities).toEqual([
      expect.objectContaining({ id: rawPendingPayin.id, shouldHide: true }),
    ]);
    expect(result.confirmedActivities).toEqual([
      expect.objectContaining({ id: canonicalSwap.id }),
    ]);
  });

  it('preserves pendingTrusted status when the CEX projection updates the same source id', async () => {
    const previousRaw = makeTransaction({
      id: 'tron-payin-hash',
      status: 'pendingTrusted',
    });
    const incomingRaw = makeTransaction({
      id: previousRaw.id,
      status: 'pending',
    });
    const canonicalSwap = makeSwap({
      id: 'backend-id::backend-swap',
      hashes: [incomingRaw.id],
    });
    getActiveCexSwapStates.mockResolvedValue([{ backendSwapId: 'backend-id', status: 'pendingTrusted' }]);
    fetchSwaps.mockResolvedValue({
      patch: {
        accountId: 'account-1',
        upsert: [canonicalSwap, { ...incomingRaw, shouldHide: true }],
        removeIds: [],
      },
    });

    const result = await reconcileActivityUpdate(
      'account-1',
      [previousRaw],
      [],
      [incomingRaw],
      { contextActivities: [canonicalSwap, previousRaw], forceCexRefreshTimeoutMs: 10 },
    );

    expect(result.pendingActivities).toEqual([
      expect.objectContaining({ id: incomingRaw.id, status: 'pendingTrusted', shouldHide: true }),
    ]);
    expect(result.patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: incomingRaw.id, status: 'pendingTrusted', shouldHide: true }),
    ]));
  });

  it('keeps incoming raw visible when active CEX refresh returns no explicit hash', async () => {
    const rawReceive = makeTransaction({ id: 'ton-payout-hash', status: 'completed', isIncoming: true });
    getActiveCexSwapStates.mockResolvedValue([{ backendSwapId: 'backend-id', status: 'pendingTrusted' }]);
    fetchSwaps.mockResolvedValue({ patch: { accountId: 'account-1', upsert: [], removeIds: [] } });

    const result = await reconcileActivityUpdate(
      'account-1', [], [rawReceive], [], { forceCexRefreshTimeoutMs: 10 },
    );

    expect(result.patch.upsert).toEqual([expect.objectContaining({ id: rawReceive.id })]);
    expect(result.patch.upsert[0]).not.toHaveProperty('shouldHide');
  });

  it('keeps incoming raw visible when active CEX force refresh times out', async () => {
    const rawReceive = makeTransaction({ id: 'ton-payout-hash', status: 'completed', isIncoming: true });
    getActiveCexSwapStates.mockResolvedValue([{ backendSwapId: 'backend-id', status: 'pendingTrusted' }]);
    fetchSwaps.mockReturnValue(new Promise(() => undefined));

    const result = await reconcileActivityUpdate(
      'account-1', [], [rawReceive], [], { forceCexRefreshTimeoutMs: 0 },
    );

    expect(result.patch.upsert).toEqual([expect.objectContaining({ id: rawReceive.id })]);
    expect(result.patch.upsert[0]).not.toHaveProperty('shouldHide');
  });

  it('does not force-refresh completed CEX state', async () => {
    const rawReceive = makeTransaction({ id: 'ton-payout-hash', status: 'completed', isIncoming: true });
    getActiveCexSwapStates.mockResolvedValue([]);

    await reconcileActivityUpdate('account-1', [], [rawReceive], []);

    expect(fetchSwaps).not.toHaveBeenCalled();
  });
});

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'backend-id::backend-swap',
    timestamp: 1_700_000_000_000,
    from: 'trx',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'toncoin',
    toAmount: '5',
    networkFee: '0.1',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    cex: { payinAddress: 'payin', payoutAddress: 'payout', status: 'waiting', transactionId: 'cex-id' },
    ...overrides,
  } as ApiSwapActivity;
}

function makeTransaction(overrides: Partial<ApiTransactionActivity> = {}): ApiTransactionActivity {
  return {
    kind: 'transaction',
    id: 'tx-hash',
    timestamp: 1_700_000_000_000,
    amount: -100n,
    fromAddress: 'from-address',
    toAddress: 'to-address',
    fee: 1n,
    slug: 'toncoin',
    isIncoming: false,
    normalizedAddress: 'normalized-address',
    status: 'pending',
    ...overrides,
  };
}
