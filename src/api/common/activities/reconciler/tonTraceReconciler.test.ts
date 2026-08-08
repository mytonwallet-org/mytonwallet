import type { ApiSwapActivity, ApiTransactionActivity } from '../../../types';

import { DIESEL_ADDRESS, MW_AGGREGATOR_QUERY_ID, SWAP_FEE_ADDRESS, TON_USDT_MAINNET } from '../../../../config';
import { projectTonAggregatorActivities } from './tonTraceReconciler';

const BASE_TIMESTAMP = 1_700_000_000_000;
const TRACE_ID = 'trace-hash';

function makeSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: `${TRACE_ID}:0`,
    timestamp: BASE_TIMESTAMP,
    from: 'toncoin',
    fromAmount: '10',
    fromAddress: 'from-address',
    to: 'ton-usdt',
    toAmount: '20',
    networkFee: '0.1',
    swapFee: '0.2',
    ourFee: '0.01',
    status: 'completed',
    hashes: ['hash-0'],
    transactionIds: {},
    ...overrides,
  };
}

function visibleSwaps(activities: readonly (ApiSwapActivity | ApiTransactionActivity)[]) {
  return activities.filter((activity): activity is ApiSwapActivity => {
    return activity.kind === 'swap' && activity.shouldHide !== true;
  });
}

function makeMarkerTransaction(overrides: Partial<ApiTransactionActivity> = {}): ApiTransactionActivity {
  return {
    kind: 'transaction',
    id: `${TRACE_ID}:fee`,
    timestamp: BASE_TIMESTAMP,
    amount: -1n,
    fromAddress: 'from-address',
    toAddress: 'fee-address',
    fee: 0n,
    slug: 'toncoin',
    isIncoming: false,
    normalizedAddress: 'fee-address',
    status: 'completed',
    shouldHide: true,
    extra: { queryId: MW_AGGREGATOR_QUERY_ID },
    ...overrides,
  };
}

describe('TON trace reconciler', () => {
  it('keeps a simple one-leg TON DEX swap raw instead of inventing an aggregate', () => {
    const swap = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });

    const result = projectTonAggregatorActivities([swap, makeMarkerTransaction()]);

    expect(result.activities.filter((activity) => activity.kind === 'swap')).toEqual([swap]);
    expect(result.newlyKnownAggregatorTraceIds).toEqual([]);
  });

  // A trade the venue settles itself locks funds in a contract and is delivered later, outside this trace, so the
  // trace holds our fee and plain transfers and no exchange action at all. Reading it as a swap would either invent a
  // route or call the trade a failure; both are wrong, and the backend row is what represents such a trade.
  it('reads no swap out of a trace that only locks funds in a contract', () => {
    const deposit = makeMarkerTransaction({
      id: `${TRACE_ID}:deposit`,
      amount: -10_000_000n,
      toAddress: 'escrow-address',
      normalizedAddress: 'escrow-address',
      shouldHide: undefined,
      extra: undefined,
    });
    const excess = makeMarkerTransaction({
      id: `${TRACE_ID}:excess`,
      amount: 2_000_000n,
      isIncoming: true,
      fromAddress: 'escrow-address',
      toAddress: 'from-address',
      normalizedAddress: 'escrow-address',
      shouldHide: undefined,
      extra: undefined,
    });
    const fee = makeMarkerTransaction({ toAddress: SWAP_FEE_ADDRESS, extra: { isOurSwapFee: true } });

    const result = projectTonAggregatorActivities([deposit, excess, fee]);

    expect(result.activities.filter((activity) => activity.kind === 'swap')).toEqual([]);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([]);
    expect(result.deaggregatedTraceIds).toEqual([]);
  });

  it.each([
    ['toncoin', '0.99', -10_000_000n, '1', 'ton-usdt'],
    [TON_USDT_MAINNET.slug, '99', -1_000_000n, '100', 'toncoin'],
  ])('includes the parsed %s fee in the aggregate source amount', (
    from,
    fromAmount,
    feeAmount,
    expectedFromAmount,
    to,
  ) => {
    const swap = makeSwap({ from, fromAmount, to });
    const fee = makeMarkerTransaction({
      amount: feeAmount,
      slug: from,
      toAddress: SWAP_FEE_ADDRESS,
      extra: { isOurSwapFee: true },
    });

    const result = projectTonAggregatorActivities([swap, fee]);
    expect(visibleSwaps(result.activities)[0]).toMatchObject({ from, fromAmount: expectedFromAmount, to });
  });

  it('includes the combined fee and diesel transfer in the aggregate source amount', () => {
    const swap = makeSwap({ from: TON_USDT_MAINNET.slug, fromAmount: '99', to: 'toncoin' });
    const feeAndDiesel = makeMarkerTransaction({
      amount: -2_000_000n,
      slug: TON_USDT_MAINNET.slug,
      toAddress: DIESEL_ADDRESS,
      extra: { isOurSwapFee: true },
    });
    const result = projectTonAggregatorActivities([swap, feeAndDiesel]);

    expect(visibleSwaps(result.activities)[0]).toMatchObject({
      from: TON_USDT_MAINNET.slug,
      fromAmount: '101',
      to: 'toncoin',
    });
  });

  it('keeps an explicitly incomplete page-boundary trace raw even when its visible subset looks clean', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });
    const marker = makeMarkerTransaction();

    const result = projectTonAggregatorActivities(
      [first, second, marker],
      [],
      { incompleteTraceIds: [TRACE_ID] },
    );

    expect(result.activities).toEqual([first, second, marker]);
    expect(result.newlyKnownAggregatorTraceIds).toEqual([]);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([]);
  });

  it('aggregates a completed TON aggregator split into one swap activity', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5', hashes: ['hash-0'] });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10', hashes: ['hash-1'] });
    const hiddenSupport = makeMarkerTransaction({ id: `${TRACE_ID}:hidden-support`, extra: undefined });

    const result = projectTonAggregatorActivities([first, second, makeMarkerTransaction(), hiddenSupport]);

    const swaps = visibleSwaps(result.activities);
    expect(swaps).toHaveLength(1);
    expect(swaps[0]).toEqual(expect.objectContaining({
      id: first.id,
      from: 'toncoin',
      fromAmount: '30',
      to: 'ton-usdt',
      toAmount: '15',
      networkFee: '0.2',
      swapFee: '0.4',
      ourFee: '0.02',
      hashes: ['hash-0', 'hash-1'],
      transactionIds: {},
      extra: expect.objectContaining({
        mtwAggregator: expect.objectContaining({ traceId: TRACE_ID, swapIds: [first.id, second.id] }),
        reconciliation: expect.objectContaining({
          sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`, hiddenSupport.id],
          hiddenSourceActionIds: [second.id, `${TRACE_ID}:fee`, hiddenSupport.id],
          reason: 'ton-aggregated-swap',
        }),
      }),
    }));
    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({
        id: second.id,
        shouldHide: true,
      }),
      expect.objectContaining({
        id: `${TRACE_ID}:fee`,
        shouldHide: true,
      }),
      expect.objectContaining({
        id: hiddenSupport.id,
        shouldHide: true,
      }),
    ]));
    expect(result.newlyKnownAggregatorTraceIds).toEqual([TRACE_ID]);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([
      expect.objectContaining({
        traceId: TRACE_ID,
        sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`, hiddenSupport.id],
        hiddenSourceActionIds: [second.id, `${TRACE_ID}:fee`, hiddenSupport.id],
        aggregatedActivity: expect.objectContaining({ id: first.id, fromAmount: '30', toAmount: '15' }),
      }),
    ]);
  });

  it('aggregates confirmed socket split legs into one confirmed swap and hides represented sources', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`,
      fromAmount: '10',
      toAmount: '5',
      status: 'confirmed',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`,
      fromAmount: '20',
      toAmount: '10',
      status: 'confirmed',
    });
    const marker = makeMarkerTransaction({ status: 'confirmed' });

    const result = projectTonAggregatorActivities([first, second, marker]);

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        status: 'confirmed',
        fromAmount: '30',
        toAmount: '15',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, marker.id],
            hiddenSourceActionIds: [second.id, marker.id],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]);
    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: second.id, status: 'confirmed', shouldHide: true }),
      expect.objectContaining({ id: marker.id, status: 'confirmed', shouldHide: true }),
    ]));
  });

  it('keeps one canonical id and source set through pending, confirmed, and completed snapshots', () => {
    function makeSnapshot(status: 'pending' | 'confirmed' | 'completed') {
      return [
        makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10', status }),
        makeMarkerTransaction({ status }),
        makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5', status }),
      ];
    }

    const pending = projectTonAggregatorActivities(makeSnapshot('pending'), [], { isLiveUpdate: true });
    const confirmed = projectTonAggregatorActivities(
      makeSnapshot('confirmed'),
      pending.knownAggregatorTraceProjections,
      { isLiveUpdate: true },
    );
    const completed = projectTonAggregatorActivities(
      makeSnapshot('completed'),
      confirmed.knownAggregatorTraceProjections,
      { isLiveUpdate: true },
    );

    const lifecycle = [pending, confirmed, completed].map((result) => visibleSwaps(result.activities)[0]);
    expect(lifecycle.map(({ id }) => id)).toEqual([
      `${TRACE_ID}:0`,
      `${TRACE_ID}:0`,
      `${TRACE_ID}:0`,
    ]);
    expect(lifecycle.map(({ status }) => status)).toEqual(['pending', 'confirmed', 'completed']);
    expect(lifecycle.map((activity) => activity.extra?.reconciliation?.sourceActionIds)).toEqual([
      [`${TRACE_ID}:0`, `${TRACE_ID}:1`, `${TRACE_ID}:fee`],
      [`${TRACE_ID}:0`, `${TRACE_ID}:1`, `${TRACE_ID}:fee`],
      [`${TRACE_ID}:0`, `${TRACE_ID}:1`, `${TRACE_ID}:fee`],
    ]);
    for (const result of [pending, confirmed, completed]) {
      expect(result.activities.filter(({ shouldHide }) => shouldHide === true)).toHaveLength(2);
    }
  });

  it('uses the least-progressed non-failed action status for an aggregate', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, status: 'completed', fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, status: 'pendingTrusted', fromAmount: '20', toAmount: '10' });
    const marker = makeMarkerTransaction({ status: 'confirmed' });

    const result = projectTonAggregatorActivities([first, second, marker]);

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({ id: first.id, status: 'pendingTrusted' }),
    ]);
  });

  it('persists same-status aggregate detail changes for later partial slices', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`,
      status: 'confirmed',
      fromAmount: '10',
      toAmount: '5',
      networkFee: '1',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`,
      status: 'confirmed',
      fromAmount: '20',
      toAmount: '10',
      networkFee: '2',
    });
    const marker = makeMarkerTransaction({ status: 'confirmed' });
    const initial = projectTonAggregatorActivities([first, second, marker]);

    const updated = projectTonAggregatorActivities(
      [{ ...first, networkFee: '4' }, second, marker],
      initial.knownAggregatorTraceProjections,
    );

    expect(updated.newlyKnownAggregatorTraceProjections).toEqual([
      expect.objectContaining({
        aggregatedActivity: expect.objectContaining({
          id: first.id,
          status: 'confirmed',
          networkFee: '6',
        }),
      }),
    ]);
  });

  it('deaggregates a previously projected trace when a source action fails', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, status: 'pending', fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, status: 'pending', fromAmount: '20', toAmount: '10' });
    const marker = makeMarkerTransaction({ status: 'pending' });
    const pending = projectTonAggregatorActivities([first, second, marker], [], { isLiveUpdate: true });

    const failed = projectTonAggregatorActivities(
      [
        { ...first, status: 'completed' },
        { ...second, status: 'failed' },
        { ...marker, status: 'completed' },
      ],
      pending.knownAggregatorTraceProjections,
      { isLiveUpdate: true },
    );

    expect(visibleSwaps(failed.activities).map(({ id }) => id).sort()).toEqual([first.id, second.id].sort());
    expect(failed.activities.every((activity) => {
      return activity.shouldHide === undefined && activity.extra?.reconciliation === undefined;
    })).toBe(true);
    expect(failed.deaggregatedTraceIds).toEqual([TRACE_ID]);
    expect(failed.newlyKnownAggregatorTraceProjections).toEqual([
      expect.objectContaining({
        traceId: TRACE_ID,
        sourceActionIds: [first.id, second.id, marker.id],
        hiddenSourceActionIds: [],
        isTerminalFailure: true,
      }),
    ]);
  });

  it('owns successful trace support actions regardless of their previous presentation visibility', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });
    const unrelatedVisible = makeMarkerTransaction({
      id: `${TRACE_ID}:visible-transfer`,
      shouldHide: false,
      extra: undefined,
    });

    const result = projectTonAggregatorActivities([first, second, makeMarkerTransaction(), unrelatedVisible]);

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({ id: first.id, fromAmount: '30', toAmount: '15' }),
    ]);
    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: unrelatedVisible.id, shouldHide: true }),
    ]));
    expect(result.newlyKnownAggregatorTraceIds).toEqual([TRACE_ID]);
  });

  it('keeps a first-observed failed trace raw and marks it terminal', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });
    const failedSupport = makeMarkerTransaction({ id: `${TRACE_ID}:failed-fee`, status: 'failed' });

    const result = projectTonAggregatorActivities([first, second, failedSupport]);

    expect(result.activities.map(({ id }) => id).sort()).toEqual(
      [first.id, second.id, failedSupport.id].sort(),
    );
    expect(result.activities.every(({ shouldHide }) => shouldHide === undefined)).toBe(true);
    expect(result.newlyKnownAggregatorTraceIds).toEqual([TRACE_ID]);
    expect(result.deaggregatedTraceIds).toEqual([TRACE_ID]);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([
      expect.objectContaining({
        traceId: TRACE_ID,
        sourceActionIds: [first.id, second.id, failedSupport.id],
        hiddenSourceActionIds: [],
        isTerminalFailure: true,
      }),
    ]);
  });

  it('aggregates a completed split and hop only when intermediates net to zero', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });

    const result = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);

    const swap = visibleSwaps(result.activities)[0];
    expect(swap.from).toBe('toncoin');
    expect(swap.fromAmount).toBe('10');
    expect(swap.to).toBe('ton-usdt');
    expect(swap.toAmount).toBe('2');
  });

  it('keeps raw swap legs visible on partial failure where an intermediate token remains', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '3', toAmount: '2',
    });

    const result = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);

    expect(result.activities.filter((activity) => activity.kind === 'swap').map(({ id }) => id).sort()).toEqual(
      [first.id, second.id].sort(),
    );
    expect(result.deaggregatedTraceIds).toEqual([TRACE_ID]);
  });

  it('keeps raw swap legs visible when any leg has failed', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10', status: 'failed' });

    const result = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);

    expect(result.activities.filter((activity) => activity.kind === 'swap').map(({ id }) => id).sort()).toEqual(
      [first.id, second.id].sort(),
    );
    expect(result.activities.every(({ shouldHide }) => shouldHide === undefined)).toBe(true);
  });

  it('aggregates a full trace while a support action is still pending', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });
    const pendingSupport = makeMarkerTransaction({ id: `${TRACE_ID}:pending-fee`, status: 'pending' });

    const result = projectTonAggregatorActivities([first, second, pendingSupport]);

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        status: 'pending',
        fromAmount: '30',
        toAmount: '15',
      }),
    ]);
    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: second.id, shouldHide: true }),
      expect.objectContaining({ id: pendingSupport.id, shouldHide: true }),
    ]));
  });

  it('uses durable known trace ids to aggregate slices that miss the marker but still prove a clean route', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });

    const result = projectTonAggregatorActivities([first, second], [TRACE_ID]);

    expect(visibleSwaps(result.activities)).toHaveLength(1);
    expect(result.newlyKnownAggregatorTraceIds).toEqual([]);
  });

  it('makes the same aggregate decision for a full main-feed trace and a known token-feed slice', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });

    const mainFeedResult = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const tokenFeedResult = projectTonAggregatorActivities([first, second], mainFeedResult.knownAggregatorTraceIds);

    const mainFeedSwap = visibleSwaps(mainFeedResult.activities)[0];
    const tokenFeedSwap = visibleSwaps(tokenFeedResult.activities)[0];

    expect(tokenFeedSwap).toEqual(expect.objectContaining({
      from: mainFeedSwap.from,
      fromAmount: mainFeedSwap.fromAmount,
      to: mainFeedSwap.to,
      toAmount: mainFeedSwap.toAmount,
    }));
  });

  it('reuses a durable known aggregate projection for a token-feed slice with only one source/output leg', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });

    const mainFeedResult = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const tokenFeedResult = projectTonAggregatorActivities([first], mainFeedResult.knownAggregatorTraceProjections);

    expect(tokenFeedResult.activities).toEqual([
      expect.objectContaining({
        id: first.id,
        from: 'toncoin',
        fromAmount: '10',
        to: 'ton-usdt',
        toAmount: '2',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`],
            hiddenSourceActionIds: [second.id, `${TRACE_ID}:fee`],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]);
  });

  it('does not replace a durable projection with a clean strict subset of a split trace', () => {
    const swaps = [
      makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' }),
      makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' }),
      makeSwap({ id: `${TRACE_ID}:2`, fromAmount: '30', toAmount: '15' }),
      makeSwap({ id: `${TRACE_ID}:3`, fromAmount: '40', toAmount: '20' }),
    ];
    const fullProjection = projectTonAggregatorActivities([...swaps, makeMarkerTransaction()]);

    const partialProjection = projectTonAggregatorActivities(
      swaps.slice(0, 2),
      fullProjection.knownAggregatorTraceProjections,
    );

    expect(visibleSwaps(partialProjection.activities)).toEqual([
      expect.objectContaining({
        id: swaps[0].id,
        fromAmount: '100',
        toAmount: '50',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [...swaps.map(({ id }) => id), `${TRACE_ID}:fee`],
          }),
        }),
      }),
    ]);
    expect(partialProjection.newlyKnownAggregatorTraceProjections).toEqual([]);
  });

  it('reuses the durable canonical row when a partial slice lists a hidden leg before the primary', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10' });
    const fullProjection = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);

    const partialProjection = projectTonAggregatorActivities(
      [second, first],
      fullProjection.knownAggregatorTraceProjections,
    );

    expect(partialProjection.activities.filter(({ id }) => id === first.id)).toEqual([
      expect.objectContaining({
        id: first.id,
        shouldHide: undefined,
        fromAmount: '30',
        toAmount: '15',
      }),
    ]);
    expect(partialProjection.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: second.id, shouldHide: true }),
    ]));
  });

  it('returns a self-contained aggregate and hidden patch for a known non-primary token slice', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-usdt', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'toncoin', to: 'ton-usdt', fromAmount: '20', toAmount: '10',
    });
    const mainFeedResult = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const lateConfirmedSecond = { ...second, status: 'confirmed' as const };

    const result = projectTonAggregatorActivities(
      [lateConfirmedSecond],
      mainFeedResult.knownAggregatorTraceProjections,
    );

    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({
        id: first.id,
        status: 'completed',
        fromAmount: '30',
        toAmount: '15',
      }),
      expect.objectContaining({
        id: second.id,
        shouldHide: true,
        status: 'confirmed',
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`],
            hiddenSourceActionIds: [second.id, `${TRACE_ID}:fee`],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]));
    expect(result.activities).toHaveLength(2);
  });

  it('keeps the durable live action set fixed when a later snapshot adds an unknown action', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5', hashes: ['hash-0'] });
    const second = makeSwap({ id: `${TRACE_ID}:1`, fromAmount: '20', toAmount: '10', hashes: ['hash-1'] });
    const firstProjection = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const hiddenSupport = makeMarkerTransaction({ id: `${TRACE_ID}:hidden-support`, extra: undefined });

    const fullerTraceProjection = projectTonAggregatorActivities(
      [first, second, makeMarkerTransaction(), hiddenSupport],
      firstProjection.knownAggregatorTraceProjections,
      { isLiveUpdate: true },
    );

    expect(fullerTraceProjection.activities.some(({ id }) => id === hiddenSupport.id)).toBe(false);
    expect(visibleSwaps(fullerTraceProjection.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`],
            hiddenSourceActionIds: [second.id, `${TRACE_ID}:fee`],
          }),
        }),
      }),
    ]);
    expect(fullerTraceProjection.newlyKnownAggregatorTraceProjections).toEqual([]);
  });

  it('does not deaggregate a durable projection from a partial history failure slice', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });
    const mainFeedResult = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const failedSecond = { ...second, status: 'failed' as const };

    const result = projectTonAggregatorActivities(
      [first, failedSecond],
      mainFeedResult.knownAggregatorTraceProjections,
    );

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        status: 'completed',
        from: 'toncoin',
        to: 'ton-usdt',
      }),
    ]);
    expect(result.activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: second.id, status: 'failed', shouldHide: true }),
    ]));
    expect(result.deaggregatedTraceIds).toEqual([]);
  });

  it('ignores an unknown action in a partial history slice without changing the durable projection', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });
    const fullProjection = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const unexpectedLeg = makeSwap({
      id: `${TRACE_ID}:unexpected`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '1', toAmount: '0.5',
    });

    const result = projectTonAggregatorActivities(
      [first, unexpectedLeg],
      fullProjection.knownAggregatorTraceProjections,
    );

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        from: 'toncoin',
        to: 'ton-usdt',
      }),
    ]);
    expect(result.activities.some(({ id }) => id === unexpectedLeg.id)).toBe(false);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([]);
  });

  it('ignores an unknown action in a known live trace without changing its canonical projection', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });
    const mainFeedResult = projectTonAggregatorActivities([first, second, makeMarkerTransaction()]);
    const unexpectedLeg = makeSwap({
      id: `${TRACE_ID}:unexpected`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '1', toAmount: '0.5',
    });

    const result = projectTonAggregatorActivities(
      [first, second, makeMarkerTransaction(), unexpectedLeg],
      mainFeedResult.knownAggregatorTraceProjections,
      { isLiveUpdate: true },
    );

    expect(visibleSwaps(result.activities)).toEqual([
      expect.objectContaining({
        id: first.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, `${TRACE_ID}:fee`],
          }),
        }),
      }),
    ]);
    expect(result.activities.some(({ id }) => id === unexpectedLeg.id)).toBe(false);
    expect(result.newlyKnownAggregatorTraceProjections).toEqual([]);
  });

  it('does not reuse a durable projection for a support-only slice with no swap leg', () => {
    const first = makeSwap({
      id: `${TRACE_ID}:0`, from: 'toncoin', to: 'ton-token-x', fromAmount: '10', toAmount: '5',
    });
    const second = makeSwap({
      id: `${TRACE_ID}:1`, from: 'ton-token-x', to: 'ton-usdt', fromAmount: '5', toAmount: '2',
    });
    const marker = makeMarkerTransaction();
    const mainFeedResult = projectTonAggregatorActivities([first, second, marker]);

    const result = projectTonAggregatorActivities([marker], mainFeedResult.knownAggregatorTraceProjections);

    expect(result.activities).toEqual([
      expect.objectContaining({
        id: marker.id,
        shouldHide: true,
        extra: expect.objectContaining({
          queryId: MW_AGGREGATOR_QUERY_ID,
          reconciliation: expect.objectContaining({
            sourceActionIds: [first.id, second.id, marker.id],
            hiddenSourceActionIds: [second.id, marker.id],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]);
  });

  it('keeps a one-leg known trace id raw when no durable aggregate projection has been proven yet', () => {
    const first = makeSwap({ id: `${TRACE_ID}:0`, fromAmount: '10', toAmount: '5' });

    const result = projectTonAggregatorActivities([first], [TRACE_ID]);

    expect(result.activities).toEqual([first]);
  });
});
