import type { ApiSwapActivity, ApiTransactionActivity } from '../../../types';
import type { WalletOperationIntent } from './types';

import { buildBackendSwapId } from '../../../../util/activities';
import {
  getActivityIdReplacementsFromSdkMatcher,
  getActivityMatchKeys,
  preserveActivityStatusProgress,
} from './matcher';

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
    status: 'pending',
    ...overrides,
  };
}

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'swap-id::backend-swap',
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

describe('activity reconciler matcher', () => {
  it('adds CEX swap hashes as both chain-hash and TON external-message match keys', () => {
    const keys = getActivityMatchKeys(makeSwap({ hashes: ['backend-known-hash'] }));

    expect(keys).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'txHash', value: 'backend-known-hash', priority: 4 }),
      expect.objectContaining({ type: 'externalMsgHashNorm', value: 'backend-known-hash', priority: 5 }),
    ]));
  });

  it('does not treat buildBackendSwapId ids as chain transaction or submitted hashes', () => {
    const activity = makeSwap({ id: buildBackendSwapId('backend-swap-id'), hashes: [] });
    const keys = getActivityMatchKeys(activity);

    expect(keys).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'backendSwapId', value: 'backend-swap-id', priority: 2 }),
      expect.objectContaining({ type: 'activityId', value: 'backend-swap-id::backend-swap', priority: 3 }),
    ]));
    expect(keys).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'txHash', value: 'backend-swap-id' }),
      expect.objectContaining({ type: 'submittedHash', value: 'backend-swap-id' }),
    ]));
  });

  // A trace action carries what the wallet submitted, so an intent lends it every hash of that submission. The trace id
  // it happens to sit under stays out: it names a whole trace, and a projector must not read it as this action's own.
  it('lends intent submitted hashes to a trace action without claiming its trace id', () => {
    const action = makeTransaction({ id: 'trace-hash:1-action', externalMsgHashNorm: 'normalized-hash' });
    const intent: WalletOperationIntent = {
      operationId: 'swap:backend-swap-id',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP - 1_000,
      status: 'pending',
      swap: {
        type: 'dex',
        backendSwapId: 'backend-swap-id',
        submittedHashes: ['signed-message-hash', 'normalized-hash'],
      },
    };

    const keys = getActivityMatchKeys(action, [intent]);

    expect(keys).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'submittedHash', value: 'signed-message-hash' }),
      expect.objectContaining({ type: 'backendSwapId', value: 'backend-swap-id' }),
    ]));
    expect(keys).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'txHash', value: 'trace-hash' }),
    ]));
  });

  it('matches changed TON activity ids by externalMsgHashNorm', () => {
    const prev = makeTransaction({ id: 'old-trace:1-action', externalMsgHashNorm: 'external-hash' });
    const next = makeTransaction({ id: 'new-trace:1-action', externalMsgHashNorm: 'external-hash' });

    expect(getActivityIdReplacementsFromSdkMatcher([prev], [next])).toEqual({
      [prev.id]: next.id,
    });
  });

  it('matches local TON DEX swap to visible swap when hidden support shares submitted hash', () => {
    const submittedHash = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'local-swap::local',
      externalMsgHashNorm: submittedHash,
      status: 'pendingTrusted',
    });
    const hiddenFee = makeTransaction({
      id: 'trace-id:1-fee',
      externalMsgHashNorm: submittedHash,
      shouldHide: true,
      status: 'completed',
    });
    const confirmedSwap = makeSwap({
      id: 'trace-id:2-swap',
      externalMsgHashNorm: submittedHash,
      status: 'completed',
      fromAmount: localSwap.fromAmount,
      toAmount: localSwap.toAmount,
    });

    expect(getActivityIdReplacementsFromSdkMatcher([localSwap], [hiddenFee, confirmedSwap])).toEqual({
      [localSwap.id]: confirmedSwap.id,
    });
  });

  it('does not pick a visible submitted-hash replacement when multiple visible candidates match', () => {
    const submittedHash = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'local-swap::local',
      externalMsgHashNorm: submittedHash,
      status: 'pendingTrusted',
    });
    const firstConfirmedSwap = makeSwap({
      id: 'trace-id:1-swap',
      externalMsgHashNorm: submittedHash,
      status: 'completed',
    });
    const secondConfirmedSwap = makeSwap({
      id: 'trace-id:2-swap',
      externalMsgHashNorm: submittedHash,
      status: 'completed',
    });

    expect(getActivityIdReplacementsFromSdkMatcher(
      [localSwap],
      [firstConfirmedSwap, secondConfirmedSwap],
    )).toEqual({});
  });

  it('uses reconciliation operationId before ambiguous hash candidates', () => {
    const prev = makeSwap({
      id: 'local-op::local',
      hashes: ['shared-hash'],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['local-op::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const wrongNext = makeSwap({ id: 'wrong::backend-swap', hashes: ['shared-hash'] });
    const rightNext = makeSwap({
      id: 'right::backend-swap',
      hashes: ['shared-hash'],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['right::backend-swap'],
          hiddenSourceActionIds: [],
          reason: 'cex-swap',
        },
      },
    });

    expect(getActivityIdReplacementsFromSdkMatcher([prev], [wrongNext, rightNext])).toEqual({
      [prev.id]: rightNext.id,
    });
  });

  it('normalizes submitted-hash intent relation before adding intent-derived keys to activities', () => {
    const activity = makeTransaction({
      id: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      status: 'completed',
    });
    const intent: WalletOperationIntent = {
      operationId: 'op-cex',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP - 1_000,
      status: 'pendingTrusted',
      swap: {
        type: 'cex',
        submittedHashes: ['0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD'],
      },
    };

    expect(getActivityMatchKeys(activity, [intent])).toEqual(expect.arrayContaining([
      expect.objectContaining({ type: 'operationId', value: 'op-cex' }),
      expect.objectContaining({
        type: 'submittedHash',
        value: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      }),
    ]));
  });

  it('does not mistake a CEX source transaction for a canonical swap replacement', () => {
    const prev = makeSwap({
      id: 'backend-swap-id::backend-swap',
      cex: {
        payinAddress: 'payin-address',
        payoutAddress: 'payout-address',
        status: 'waiting',
        transactionId: 'cex-transaction-id',
      },
    });
    const next = makeTransaction({ id: 'submitted-chain-hash', status: 'completed' });
    const intent: WalletOperationIntent = {
      operationId: 'op-cex',
      accountId: 'account-1',
      kind: 'swap',
      createdAt: BASE_TIMESTAMP - 1_000,
      status: 'pendingTrusted',
      swap: {
        type: 'cex',
        backendSwapId: 'backend-swap-id',
        cexTransactionId: 'cex-transaction-id',
        submittedHashes: ['submitted-chain-hash'],
      },
    };

    expect(getActivityIdReplacementsFromSdkMatcher([prev], [next], { previousIntents: [intent] })).toEqual({});
  });

  it('does not replace one TON trace action with another only because the trace hash matches', () => {
    const previous = makeTransaction({ id: 'shared-trace:1-action' });
    const incoming = makeTransaction({ id: 'shared-trace:2-action', status: 'completed' });

    expect(getActivityIdReplacementsFromSdkMatcher([previous], [incoming])).toEqual({});
  });

  it('does not infer W5 gasless transaction identity from recipient and amount', () => {
    const local = makeTransaction({
      id: 'local-transaction::local',
      extra: { withW5Gasless: true },
    });
    const previousIdenticalTransfer = makeTransaction({
      id: 'previous-chain-transaction',
      status: 'completed',
    });

    expect(getActivityIdReplacementsFromSdkMatcher([local], [previousIdenticalTransfer])).toEqual({});
  });

  it('does not infer local swap identity from pair and amount without an explicit identifier', () => {
    const local = makeSwap({
      id: 'local-swap::local',
      extra: {
        reconciliation: {
          operationId: 'swap:local',
          sourceActionIds: ['local-swap::local'],
          hiddenSourceActionIds: [],
          reason: 'local-intent',
        },
      },
    });
    const chainPending = makeSwap({ id: 'chain-pending', status: 'pending' });

    expect(getActivityIdReplacementsFromSdkMatcher([local], [chainPending])).toEqual({});
  });

  it('prevents status regressions from late pending updates', () => {
    const completed = makeTransaction({ id: 'same-id', status: 'completed' });
    const latePending = makeTransaction({ id: 'same-id', status: 'pending' });

    expect(preserveActivityStatusProgress(completed, latePending).status).toBe('completed');
  });

  it('merges reconciliation source metadata across paged updates for the same activity', () => {
    const existing = makeSwap({
      id: 'swap-id::backend-swap',
      status: 'completed',
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::backend-swap', 'payin-id'],
          hiddenSourceActionIds: ['payin-id'],
          reason: 'cex-swap',
        },
      },
    });
    const incoming = makeSwap({
      id: 'swap-id::backend-swap',
      status: 'completed',
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::backend-swap', 'payout-id'],
          hiddenSourceActionIds: ['payout-id'],
          reason: 'cex-swap',
        },
      },
    });

    expect(preserveActivityStatusProgress(existing, incoming).extra?.reconciliation).toEqual({
      operationId: 'swap:swap-id',
      sourceActionIds: ['swap-id::backend-swap', 'payin-id', 'payout-id'],
      hiddenSourceActionIds: ['payin-id', 'payout-id'],
      reason: 'cex-swap',
    });
  });
});
