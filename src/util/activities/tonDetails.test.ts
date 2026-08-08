import type { ApiSwapActivity } from '../../api/types';

import { getTonAggregatedSwapDetailsTraceId } from './tonDetails';

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'trace-id:1-action',
    timestamp: 1_700_000_000_000,
    from: 'toncoin',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'ton-target',
    toAmount: '20',
    networkFee: '0.1',
    swapFee: '0',
    status: 'completed',
    hashes: [],
    transactionIds: {},
    ...overrides,
  };
}

describe('TON aggregated swap details trace id', () => {
  it('uses explicit mtwAggregator trace id for multi-leg swaps', () => {
    const activity = makeSwap({
      id: 'representative-trace:1-action',
      extra: {
        mtwAggregator: {
          traceId: 'explicit-trace-id',
          swapIds: ['representative-trace:1-action', 'representative-trace:2-action'],
          from: 'toncoin',
          to: 'ton-target',
        },
      },
    });

    expect(getTonAggregatedSwapDetailsTraceId(activity)).toBe('explicit-trace-id');
  });

  it('does not expose details for one-leg swaps', () => {
    const activity = makeSwap({
      extra: {
        mtwAggregator: {
          traceId: 'explicit-trace-id',
          swapIds: ['representative-trace:1-action'],
          from: 'toncoin',
          to: 'ton-target',
        },
      },
    });

    expect(getTonAggregatedSwapDetailsTraceId(activity)).toBeUndefined();
  });

  it('uses the unambiguous represented trace for local-intent split representatives', () => {
    const activity = makeSwap({
      id: 'trace-id:3-full',
      extra: {
        reconciliation: {
          sourceActionIds: ['trace-id:3-full', 'trace-id:2-leg', 'trace-id:4-fee'],
          hiddenSourceActionIds: ['trace-id:2-leg', 'trace-id:4-fee'],
          reason: 'local-intent',
        },
      },
    });

    expect(getTonAggregatedSwapDetailsTraceId(activity)).toBe('trace-id');
  });

  it('uses an unambiguous represented raw trace instead of the backend swap id', () => {
    const activity = makeSwap({
      id: 'backend-id::backend-swap',
      extra: {
        reconciliation: {
          sourceActionIds: ['backend-id::backend-swap', 'raw-trace:2-leg'],
          hiddenSourceActionIds: ['raw-trace:2-leg'],
          reason: 'ton-aggregated-swap',
        },
      },
    });

    expect(getTonAggregatedSwapDetailsTraceId(activity)).toBe('raw-trace');
  });

  it('does not expose details for non-aggregated swaps', () => {
    expect(getTonAggregatedSwapDetailsTraceId(makeSwap())).toBeUndefined();
  });

  it('falls back to submitted message hash only when represented trace ids are ambiguous', () => {
    const activity = makeSwap({
      id: 'local-id::local',
      externalMsgHashNorm: 'submitted-message-hash',
      extra: {
        reconciliation: {
          sourceActionIds: ['local-id::local', 'first-trace:1-leg', 'second-trace:2-leg'],
          hiddenSourceActionIds: ['first-trace:1-leg', 'second-trace:2-leg'],
          reason: 'local-intent',
        },
      },
    });

    expect(getTonAggregatedSwapDetailsTraceId(activity)).toBe('submitted-message-hash');
  });
});
