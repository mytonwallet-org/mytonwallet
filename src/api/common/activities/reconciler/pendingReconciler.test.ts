import type { ApiSwapActivity, ApiTransactionActivity } from '../../../types';

import { reconcileNewActivitiesUpdate, reconcilePendingActivities } from './pendingReconciler';

const BASE_TIMESTAMP = 1_700_000_000_000;

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'swap-local::local',
    timestamp: BASE_TIMESTAMP,
    from: 'toncoin',
    fromAmount: '5',
    fromAddress: 'from-address',
    to: 'ton-token',
    toAmount: '10',
    networkFee: '0',
    swapFee: '0',
    ourFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    transactionIds: {},
    ...overrides,
  };
}

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

describe('pending reconciler', () => {
  it('replaces a sub-indexed local Solana transfer by its submitted transaction signature', () => {
    const signature = 'solana-signature';
    const localActivity = makeTransaction({
      id: `${signature}:0:local`,
      status: 'pendingTrusted',
    });
    const confirmedActivity = makeTransaction({
      id: signature,
      externalMsgHashNorm: signature,
      status: 'completed',
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localActivity], [confirmedActivity], undefined);

    expect(result.patch.replacedIds).toEqual({ [localActivity.id]: confirmedActivity.id });
    expect(result.patch.removeIds).toEqual([localActivity.id]);
  });

  it('maps local pendingTrusted activity to chain pending by SDK operationId and preserves trust', () => {
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
    const chainPending = makeTransaction({
      id: 'chain-pending',
      status: 'pending',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['chain-pending'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });

    const result = reconcilePendingActivities([localActivity], [chainPending]);

    expect(result.replacedIds).toEqual({ [localActivity.id]: chainPending.id });
    expect(result.pendingActivities[0].status).toBe('pendingTrusted');
  });

  it('does not regress a completed activity to pending when a late pending update arrives', () => {
    const completed = makeTransaction({ id: 'same-id', status: 'completed' });
    const latePending = makeTransaction({ id: 'same-id', status: 'pending' });

    const result = reconcilePendingActivities([completed], [latePending]);

    expect(result.replacedIds).toEqual({ 'same-id': 'same-id' });
    expect(result.pendingActivities[0].status).toBe('completed');
  });

  it('does not remove activities for self-replacements in SDK patches', () => {
    const completed = makeTransaction({ id: 'same-id', status: 'completed' });
    const latePending = makeTransaction({ id: 'same-id', status: 'pending' });

    const result = reconcileNewActivitiesUpdate('account-1', [completed], [], [latePending]);

    expect(result.patch.replacedIds).toEqual({ 'same-id': 'same-id' });
    expect(result.patch.removeIds).toEqual([]);
    expect(result.patch.upsert).toEqual([expect.objectContaining({ id: 'same-id', status: 'completed' })]);
  });

  it('builds an SDK patch for a new-activities update with adjusted pending status and replacements', () => {
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
    const chainPending = makeTransaction({
      id: 'chain-pending',
      status: 'pending',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['chain-pending'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });
    const confirmed = makeTransaction({ id: 'confirmed', status: 'completed' });

    const result = reconcileNewActivitiesUpdate('account-1', [localActivity], [confirmed], [chainPending]);

    expect(result.pendingActivities?.[0].status).toBe('pendingTrusted');
    expect(result.patch).toEqual(expect.objectContaining({
      accountId: 'account-1',
      removeIds: [localActivity.id],
      replacedIds: { [localActivity.id]: chainPending.id },
      upsert: [expect.objectContaining({ id: chainPending.id, status: 'pendingTrusted' }), confirmed],
    }));
  });

  it('does not synthesize a local suppression projection from raw same-hash split legs', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
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
    const firstLeg = makeSwap({
      id: 'trace:1-first-leg',
      status: 'confirmed',
      fromAmount: '117540',
      toAmount: '2.196326248',
      externalMsgHashNorm,
    });
    const secondLeg = makeSwap({
      id: 'trace:2-second-leg',
      status: 'confirmed',
      fromAmount: '182460',
      toAmount: '3.407652879',
      externalMsgHashNorm,
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localSwap], [], [firstLeg, secondLeg]);

    expect(result.patch.removeIds).toEqual([]);
    expect(result.patch.replacedIds).toEqual({});
    expect(result.patch.upsert).toEqual([firstLeg, secondLeg]);
  });

  it('replaces a local pendingTrusted swap with the canonical pending aggregate without regressing trust', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
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
      id: 'trace:aggregate',
      status: 'pending',
      externalMsgHashNorm,
      extra: {
        reconciliation: {
          sourceActionIds: ['trace:aggregate', 'trace:hidden'],
          hiddenSourceActionIds: ['trace:hidden'],
          reason: 'ton-aggregated-swap',
        },
      },
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localSwap], [], [aggregate]);

    expect(result.patch.removeIds).toEqual([localSwap.id]);
    expect(result.patch.replacedIds).toEqual({ [localSwap.id]: aggregate.id });
    expect(result.patch.upsert).toEqual([
      expect.objectContaining({ id: aggregate.id, status: 'pendingTrusted' }),
    ]);
    expect(result.patch.upsert[0].shouldHide).not.toBe(true);
  });

  it('keeps ambiguous settled same-hash swap actions visible instead of hiding them behind the local intent', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
      fromAmount: '6',
      toAmount: '317988.3910251973',
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
    const completedAggregate = makeSwap({
      id: 'trace:completed-aggregate',
      status: 'completed',
      fromAmount: '6',
      toAmount: '317988.3910251972',
      externalMsgHashNorm,
    });
    const splitLeg = makeSwap({
      id: 'trace:split-leg',
      status: 'completed',
      fromAmount: '3.65214',
      toAmount: '193518.4923864239',
      externalMsgHashNorm,
    });

    const result = reconcileNewActivitiesUpdate(
      'account-1',
      [localSwap],
      [completedAggregate, splitLeg],
      undefined,
    );

    expect(result.patch.removeIds).toEqual([]);
    expect(result.patch.upsert).toEqual([completedAggregate, splitLeg]);
    expect(result.patch.replacedIds).toEqual({});
  });

  it('does not synthesize lifecycle ownership from mixed raw same-hash legs', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
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
    const completedLeg = makeSwap({
      id: 'trace:completed-leg',
      status: 'completed',
      externalMsgHashNorm,
    });
    const pendingLeg = makeSwap({
      id: 'trace:pending-leg',
      status: 'pending',
      externalMsgHashNorm,
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localSwap], [completedLeg], [pendingLeg]);

    expect(result.patch.removeIds).toEqual([]);
    expect(result.patch.replacedIds).toEqual({});
    expect(result.patch.upsert).toEqual([pendingLeg, completedLeg]);
  });

  it('does not hide failed submitted-hash raw rows behind a local TON swap', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
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
      id: 'trace:failed-raw',
      status: 'failed',
      externalMsgHashNorm,
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localSwap], [], [failedRaw]);

    expect(result.patch.upsert).toEqual([failedRaw]);
    expect(result.patch.removeIds).toEqual([localSwap.id]);
    expect(result.patch.replacedIds).toEqual({});
  });

  it('does not hide bounced submitted-hash raw rows behind a local TON swap', () => {
    const externalMsgHashNorm = 'external-message-hash';
    const localSwap = makeSwap({
      id: 'swap-id::local',
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
    const bouncedRaw = makeTransaction({
      id: 'trace:bounced-raw',
      status: 'completed',
      type: 'bounced',
      externalMsgHashNorm,
    });

    const result = reconcileNewActivitiesUpdate('account-1', [localSwap], [], [bouncedRaw]);

    expect(result.patch.upsert).toEqual([bouncedRaw]);
    expect(result.patch.removeIds).toEqual([localSwap.id]);
    expect(result.patch.replacedIds).toEqual({});
  });

  it('reconciles socket pending to confirmed activity without duplicates or status regression', () => {
    const pending = makeTransaction({
      id: 'pending-id',
      status: 'pendingTrusted',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['pending-id'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });
    const confirmed = makeTransaction({
      id: 'confirmed-id',
      status: 'completed',
      extra: {
        reconciliation: {
          operationId: 'op-1',
          sourceActionIds: ['confirmed-id'],
          hiddenSourceActionIds: [],
          reason: 'raw',
        },
      },
    });

    const result = reconcileNewActivitiesUpdate('account-1', [pending], [confirmed], undefined);

    expect(result.patch.removeIds).toEqual([pending.id]);
    expect(result.patch.upsert).toEqual([
      {
        ...confirmed,
        extra: {
          reconciliation: {
            operationId: 'op-1',
            sourceActionIds: ['pending-id', 'confirmed-id'],
            hiddenSourceActionIds: [],
            reason: 'raw',
          },
        },
      },
    ]);
    expect(result.patch.replacedIds).toEqual({ [pending.id]: confirmed.id });
  });
});
