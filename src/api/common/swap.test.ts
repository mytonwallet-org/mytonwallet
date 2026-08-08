import type { ApiSwapActivity, ApiSwapHistoryItem, ApiTransactionActivity } from '../types';
import type { WalletOperationIntent } from './activities/reconciler/types';

import {
  ETH_USDT_MAINNET,
  SOLANA,
  SOLANA_USDC_MAINNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
} from '../../config';
import { getActivityTokenSlugs } from '../../util/activities';
import {
  getBackendDexHistoryFetchFromTime,
  getSwapHistoryTokenFilter,
  getSwapItemSlug,
  projectBackendDexSwapActivities,
  swapItemToActivity,
} from './swap';

const SOLANA_EXAMPLE_MINT = 'AymATz4TCL9sWNEEV9Kvyz45CHVhDZ6kUgjTJPzLpU9P';

const BASE_SWAP: ApiSwapHistoryItem = {
  id: 'cex-backend-id',
  timestamp: 1_700_000_000_000,
  from: TONCOIN.symbol,
  fromAmount: '16.4',
  fromAddress: 'ton-address',
  to: TRC20_USDT_MAINNET.tokenAddress,
  toAmount: '28.854382',
  networkFee: '0.1',
  swapFee: '0',
  status: 'completed',
  hashes: ['payin-hash', 'payout-hash'],
  transactionIds: {},
  cex: {
    payinAddress: 'payin-address',
    payoutAddress: 'payout-address',
    status: 'finished',
    transactionId: 'cex-transaction-id',
  },
};

// A swap settled by the venue rather than by our own trace: the row knows the hash of what the wallet signed, the
// chain knows its normalized form, and only the submit intent holds both.
const SIGNED_MESSAGE_HASH = 'signed-message-hash';
const NORMALIZED_MESSAGE_HASH = 'normalized-external-message-hash';

function buildDexSwapIntent(overrides: Partial<WalletOperationIntent> = {}): WalletOperationIntent {
  return {
    operationId: 'swap:dex-backend-id',
    accountId: '0-ton-mainnet',
    kind: 'swap',
    createdAt: BASE_SWAP.timestamp,
    status: 'pending',
    ...overrides,
    swap: {
      type: 'dex',
      backendSwapId: 'dex-backend-id',
      submittedHashes: [SIGNED_MESSAGE_HASH, NORMALIZED_MESSAGE_HASH],
      ...overrides.swap,
    },
  };
}

describe('getSwapItemSlug', () => {
  it('passes legacy backend asset ids through unchanged', () => {
    expect(getSwapItemSlug('solana-usdc')).toBe('solana-usdc');
    expect(getSwapItemSlug('sol')).toBe('sol');
  });

  it('maps legacy TON symbol to the frontend TON slug', () => {
    expect(getSwapItemSlug('TON')).toBe(TONCOIN.slug);
  });

  it('uses chain context for legacy raw token addresses in locally-created swap items', () => {
    expect(getSwapItemSlug(SOLANA_USDC_MAINNET.tokenAddress, 'solana')).toBe(SOLANA_USDC_MAINNET.slug);
  });

  it('maps NewBackendId native assets to frontend native token slugs', () => {
    expect(getSwapItemSlug('ton:native')).toBe(TONCOIN.slug);
    expect(getSwapItemSlug('solana:native')).toBe('sol');
  });

  it('maps known NewBackendId token addresses to frontend token slugs', () => {
    expect(getSwapItemSlug(`solana:${SOLANA_USDC_MAINNET.tokenAddress}`)).toBe(SOLANA_USDC_MAINNET.slug);
    expect(getSwapItemSlug(`ethereum:${ETH_USDT_MAINNET.tokenAddress}`)).toBe(ETH_USDT_MAINNET.slug);
  });

  it('builds a frontend token slug for unknown NewBackendId token addresses', () => {
    expect(getSwapItemSlug(`solana:${SOLANA_EXAMPLE_MINT}`)).toBe('solana-aymatz4tcl');
  });

  it('does not require chain context for CEX cross-chain asset ids', () => {
    const activity = swapItemToActivity({
      id: '42',
      timestamp: 1,
      from: `solana:${SOLANA_EXAMPLE_MINT}`,
      fromAmount: '1',
      fromAddress: 'EQ-address',
      to: 'ton:native',
      toAmount: '2',
      status: 'pending',
      hashes: [],
      transactionIds: {},
      exchanger: 'near-intents',
      cexLabel: 'near-intents',
      cex: { status: 'waiting', transactionId: 'correlation-id' },
    } as any);

    expect(activity.from).toBe('solana-aymatz4tcl');
    expect(activity.to).toBe(TONCOIN.slug);
  });
});

describe('getSwapHistoryTokenFilter', () => {
  it('uses backend legacy asset ids for CEX history filters', () => {
    expect(getSwapHistoryTokenFilter(TONCOIN.slug)).toBe('TON');
    expect(getSwapHistoryTokenFilter(SOLANA.slug)).toBe(SOLANA.slug);
    expect(getSwapHistoryTokenFilter(ETH_USDT_MAINNET.slug)).toBe(ETH_USDT_MAINNET.tokenAddress);
  });
});

describe('swap activity projection', () => {
  it('projects CEX target token addresses to canonical token slugs for token histories', () => {
    const activity = swapItemToActivity(BASE_SWAP);

    expect(activity.from).toBe(TONCOIN.slug);
    expect(activity.to).toBe(TRC20_USDT_MAINNET.slug);
    expect(getActivityTokenSlugs(activity)).toEqual([TONCOIN.slug, TRC20_USDT_MAINNET.slug]);
  });

  it('projects a backend TON DEX swap into source and target histories while hiding raw submitted transactions', () => {
    const source: ApiTransactionActivity = {
      kind: 'transaction',
      id: 'trace-id:1-source',
      timestamp: BASE_SWAP.timestamp,
      amount: -100n,
      fromAddress: 'ton-address',
      toAddress: 'router-address',
      fee: 1n,
      slug: TONCOIN.slug,
      isIncoming: false,
      normalizedAddress: 'router-address',
      status: 'completed',
      externalMsgHashNorm: 'submitted-hash',
    };
    const payout: ApiTransactionActivity = {
      ...source,
      id: 'trace-id:2-payout',
      amount: 50n,
      isIncoming: true,
      slug: 'ton-target-token',
    };
    const swap: ApiSwapActivity = {
      kind: 'swap',
      id: 'dex-backend-id::backend-swap',
      timestamp: BASE_SWAP.timestamp,
      from: TONCOIN.slug,
      fromAmount: '5',
      fromAddress: 'ton-address',
      to: 'ton-target-token',
      toAmount: '5.1',
      networkFee: '0.09',
      swapFee: '0',
      ourFee: '0.04',
      status: 'completed',
      hashes: ['submitted-hash'],
      transactionIds: {},
      extra: {
        reconciliation: {
          operationId: 'swap:dex-backend-id',
          sourceActionIds: ['dex-backend-id::backend-swap'],
          hiddenSourceActionIds: [],
          reason: 'ton-aggregated-swap',
        },
      },
    };

    const result = projectBackendDexSwapActivities(
      [source, payout],
      [swap],
      new Set([swap.id]),
      [],
    );

    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: swap.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            operationId: 'swap:dex-backend-id',
            sourceActionIds: [swap.id, source.id, payout.id],
            hiddenSourceActionIds: [source.id, payout.id],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]);
    expect(result.projectedSourceActivities).toEqual(expect.arrayContaining([
      expect.objectContaining({
        id: source.id,
        shouldHide: true,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            operationId: 'swap:dex-backend-id',
            sourceActionIds: [swap.id, source.id, payout.id],
            hiddenSourceActionIds: [source.id, payout.id],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
      expect.objectContaining({ id: payout.id, shouldHide: true }),
    ]));
    expect(getActivityTokenSlugs(result.projectedSwapActivities[0])).toEqual([TONCOIN.slug, 'ton-target-token']);
  });

  it('hides a one-leg TON swap action by explicit identity and keeps the backend swap in both token histories', () => {
    const rawTonSwap: ApiSwapActivity = {
      kind: 'swap',
      id: 'trace-id:1-swap-leg',
      timestamp: BASE_SWAP.timestamp,
      from: TONCOIN.slug,
      fromAmount: '5',
      fromAddress: 'ton-address',
      to: 'ton-target-token',
      toAmount: '5.1',
      networkFee: '0.09',
      swapFee: '0',
      status: 'completed',
      hashes: [],
      externalMsgHashNorm: 'normalized-external-message-hash',
      transactionIds: {},
    };
    const backendSwap: ApiSwapActivity = {
      ...rawTonSwap,
      id: 'dex-backend-id::backend-swap',
      hashes: ['normalized-external-message-hash'],
      externalMsgHashNorm: undefined,
    };

    const result = projectBackendDexSwapActivities(
      [rawTonSwap],
      [backendSwap],
      new Set([backendSwap.id]),
      [],
    );

    expect(result.projectedSourceActivities).toEqual([
      expect.objectContaining({ id: rawTonSwap.id, shouldHide: true }),
    ]);
    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({ id: backendSwap.id }),
    ]);
    expect(getActivityTokenSlugs(result.projectedSwapActivities[0])).toEqual([TONCOIN.slug, 'ton-target-token']);
  });

  it('does not hide unrelated TON transactions when a backend DEX swap matches another raw row', () => {
    const source: ApiTransactionActivity = {
      kind: 'transaction',
      id: 'trace-id:1-source',
      timestamp: BASE_SWAP.timestamp,
      amount: -100n,
      fromAddress: 'ton-address',
      toAddress: 'router-address',
      fee: 1n,
      slug: TONCOIN.slug,
      isIncoming: false,
      normalizedAddress: 'router-address',
      status: 'completed',
      externalMsgHashNorm: 'matched-submitted-hash',
    };
    const unrelated: ApiTransactionActivity = {
      ...source,
      id: 'unrelated-trace:1-source',
      externalMsgHashNorm: 'unrelated-submitted-hash',
    };
    const swap: ApiSwapActivity = {
      kind: 'swap',
      id: 'dex-backend-id::backend-swap',
      timestamp: BASE_SWAP.timestamp,
      from: TONCOIN.slug,
      fromAmount: '5',
      fromAddress: 'ton-address',
      to: 'ton-target-token',
      toAmount: '5.1',
      networkFee: '0.09',
      swapFee: '0',
      ourFee: '0.04',
      status: 'completed',
      hashes: ['matched-submitted-hash'],
      transactionIds: {},
    };

    const result = projectBackendDexSwapActivities(
      [source, unrelated],
      [swap],
      new Set([swap.id]),
      [],
    );

    expect(result.projectedSourceActivities).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: source.id, shouldHide: true }),
      expect.objectContaining({ id: unrelated.id }),
    ]));
    expect(result.projectedSourceActivities.find(({ id }) => id === unrelated.id)?.shouldHide).toBeUndefined();
    expect(result.projectedSwapActivities[0].extra?.reconciliation?.hiddenSourceActionIds).toEqual([source.id]);
  });

  it('does not emit a backend DEX duplicate when a trace aggregate already represents the swap', () => {
    const aggregate: ApiSwapActivity = {
      kind: 'swap',
      id: 'trace-id:2-aggregate',
      timestamp: BASE_SWAP.timestamp,
      from: 'ton-source-token',
      fromAmount: '300000',
      fromAddress: 'ton-address',
      to: TONCOIN.slug,
      toAmount: '5.636858156',
      networkFee: '0.09',
      swapFee: '0',
      ourFee: '2625',
      status: 'completed',
      hashes: [],
      externalMsgHashNorm: 'normalized-external-message-hash',
      transactionIds: {},
      extra: {
        mtwAggregator: {
          traceId: 'trace-id',
          swapIds: ['trace-id:1-leg', 'trace-id:2-aggregate'],
          from: 'ton-source-token',
          to: TONCOIN.slug,
        },
        reconciliation: {
          sourceActionIds: ['trace-id:1-leg', 'trace-id:2-aggregate', 'trace-id:3-fee'],
          hiddenSourceActionIds: ['trace-id:1-leg', 'trace-id:3-fee'],
          reason: 'ton-aggregated-swap',
        },
      },
    };
    const backendSwap: ApiSwapActivity = {
      kind: 'swap',
      id: 'dex-backend-id::backend-swap',
      timestamp: BASE_SWAP.timestamp - 2_000,
      from: 'ton-source-token',
      fromAmount: '300000.000000000000000000',
      fromAddress: 'ton-address',
      to: TONCOIN.slug,
      toAmount: '5.636858157000000000',
      networkFee: '0.09',
      swapFee: '0',
      ourFee: '2625',
      status: 'completed',
      hashes: ['normalized-external-message-hash'],
      transactionIds: {},
    };

    const result = projectBackendDexSwapActivities(
      [aggregate],
      [backendSwap],
      new Set([backendSwap.id]),
      [],
    );

    expect(result.projectedSourceActivities).toEqual([aggregate]);
    expect(result.projectedSwapActivities).toEqual([]);
  });

  it('keeps same pair/amount/time backend DEX swap visible when identities are unrelated', () => {
    const aggregate: ApiSwapActivity = {
      kind: 'swap',
      id: 'trace-id:2-aggregate',
      timestamp: BASE_SWAP.timestamp,
      from: 'ton-source-token',
      fromAmount: '300000',
      fromAddress: 'ton-address',
      to: TONCOIN.slug,
      toAmount: '5.636858156',
      networkFee: '0.09',
      swapFee: '0',
      ourFee: '2625',
      status: 'completed',
      hashes: [],
      transactionIds: {},
      extra: {
        mtwAggregator: {
          traceId: 'trace-id',
          swapIds: ['trace-id:1-leg', 'trace-id:2-aggregate'],
          from: 'ton-source-token',
          to: TONCOIN.slug,
        },
        reconciliation: {
          sourceActionIds: ['trace-id:1-leg', 'trace-id:2-aggregate', 'trace-id:3-fee'],
          hiddenSourceActionIds: ['trace-id:1-leg', 'trace-id:3-fee'],
          reason: 'ton-aggregated-swap',
        },
      },
    };
    const backendSwap: ApiSwapActivity = {
      ...aggregate,
      id: 'dex-backend-id::backend-swap',
      hashes: ['unrelated-backend-hash'],
      transactionIds: {},
      extra: undefined,
    };

    const result = projectBackendDexSwapActivities(
      [aggregate],
      [backendSwap],
      new Set([backendSwap.id]),
      [],
    );

    expect(result.projectedSourceActivities).toEqual([aggregate]);
    expect(result.projectedSwapActivities).toEqual([expect.objectContaining({ id: backendSwap.id })]);
  });

  it('hides the transactions of a venue-settled swap under its backend row through the submit intent', () => {
    const { sent, excess, backendSwap } = buildEscrowSwapFixture();

    const result = projectBackendDexSwapActivities(
      [sent, excess],
      [backendSwap],
      new Set([backendSwap.id]),
      [buildDexSwapIntent()],
    );

    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: backendSwap.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({
            hiddenSourceActionIds: [sent.id, excess.id],
            reason: 'ton-aggregated-swap',
          }),
        }),
      }),
    ]);
    expect(result.projectedSourceActivities).toEqual([
      expect.objectContaining({ id: sent.id, shouldHide: true }),
      expect.objectContaining({ id: excess.id, shouldHide: true }),
    ]);
  });

  it('keeps the transactions of a venue-settled swap visible without a submit intent', () => {
    const { sent, excess, backendSwap } = buildEscrowSwapFixture();

    const result = projectBackendDexSwapActivities(
      [sent, excess],
      [backendSwap],
      new Set([backendSwap.id]),
      [],
    );

    expect(result.projectedSourceActivities).toEqual([sent, excess]);
    expect(result.projectedSwapActivities).toEqual([expect.objectContaining({ id: backendSwap.id })]);
  });

  it('keeps transactions visible when two backend rows claim the same submitted message', () => {
    const { sent, backendSwap } = buildEscrowSwapFixture();
    const otherBackendSwap: ApiSwapActivity = {
      ...backendSwap,
      id: 'other-backend-id::backend-swap',
      hashes: [SIGNED_MESSAGE_HASH],
      extra: {
        reconciliation: {
          operationId: 'swap:other-backend-id',
          sourceActionIds: ['other-backend-id::backend-swap'],
          hiddenSourceActionIds: [],
          reason: 'ton-aggregated-swap',
        },
      },
    };

    const result = projectBackendDexSwapActivities(
      [sent],
      [backendSwap, otherBackendSwap],
      new Set([backendSwap.id, otherBackendSwap.id]),
      [
        buildDexSwapIntent(),
        buildDexSwapIntent({
          operationId: 'swap:other-backend-id',
          swap: { type: 'dex', backendSwapId: 'other-backend-id', submittedHashes: [SIGNED_MESSAGE_HASH] },
        }),
      ],
    );

    expect(result.projectedSourceActivities).toEqual([sent]);
  });

  it('suppresses the backend row rather than the trace aggregate when only the intent relates them', () => {
    const aggregate = buildTonAggregate('trace-id');
    const backendSwap: ApiSwapActivity = {
      ...aggregate,
      id: 'dex-backend-id::backend-swap',
      hashes: [],
      externalMsgHashNorm: undefined,
      extra: {
        reconciliation: {
          operationId: 'swap:dex-backend-id',
          sourceActionIds: ['dex-backend-id::backend-swap'],
          hiddenSourceActionIds: [],
          reason: 'ton-aggregated-swap',
        },
      },
    };

    const result = projectBackendDexSwapActivities(
      [aggregate],
      [backendSwap],
      new Set([backendSwap.id]),
      [buildDexSwapIntent()],
    );

    expect(result.projectedSourceActivities).toEqual([aggregate]);
    expect(result.projectedSwapActivities).toEqual([]);
  });

  it('keeps one row for a trade whose messages landed in several traces', () => {
    const firstAggregate = buildTonAggregate('trace-id');
    const secondAggregate = buildTonAggregate('other-trace-id');
    const backendSwap = buildBackendRow('dex-backend-id', [SIGNED_MESSAGE_HASH]);

    const result = projectBackendDexSwapActivities(
      [firstAggregate, secondAggregate],
      [backendSwap],
      new Set([backendSwap.id]),
      [buildDexSwapIntent()],
    );

    expect(result.projectedSourceActivities).toEqual([
      expect.objectContaining({ id: firstAggregate.id, shouldHide: true }),
      expect.objectContaining({ id: secondAggregate.id, shouldHide: true }),
    ]);
    expect(result.projectedSwapActivities).toEqual([expect.objectContaining({ id: backendSwap.id })]);
  });

  it('keeps both rows when one aggregate answers to two of them', () => {
    const aggregate = buildTonAggregate('trace-id');
    const firstSwap = buildBackendRow('alpha-id', [SIGNED_MESSAGE_HASH]);
    const secondSwap = buildBackendRow('beta-id', [SIGNED_MESSAGE_HASH]);

    const result = projectBackendDexSwapActivities(
      [aggregate],
      [firstSwap, secondSwap],
      new Set([firstSwap.id, secondSwap.id]),
      [
        buildDexSwapIntent({
          operationId: 'swap:alpha-id',
          swap: {
            type: 'dex',
            backendSwapId: 'alpha-id',
            submittedHashes: [SIGNED_MESSAGE_HASH, NORMALIZED_MESSAGE_HASH],
          },
        }),
        buildDexSwapIntent({
          operationId: 'swap:beta-id',
          swap: { type: 'dex', backendSwapId: 'beta-id', submittedHashes: [SIGNED_MESSAGE_HASH] },
        }),
      ],
    );

    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({ id: firstSwap.id }),
      expect.objectContaining({ id: secondSwap.id }),
    ]);
  });

  it('gives each backend row the transactions of its own swap when other intents are stored', () => {
    const { sent: firstSent, backendSwap: firstSwap } = buildEscrowSwapFixture();
    const secondSent: ApiTransactionActivity = {
      ...firstSent,
      id: 'other-trace-id:1-sent',
      externalMsgHashNorm: 'other-normalized-message-hash',
    };
    const secondSwap: ApiSwapActivity = {
      ...firstSwap,
      id: 'other-backend-id::backend-swap',
      hashes: ['other-signed-message-hash'],
      extra: {
        reconciliation: {
          operationId: 'swap:other-backend-id',
          sourceActionIds: ['other-backend-id::backend-swap'],
          hiddenSourceActionIds: [],
          reason: 'ton-aggregated-swap',
        },
      },
    };

    const result = projectBackendDexSwapActivities(
      [firstSent, secondSent],
      [firstSwap, secondSwap],
      new Set([firstSwap.id, secondSwap.id]),
      [
        buildDexSwapIntent({
          operationId: 'swap:other-backend-id',
          swap: {
            type: 'dex',
            backendSwapId: 'other-backend-id',
            submittedHashes: ['other-signed-message-hash', 'other-normalized-message-hash'],
          },
        }),
        buildDexSwapIntent(),
      ],
    );

    expect(result.projectedSwapActivities).toEqual([
      expect.objectContaining({
        id: firstSwap.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({ hiddenSourceActionIds: [firstSent.id] }),
        }),
      }),
      expect.objectContaining({
        id: secondSwap.id,
        extra: expect.objectContaining({
          reconciliation: expect.objectContaining({ hiddenSourceActionIds: [secondSent.id] }),
        }),
      }),
    ]);
  });
});

function buildBackendRow(backendSwapId: string, hashes: string[]): ApiSwapActivity {
  return {
    kind: 'swap',
    id: `${backendSwapId}::backend-swap`,
    timestamp: BASE_SWAP.timestamp,
    from: TONCOIN.slug,
    fromAmount: '100',
    fromAddress: 'ton-address',
    to: 'ton-target-token',
    toAmount: '5.1',
    networkFee: '0.09',
    swapFee: '0',
    status: 'completed',
    hashes,
    transactionIds: {},
    extra: {
      reconciliation: {
        operationId: `swap:${backendSwapId}`,
        sourceActionIds: [`${backendSwapId}::backend-swap`],
        hiddenSourceActionIds: [],
        reason: 'ton-aggregated-swap',
      },
    },
  };
}

function buildEscrowSwapFixture() {
  const sent: ApiTransactionActivity = {
    kind: 'transaction',
    id: 'trace-id:1-sent',
    timestamp: BASE_SWAP.timestamp,
    amount: -100n,
    fromAddress: 'ton-address',
    toAddress: 'escrow-address',
    fee: 1n,
    slug: TONCOIN.slug,
    isIncoming: false,
    normalizedAddress: 'escrow-address',
    status: 'completed',
    externalMsgHashNorm: NORMALIZED_MESSAGE_HASH,
  };
  const excess: ApiTransactionActivity = {
    ...sent,
    id: 'trace-id:2-excess',
    amount: 2n,
    isIncoming: true,
    fromAddress: 'escrow-address',
    toAddress: 'ton-address',
  };
  // The venue settles the trade off our transactions, so the row carries only the hash of the message the wallet
  // signed - the normalized hash the actions above are stamped with never reaches it.
  const backendSwap: ApiSwapActivity = {
    kind: 'swap',
    id: 'dex-backend-id::backend-swap',
    timestamp: BASE_SWAP.timestamp,
    from: TONCOIN.slug,
    fromAmount: '100',
    fromAddress: 'ton-address',
    to: 'ton-target-token',
    toAmount: '5.1',
    networkFee: '0.09',
    swapFee: '0',
    status: 'completed',
    hashes: [SIGNED_MESSAGE_HASH],
    transactionIds: {},
    extra: {
      reconciliation: {
        operationId: 'swap:dex-backend-id',
        sourceActionIds: ['dex-backend-id::backend-swap'],
        hiddenSourceActionIds: [],
        reason: 'ton-aggregated-swap',
      },
    },
  };

  return { sent, excess, backendSwap };
}

function buildTonAggregate(traceId: string): ApiSwapActivity {
  return {
    kind: 'swap',
    id: `${traceId}:2-aggregate`,
    timestamp: BASE_SWAP.timestamp,
    from: TONCOIN.slug,
    fromAmount: '100',
    fromAddress: 'ton-address',
    to: 'ton-target-token',
    toAmount: '5.1',
    networkFee: '0.09',
    swapFee: '0',
    status: 'completed',
    hashes: [],
    externalMsgHashNorm: NORMALIZED_MESSAGE_HASH,
    transactionIds: {},
    extra: {
      mtwAggregator: {
        traceId,
        swapIds: [`${traceId}:2-aggregate`],
        from: TONCOIN.slug,
        to: 'ton-target-token',
      },
      reconciliation: {
        sourceActionIds: [`${traceId}:1-leg`, `${traceId}:2-aggregate`],
        hiddenSourceActionIds: [`${traceId}:1-leg`],
        reason: 'ton-aggregated-swap',
      },
    },
  };
}

describe('getBackendDexHistoryFetchFromTime', () => {
  const NOW = 1_700_000_100_000;
  const SLICE_START = NOW - 10_000;

  it('keeps the slice start when no intent is live', () => {
    expect(getBackendDexHistoryFetchFromTime(SLICE_START, [], NOW)).toBe(SLICE_START);
  });

  it('reaches back to cover an in-flight swap row created before the slice', () => {
    const intent = buildDexSwapIntent({ createdAt: SLICE_START - 15_000 });

    expect(getBackendDexHistoryFetchFromTime(SLICE_START, [intent], NOW))
      .toBeLessThanOrEqual(intent.createdAt);
  });

  it('keeps the slice start when the intent is newer than it beyond the skew margin', () => {
    const intent = buildDexSwapIntent({ createdAt: SLICE_START + 5 * 60 * 1000 });

    expect(getBackendDexHistoryFetchFromTime(SLICE_START, [intent], NOW)).toBe(SLICE_START);
  });

  it('ignores an intent old enough for finalization to have recorded the chain identity', () => {
    const intent = buildDexSwapIntent({ createdAt: NOW - 2 * 60 * 60 * 1000 });

    expect(getBackendDexHistoryFetchFromTime(SLICE_START, [intent], NOW)).toBe(SLICE_START);
  });

  it('ignores intents that cannot pull a row into the projection', () => {
    const cexIntent = buildDexSwapIntent({ createdAt: SLICE_START - 15_000 });
    cexIntent.swap = { ...cexIntent.swap!, type: 'cex' };
    const unsubmittedIntent = buildDexSwapIntent({ createdAt: SLICE_START - 15_000 });
    unsubmittedIntent.swap = { ...unsubmittedIntent.swap!, submittedHashes: [] };

    expect(getBackendDexHistoryFetchFromTime(SLICE_START, [cexIntent, unsubmittedIntent], NOW)).toBe(SLICE_START);
  });
});
