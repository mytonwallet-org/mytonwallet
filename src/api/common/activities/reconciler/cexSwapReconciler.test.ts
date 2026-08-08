import type { ApiSwapActivity, ApiTransactionActivity } from '../../../types';
import type { WalletOperationIntent } from './types';

import {
  buildCexSwapRefreshPatch,
  getCexSwapIdsRepresentedBySourceActivities,
  projectCexSwapActivities,
} from './cexSwapReconciler';
import { buildCexSwapOperationIntent } from './operationIntentStore';

const BASE_TIMESTAMP = 1_700_000_000_000;

function makeTransaction(overrides: Partial<ApiTransactionActivity> = {}): ApiTransactionActivity {
  return {
    kind: 'transaction',
    id: 'tx-hash',
    timestamp: BASE_TIMESTAMP,
    amount: -100n,
    fromAddress: 'from-address',
    toAddress: 'to-address',
    fee: 1n,
    slug: 'toncoin',
    isIncoming: false,
    normalizedAddress: 'normalized-address',
    status: 'completed',
    ...overrides,
  };
}

function makeCexSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'backend-swap-id::backend-swap',
    timestamp: BASE_TIMESTAMP,
    from: 'toncoin',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'solana-sol',
    toAmount: '20',
    networkFee: '0.1',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    transactionIds: {},
    cex: {
      payinAddress: 'payin-address',
      payoutAddress: 'payout-address',
      status: 'waiting',
      transactionId: 'cex-transaction-id',
    },
    ...overrides,
  };
}

describe('CEX swap reconciler', () => {
  it('hides a raw transaction matched by TON externalMsgHashNorm even when its id hash differs', () => {
    const raw = makeTransaction({ id: 'trace-id:0', externalMsgHashNorm: 'external-msg-hash' });
    const swap = makeCexSwap({ hashes: ['external-msg-hash'] });

    const { projectedSourceActivities } = projectCexSwapActivities([raw], [swap], new Set([swap.id]));

    expect(projectedSourceActivities[0]).toEqual(expect.objectContaining({
      id: raw.id,
      shouldHide: true,
      extra: expect.objectContaining({
        reconciliation: expect.objectContaining({
          sourceActionIds: [raw.id],
          hiddenSourceActionIds: [raw.id],
          reason: 'cex-swap',
        }),
      }),
    }));
  });

  it('hides a raw transaction matched by SDK operation-intent submitted hash before backend hashes catch up', () => {
    const raw = makeTransaction({ id: 'evm-submitted-hash' });
    const swap = makeCexSwap({ hashes: [] });
    const intent: WalletOperationIntent = {
      operationId: 'swap:backend-swap-id',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP,
      status: 'pendingTrusted',
      swap: {
        type: 'cex',
        backendSwapId: 'backend-swap-id',
        cexTransactionId: 'cex-transaction-id',
        submittedHashes: ['evm-submitted-hash'],
      },
    };

    const { projectedSourceActivities } = projectCexSwapActivities([raw], [swap], new Set([swap.id]), [intent]);

    expect(projectedSourceActivities[0]).toEqual(expect.objectContaining({
      shouldHide: true,
      extra: expect.objectContaining({
        reconciliation: expect.objectContaining({ operationId: 'swap:backend-swap-id' }),
      }),
    }));
  });

  it('does not hide a raw transaction when two CEX swaps claim the same hash', () => {
    const raw = makeTransaction({ id: 'shared-hash' });
    const firstSwap = makeCexSwap({ id: 'first::backend-swap', hashes: [raw.id] });
    const secondSwap = makeCexSwap({ id: 'second::backend-swap', hashes: [raw.id] });

    const { projectedSourceActivities } = projectCexSwapActivities(
      [raw],
      [firstSwap, secondSwap],
      new Set([firstSwap.id, secondSwap.id]),
    );

    expect(projectedSourceActivities[0].shouldHide).toBeUndefined();
  });

  it('normalizes mixed-case EVM submitted hashes before CEX relation checks', () => {
    const raw = makeTransaction({ id: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd' });
    const swap = makeCexSwap({ hashes: [] });
    const intent: WalletOperationIntent = {
      operationId: 'swap:backend-swap-id',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP,
      status: 'pendingTrusted',
      swap: {
        type: 'cex',
        backendSwapId: 'backend-swap-id',
        cexTransactionId: 'cex-transaction-id',
        submittedHashes: ['0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD'],
      },
    };

    const { projectedSourceActivities } = projectCexSwapActivities([raw], [swap], new Set([swap.id]), [intent]);

    expect(projectedSourceActivities[0]).toEqual(expect.objectContaining({ shouldHide: true }));
  });

  it('only emits backend swap rows whose timestamps belong to the requested slice', () => {
    const visibleSwap = makeCexSwap({ id: 'visible::backend-swap' });
    const hiddenContextSwap = makeCexSwap({ id: 'context::backend-swap' });

    const { projectedSwapActivities } = projectCexSwapActivities(
      [],
      [visibleSwap, hiddenContextSwap],
      new Set([visibleSwap.id]),
    );

    expect(projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: visibleSwap.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            reason: 'cex-swap',
            sourceActionIds: [visibleSwap.id],
          }),
        }),
      }),
    ]);
  });

  it('does not hide a raw transaction when its matched CEX swap is context-only and not emitted', () => {
    const raw = makeTransaction({ id: 'context-hash' });
    const contextOnlySwap = makeCexSwap({ id: 'context::backend-swap', hashes: ['context-hash'] });

    const result = projectCexSwapActivities([raw], [contextOnlySwap], new Set());

    expect(result.projectedSwapActivities).toEqual([]);
    expect(result.projectedSourceActivities[0].shouldHide).toBeUndefined();
  });

  it('force-emits a matched CEX replacement when raw source rows are in the current slice', () => {
    const rawPayin = makeTransaction({ id: 'payin-hash', timestamp: BASE_TIMESTAMP + 30_000 });
    const rawPayout = makeTransaction({ id: 'payout-hash', timestamp: BASE_TIMESTAMP + 60_000 });
    const swap = makeCexSwap({
      id: 'backend-swap-id::backend-swap',
      timestamp: BASE_TIMESTAMP,
      hashes: ['payin-hash', 'payout-hash'],
      transactionIds: {},
      status: 'completed',
    });

    const visibleSwapIds = getCexSwapIdsRepresentedBySourceActivities([rawPayout, rawPayin], [swap]);
    const result = projectCexSwapActivities([rawPayout, rawPayin], [swap], visibleSwapIds);

    expect([...visibleSwapIds]).toEqual([swap.id]);
    expect(result.projectedSourceActivities).toEqual([
      expect.objectContaining({ id: rawPayout.id, shouldHide: true }),
      expect.objectContaining({ id: rawPayin.id, shouldHide: true }),
    ]);
    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: swap.id,
        status: 'completed',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [swap.id, rawPayout.id, rawPayin.id],
            hiddenSourceActionIds: [rawPayout.id, rawPayin.id],
          }),
        }),
      }),
    ]);
  });

  it('does not hide a raw transaction only because its tx hash equals a backend swap id', () => {
    const raw = makeTransaction({ id: 'backend-swap-id' });
    const swap = makeCexSwap({ id: 'backend-swap-id::backend-swap', hashes: [] });

    const { projectedSourceActivities } = projectCexSwapActivities([raw], [swap]);

    expect(projectedSourceActivities[0].shouldHide).toBeUndefined();
  });

  it('builds an SDK patch for fetched CEX refresh results', () => {
    const active = makeCexSwap({ id: 'active::backend-swap' });
    const missing = makeCexSwap({ id: 'missing::backend-swap', status: 'pendingTrusted' });

    const patch = buildCexSwapRefreshPatch('account-1', [active], ['missing'], [missing]);

    expect(patch).toEqual(expect.objectContaining({
      accountId: 'account-1',
      removeIds: [],
      replacedIds: {},
      upsert: expect.arrayContaining([
        expect.objectContaining({ id: active.id, status: active.status }),
        expect.objectContaining({ id: missing.id, status: 'expired' }),
      ]),
    }));
    expect(patch.upsert.find(({ id }) => id === missing.id)?.shouldHide).not.toBe(true);
    expect(patch.upsert.every((activity) => activity.extra?.reconciliation?.reason === 'cex-swap')).toBe(true);
  });

  it('builds an SDK refresh patch that hides cached raw transactions covered by CEX hashes', () => {
    const raw = makeTransaction({ id: 'covered-hash' });
    const swap = makeCexSwap({ id: 'active::backend-swap', hashes: ['covered-hash'] });

    const patch = buildCexSwapRefreshPatch('account-1', [swap], [], [raw, swap]);

    expect(patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: raw.id, shouldHide: true }),
    ]));
    expect(patch.upsert.find(({ id }) => id === swap.id)?.extra?.reconciliation).toEqual(expect.objectContaining({
      sourceActionIds: [swap.id, raw.id],
      hiddenSourceActionIds: [raw.id],
    }));
  });

  it('does not emit or mutate completed operation A when only pending operation B is refreshed', () => {
    const sourceA = makeTransaction({
      id: 'source-a-hash',
      shouldHide: true,
      extra: {
        reconciliation: {
          operationId: 'swap:operation-a',
          sourceActionIds: ['source-a-hash'],
          hiddenSourceActionIds: ['source-a-hash'],
          reason: 'cex-swap',
        },
      },
    });
    const canonicalA = makeCexSwap({
      id: 'operation-a::backend-swap',
      status: 'completed',
      hashes: [sourceA.id],
      extra: {
        reconciliation: {
          operationId: 'swap:operation-a',
          sourceActionIds: ['operation-a::backend-swap', sourceA.id],
          hiddenSourceActionIds: [sourceA.id],
          reason: 'cex-swap',
        },
      },
    });
    const sourceB = makeTransaction({ id: 'source-b-hash' });
    const existingB = makeCexSwap({
      id: 'operation-b::backend-swap',
      status: 'pendingTrusted',
      hashes: [],
    });
    const refreshedB = makeCexSwap({
      ...existingB,
      hashes: [sourceB.id],
    });

    const patch = buildCexSwapRefreshPatch(
      'account-1',
      [refreshedB],
      [],
      [canonicalA, sourceA, existingB, sourceB],
    );

    expect(patch.upsert.some(({ id }) => id === canonicalA.id || id === sourceA.id)).toBe(false);
    expect(patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: refreshedB.id, status: 'pendingTrusted' }),
      expect.objectContaining({
        id: sourceB.id,
        shouldHide: true,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({ operationId: 'swap:operation-b' }),
        }),
      }),
    ]));
  });

  it('leaves an unowned raw source visible when context operations A and B claim the same identity', () => {
    const sharedSource = makeTransaction({ id: 'shared-refresh-hash' });
    const contextA = makeCexSwap({
      id: 'operation-a::backend-swap',
      status: 'completed',
      hashes: [sharedSource.id],
    });
    const refreshedB = makeCexSwap({
      id: 'operation-b::backend-swap',
      hashes: [sharedSource.id],
    });

    const patch = buildCexSwapRefreshPatch(
      'account-1',
      [refreshedB],
      [],
      [contextA, sharedSource],
    );

    expect(patch.upsert.find(({ id }) => id === sharedSource.id)).toBeUndefined();
    expect(patch.upsert.find(({ id }) => id === refreshedB.id)?.extra?.reconciliation)
      .toEqual(expect.objectContaining({ hiddenSourceActionIds: [] }));
  });

  it('keeps the complete CEX source projection in a self-contained refresh patch', () => {
    const payin = makeTransaction({ id: 'payin-hash', shouldHide: true });
    const payout = makeTransaction({ id: 'payout-hash' });
    const existingSwap = makeCexSwap({
      id: 'active::backend-swap',
      hashes: ['payin-hash', 'payout-hash'],
      extra: {
        reconciliation: {
          operationId: 'swap:active',
          sourceActionIds: ['active::backend-swap', payin.id],
          hiddenSourceActionIds: [payin.id],
          reason: 'cex-swap',
        },
      },
    });
    const refreshedSwap = makeCexSwap({
      id: existingSwap.id,
      hashes: ['payin-hash', 'payout-hash'],
      status: 'completed',
    });

    const patch = buildCexSwapRefreshPatch(
      'account-1',
      [refreshedSwap],
      [],
      [existingSwap, payin, payout],
    );

    expect(patch.upsert.find(({ id }) => id === existingSwap.id)?.extra?.reconciliation).toEqual({
      operationId: 'swap:active',
      sourceActionIds: [existingSwap.id, payin.id, payout.id],
      hiddenSourceActionIds: [payin.id, payout.id],
      reason: 'cex-swap',
    });
  });

  it('keeps an SDK-owned raw source hidden when a later provider response omits its hash', () => {
    const raw = makeTransaction({
      id: 'old-payin-hash',
      shouldHide: true,
      extra: {
        reconciliation: {
          operationId: 'swap:active',
          sourceActionIds: ['active::backend-swap', 'old-payin-hash'],
          hiddenSourceActionIds: ['old-payin-hash'],
          reason: 'cex-swap',
        },
      },
    });
    const oldSwap = makeCexSwap({ id: 'active::backend-swap', hashes: [raw.id] });
    const refreshedSwap = makeCexSwap({ id: oldSwap.id, hashes: [] });

    const patch = buildCexSwapRefreshPatch('account-1', [refreshedSwap], [], [oldSwap, raw]);
    const projectedSwap = patch.upsert.find(({ id }) => id === refreshedSwap.id);

    expect(patch.upsert.find(({ id }) => id === raw.id)).toBeUndefined();
    expect(projectedSwap?.extra?.reconciliation).toEqual(expect.objectContaining({
      operationId: 'swap:active',
      sourceActionIds: [refreshedSwap.id, raw.id],
      hiddenSourceActionIds: [raw.id],
    }));
  });

  it('keeps a canceled CEX operation canonical and hides its explicitly matched source', () => {
    const raw = makeTransaction({ id: 'canceled-payin-hash' });
    const canceledSwap = makeCexSwap({
      id: 'canceled::backend-swap',
      hashes: [raw.id],
      isCanceled: true,
    });

    const patch = buildCexSwapRefreshPatch('account-1', [canceledSwap], [], [raw]);

    expect(patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: canceledSwap.id, status: 'expired' }),
      expect.objectContaining({ id: raw.id, shouldHide: true }),
    ]));
    expect(patch.upsert.find(({ id }) => id === canceledSwap.id)?.shouldHide).not.toBe(true);
  });

  it('keeps a confirmed-404 CEX operation canonical while preserving owned source visibility', () => {
    const raw = makeTransaction({
      id: 'missing-payin-hash',
      shouldHide: true,
      extra: {
        reconciliation: {
          operationId: 'swap:missing',
          sourceActionIds: ['missing-payin-hash'],
          hiddenSourceActionIds: ['missing-payin-hash'],
          reason: 'cex-swap',
        },
      },
    });
    const pendingSwap = makeCexSwap({
      id: 'missing::backend-swap',
      hashes: [raw.id],
      extra: {
        reconciliation: {
          operationId: 'swap:missing',
          sourceActionIds: ['missing::backend-swap', raw.id],
          hiddenSourceActionIds: [raw.id],
          reason: 'cex-swap',
        },
      },
    });

    const patch = buildCexSwapRefreshPatch('account-1', [], ['missing'], [pendingSwap, raw]);
    const expiredSwap = patch.upsert.find(({ id }) => id === pendingSwap.id);

    expect(expiredSwap).toEqual(expect.objectContaining({ status: 'expired' }));
    expect(expiredSwap?.shouldHide).not.toBe(true);
    expect(expiredSwap?.extra?.reconciliation).toEqual(expect.objectContaining({
      hiddenSourceActionIds: [raw.id],
    }));
    expect(patch.upsert.find(({ id }) => id === raw.id)).toBeUndefined();
  });

  it('projects a Solana to Ethereum CEX swap as one visible swap with both raw chain transfers hidden', () => {
    const rawSolanaSend = makeTransaction({ id: 'solana-signature', slug: 'solana-sol' });
    const rawEthereumReceive = makeTransaction({
      id: '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      slug: 'ethereum-eth',
      isIncoming: true,
      amount: 200n,
    });
    const swap = makeCexSwap({
      id: 'sol-eth::backend-swap',
      from: 'solana-sol',
      to: 'ethereum-eth',
      hashes: [rawSolanaSend.id, rawEthereumReceive.id],
      transactionIds: {},
    });

    const result = projectCexSwapActivities([rawSolanaSend, rawEthereumReceive], [swap], new Set([swap.id]));

    expect(result.projectedSourceActivities).toEqual([
      expect.objectContaining({ id: rawSolanaSend.id, shouldHide: true }),
      expect.objectContaining({ id: rawEthereumReceive.id, shouldHide: true }),
    ]);
    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: swap.id,
        from: 'solana-sol',
        to: 'ethereum-eth',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            hiddenSourceActionIds: [rawSolanaSend.id, rawEthereumReceive.id],
          }),
        }),
      }),
    ]);
  });

  it('builds an SDK refresh patch that hides cached raw transactions covered only by submitted-hash intent', () => {
    const raw = makeTransaction({ id: 'submitted-hash' });
    const swap = makeCexSwap({ id: 'active::backend-swap', hashes: [] });
    const intent: WalletOperationIntent = {
      operationId: 'swap:active',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP,
      status: 'pendingTrusted',
      swap: {
        type: 'cex',
        backendSwapId: 'active',
        cexTransactionId: 'cex-transaction-id',
        submittedHashes: ['submitted-hash'],
      },
    };

    const patch = buildCexSwapRefreshPatch('account-1', [swap], [], [raw, swap], [intent]);

    expect(patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({
        id: raw.id,
        shouldHide: true,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({ operationId: 'swap:active' }),
        }),
      }),
    ]));
  });

  it('keeps a raw TON payout visible until backend exposes an explicit payout hash', () => {
    const rawPayout = makeTransaction({
      id: 'ton-payout-hash',
      slug: 'toncoin',
      isIncoming: true,
      amount: 20n,
      toAddress: 'payout-address',
      normalizedAddress: 'payout-address',
    });
    const pendingSwap = makeCexSwap({
      from: 'trx',
      to: 'toncoin',
      fromAmount: '10',
      toAmount: '20',
      hashes: ['trx-submitted-hash'],
      transactionIds: {},
      status: 'pendingTrusted',
    });

    const withoutBackendPayoutHash = projectCexSwapActivities(
      [rawPayout],
      [pendingSwap],
      new Set([pendingSwap.id]),
    );

    expect(withoutBackendPayoutHash.projectedSourceActivities[0].id).toBe(rawPayout.id);
    expect(withoutBackendPayoutHash.projectedSourceActivities[0].shouldHide).toBeUndefined();
    expect(withoutBackendPayoutHash.projectedSwapActivities).toEqual([
      expect.objectContaining({ id: pendingSwap.id, status: 'pendingTrusted' }),
    ]);

    const completedSwap = makeCexSwap({
      ...pendingSwap,
      status: 'completed',
      hashes: ['trx-submitted-hash', rawPayout.id],
      transactionIds: {},
    });
    const patch = buildCexSwapRefreshPatch('account-1', [completedSwap], [], [rawPayout, pendingSwap]);

    expect(patch.upsert).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: rawPayout.id, shouldHide: true }),
      expect.objectContaining({ id: completedSwap.id, status: 'completed' }),
    ]));
    expect(patch.upsert.find(({ id }) => id === completedSwap.id)?.extra?.reconciliation)
      .toEqual(expect.objectContaining({ hiddenSourceActionIds: [rawPayout.id] }));
  });

  it('does not hide an unrelated same token/amount/time receive without backend CEX identity', () => {
    const rawReceive = makeTransaction({
      id: 'unrelated-ton-receive',
      slug: 'toncoin',
      isIncoming: true,
      amount: 20n,
      timestamp: BASE_TIMESTAMP,
      toAddress: 'payout-address',
      normalizedAddress: 'payout-address',
    });
    const pendingSwap = makeCexSwap({
      from: 'trx',
      to: 'toncoin',
      toAmount: '20',
      timestamp: BASE_TIMESTAMP,
      hashes: [],
      transactionIds: {},
      status: 'pendingTrusted',
    });

    const result = projectCexSwapActivities([rawReceive], [pendingSwap], new Set([pendingSwap.id]));

    expect(result.projectedSourceActivities[0].shouldHide).toBeUndefined();
    expect(result.projectedSwapActivities).toEqual([expect.objectContaining({ id: pendingSwap.id })]);
  });

  it('normalizes projected backend swap ids when storing operation intents', () => {
    const intent = buildCexSwapOperationIntent('account-1', makeCexSwap({ id: 'active::backend-swap' }));

    expect(intent.operationId).toBe('swap:active');
    expect(intent.swap?.backendSwapId).toBe('active');
  });
});
