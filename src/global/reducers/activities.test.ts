import type { ApiSwapActivity, ApiTransactionActivity } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import {
  addInitialActivities,
  addNewActivities,
  addPastActivities,
  applyActivitiesPatch,
  removeActivities,
  replaceCurrentActivityId,
} from './activities';

const ACCOUNT_ID = 'test-account';

function buildGlobal(): GlobalState {
  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: {
      byId: {
        [ACCOUNT_ID]: {
          title: 'Test',
          type: 'mnemonic',
          byChain: {
            ton: { address: 'ton-address' },
            solana: { address: 'solana-address' },
          },
        },
      },
    },
    byAccountId: {
      [ACCOUNT_ID]: {},
    },
  } as GlobalState;
}

function makeActivity(
  id: string,
  slug: string,
  timestamp: number,
  status: ApiTransactionActivity['status'] = 'completed',
): ApiTransactionActivity {
  return {
    id,
    kind: 'transaction',
    amount: 1n,
    fee: 0n,
    fromAddress: 'from',
    toAddress: 'to',
    normalizedAddress: 'to',
    slug,
    isIncoming: true,
    status,
    timestamp,
  };
}

describe('addInitialActivities', () => {
  it('keeps exhausted one-item histories from different chains', () => {
    let global = buildGlobal();
    const tonActivity = makeActivity('ton-100', 'toncoin', 100);
    const solanaActivity = makeActivity('sol-200', 'sol', 200);

    global = addInitialActivities(global, ACCOUNT_ID, [tonActivity], {}, 'ton', false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain).toBeUndefined();

    global = addInitialActivities(global, ACCOUNT_ID, [solanaActivity], {}, 'solana', false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain).toEqual(['sol-200', 'ton-100']);
    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBe(true);
  });

  it('keeps exhausted chain items below the paginating chain boundary', () => {
    // An exhausted chain has no more history to load; trimming its old items would hide
    // data we already know is complete and never re-include it on subsequent pagination.
    let global = buildGlobal();
    const tonActivities = [
      makeActivity('ton-1000', 'toncoin', 1000),
      makeActivity('ton-900', 'toncoin', 900),
    ];
    const solanaActivity = makeActivity('sol-800', 'sol', 800);

    global = addInitialActivities(global, ACCOUNT_ID, tonActivities, {}, 'ton', true);
    global = addInitialActivities(global, ACCOUNT_ID, [solanaActivity], {}, 'solana', false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain)
      .toEqual(['ton-1000', 'ton-900', 'sol-800']);
    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBeUndefined();
  });

  it('trims paginating chain items below the boundary', () => {
    // Paginating chains must be trimmed below the boundary because intermediate items
    // from any other paginating chain might still be unloaded.
    let global = buildGlobal();
    const tonActivity = makeActivity('ton-1000', 'toncoin', 1000);
    const solanaActivities = [
      makeActivity('sol-950', 'sol', 950),
      makeActivity('sol-800', 'sol', 800),
    ];

    global = addInitialActivities(global, ACCOUNT_ID, [tonActivity], {}, 'ton', true);
    global = addInitialActivities(global, ACCOUNT_ID, solanaActivities, {}, 'solana', true);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain).toEqual(['ton-1000']);
  });

  it('recovers end-of-history when a failed chain later reports an empty history', () => {
    // A failed initial load emits an empty update without `mainHistoryHasMore`. When the chain
    // recovers and reports an empty history with `mainHistoryHasMore=false`, that update carries
    // new information and must not be skipped - otherwise an empty wallet keeps the loading
    // spinner forever instead of showing the empty state.
    let global = buildGlobal();

    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'ton', false);
    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'solana', undefined);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain).toEqual([]);
    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBeUndefined();

    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'solana', false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBe(true);
  });

  it('skips uninformative empty re-emits of an already loaded chain', () => {
    let global = buildGlobal();

    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'ton', false);
    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'solana', false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBe(true);

    const prevGlobal = global;
    // A failed re-emit (no `mainHistoryHasMore`) must not degrade the reached state
    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'solana', undefined);
    expect(global).toBe(prevGlobal);

    // A repeated successful empty emit carries no new information either
    global = addInitialActivities(global, ACCOUNT_ID, [], {}, 'solana', false);
    expect(global).toBe(prevGlobal);
  });
});

describe('addPastActivities main feed', () => {
  it('re-includes previously trimmed items when all chains exhaust', () => {
    // Items hidden by the initial pagination boundary must reappear once the boundary
    // collapses (here: when main-feed pagination signals all chains are exhausted).
    let global = buildGlobal();
    const tonActivity = makeActivity('ton-1000', 'toncoin', 1000);
    const solanaActivities = [
      makeActivity('sol-950', 'sol', 950),
      makeActivity('sol-800', 'sol', 800),
    ];

    global = addInitialActivities(global, ACCOUNT_ID, [tonActivity], {}, 'ton', true);
    global = addInitialActivities(global, ACCOUNT_ID, solanaActivities, {}, 'solana', true);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain).toEqual(['ton-1000']);

    const morePastTon = [makeActivity('ton-700', 'toncoin', 700)];

    global = addPastActivities(global, ACCOUNT_ID, undefined, morePastTon, true);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain)
      .toEqual(['ton-1000', 'sol-950', 'sol-800', 'ton-700']);
    expect(global.byAccountId[ACCOUNT_ID].activities?.isMainHistoryEndReached).toBe(true);
  });
});

describe('addNewActivities', () => {
  it('does not regress a completed activity to pending after a late pending update', () => {
    let global = buildGlobal();
    const completedActivity = makeActivity('same-id', 'toncoin', 1000, 'completed');
    const latePendingActivity = makeActivity('same-id', 'toncoin', 1000, 'pending');

    global = addNewActivities(global, ACCOUNT_ID, [completedActivity], 'ton');
    global = addNewActivities(global, ACCOUNT_ID, [latePendingActivity], 'ton');

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.byId['same-id'].status).toBe('completed');
    expect(activities.pendingActivityIds?.ton ?? []).not.toContain('same-id');
  });

  it('indexes visible cross-chain CEX swap upserts by both source and target token histories', () => {
    let global = buildGlobal();
    const swapActivity: ApiSwapActivity = {
      id: '2462348::backend-swap',
      kind: 'swap',
      from: 'toncoin',
      fromAmount: '16.400000000000000000',
      fromAddress: 'ton-address',
      to: 'tron-tr7nhqjekq',
      toAmount: '28.854382000000000000',
      networkFee: '0',
      swapFee: '0',
      status: 'completed',
      timestamp: 1779718745117,
      hashes: [],
      transactionIds: {},
      cex: {
        payinAddress: 'payin-address',
        payoutAddress: 'payout-address',
        status: 'finished',
        transactionId: '2462348',
      },
    };

    global = addNewActivities(global, ACCOUNT_ID, [swapActivity]);

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.idsBySlug?.toncoin).toContain(swapActivity.id);
    expect(activities.idsBySlug?.['tron-tr7nhqjekq']).toContain(swapActivity.id);
  });

  it('does not infer source visibility from reconciliation metadata', () => {
    let global = buildGlobal();
    const source = makeTonSwap('trace:1', 1000);
    const aggregate = makeTonSwap('trace:0', 1001, {
      extra: {
        reconciliation: {
          sourceActionIds: ['trace:0', source.id],
          hiddenSourceActionIds: [source.id],
          reason: 'ton-aggregated-swap',
        },
      },
    });

    global = addNewActivities(global, ACCOUNT_ID, [source], 'ton');
    global = addNewActivities(global, ACCOUNT_ID, [aggregate], 'ton');

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.byId[source.id].shouldHide).toBeUndefined();
    expect(activities.byId[source.id].extra?.reconciliation).toBeUndefined();
  });

  it('stores an explicit SDK visibility projection without re-deriving it', () => {
    let global = buildGlobal();
    const hiddenSource = makeTonSwap('trace:1', 1000, {
      shouldHide: true,
      extra: {
        reconciliation: {
          sourceActionIds: ['trace:0', 'trace:1'],
          hiddenSourceActionIds: ['trace:1'],
          reason: 'ton-aggregated-swap',
        },
      },
    });

    global = addNewActivities(global, ACCOUNT_ID, [hiddenSource], 'ton');

    const stored = global.byAccountId[ACCOUNT_ID].activities!.byId[hiddenSource.id];
    expect(stored.shouldHide).toBe(true);
    expect(stored.extra?.reconciliation).toEqual(hiddenSource.extra?.reconciliation);
  });

  it('does not override an explicit SDK removal for a local representative', () => {
    let global = buildGlobal();
    const local = makeTonSwap('swap-id::local', 1000, {
      status: 'pendingTrusted',
      extra: {
        reconciliation: {
          operationId: 'swap:swap-id',
          sourceActionIds: ['swap-id::local', 'trace:1'],
          hiddenSourceActionIds: ['trace:1'],
          reason: 'local-intent',
        },
      },
    });

    global = addNewActivities(global, ACCOUNT_ID, [local], 'ton');
    global = removeActivities(global, ACCOUNT_ID, [local.id]);

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.byId[local.id]).toBeUndefined();
    expect(activities.idsMain).not.toContain(local.id);
  });
});

describe('applyActivitiesPatch', () => {
  it('stores SDK upserts exactly without re-running status or metadata reconciliation', () => {
    let global = buildGlobal();
    const existing = {
      ...makeActivity('same-id', 'toncoin', 1000, 'completed'),
      extra: {
        reconciliation: {
          operationId: 'operation-2',
          sourceActionIds: ['same-id', 'old-source'],
          hiddenSourceActionIds: ['old-source'],
          reason: 'cex-swap' as const,
        },
      },
    };
    const authoritative = {
      ...existing,
      status: 'pending' as const,
      extra: {
        reconciliation: {
          operationId: 'operation-2',
          sourceActionIds: ['same-id', 'new-source'],
          hiddenSourceActionIds: ['new-source'],
          reason: 'cex-swap' as const,
        },
      },
    };

    global = addNewActivities(global, ACCOUNT_ID, [existing], 'ton');
    global = applyActivitiesPatch(global, ACCOUNT_ID, { upsert: [authoritative], removeIds: [] });

    expect(global.byAccountId[ACCOUNT_ID].activities!.byId[existing.id]).toBe(authoritative);
  });

  it('keeps hidden upserts by id while removing them from presentation and pending indexes', () => {
    let global = buildGlobal();
    const source = makeActivity('pending-source', 'toncoin', 1000, 'pending');
    const hiddenSource = {
      ...source,
      shouldHide: true,
    };

    global = addNewActivities(global, ACCOUNT_ID, [source], 'ton');
    global = {
      ...global,
      byAccountId: {
        ...global.byAccountId,
        [ACCOUNT_ID]: {
          ...global.byAccountId[ACCOUNT_ID],
          activities: {
            ...global.byAccountId[ACCOUNT_ID].activities!,
            mainActivityIdsByChain: { ton: [source.id] },
          },
        },
      },
    };
    global = applyActivitiesPatch(global, ACCOUNT_ID, { upsert: [hiddenSource], removeIds: [] });

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.byId[source.id]).toBe(hiddenSource);
    expect(activities.idsMain).not.toContain(source.id);
    expect(activities.idsBySlug?.toncoin ?? []).not.toContain(source.id);
    expect(activities.mainActivityIdsByChain?.ton ?? []).not.toContain(source.id);
    expect(activities.pendingActivityIds?.ton ?? []).not.toContain(source.id);
  });

  it('indexes visible SDK upserts and keeps newest activity references authoritative', () => {
    let global = buildGlobal();
    const canonical = makeActivity('canonical', 'toncoin', 1000, 'completed');

    global = applyActivitiesPatch(global, ACCOUNT_ID, { upsert: [canonical], removeIds: [] });

    const activities = global.byAccountId[ACCOUNT_ID].activities!;
    expect(activities.byId[canonical.id]).toBe(canonical);
    expect(activities.idsMain).toContain(canonical.id);
    expect(activities.idsBySlug?.toncoin).toContain(canonical.id);
    expect(activities.newestActivitiesBySlug?.toncoin).toBe(canonical);
  });
});

describe('replaceCurrentActivityId', () => {
  it('keeps only SDK-provided aliases for presentation identity', () => {
    let global = buildGlobal();
    global.byAccountId[ACCOUNT_ID] = {
      currentActivityId: 'local-id',
      activities: {
        byId: {},
        activityIdReplacements: { 'older-local-id': 'local-id' },
      },
    };

    global = replaceCurrentActivityId(global, ACCOUNT_ID, { 'local-id': 'chain-id' });

    expect(global.byAccountId[ACCOUNT_ID].currentActivityId).toBe('chain-id');
    expect(global.byAccountId[ACCOUNT_ID].activities?.activityIdReplacements).toEqual({
      'older-local-id': 'local-id',
      'local-id': 'chain-id',
    });
  });
});

function makeTonSwap(
  id: string,
  timestamp: number,
  overrides: Partial<ApiSwapActivity> = {},
): ApiSwapActivity {
  return {
    id,
    kind: 'swap',
    from: 'toncoin',
    fromAmount: '0.2',
    fromAddress: 'ton-address',
    to: 'ton-eqcsxgzphq',
    toAmount: '0.1',
    networkFee: '0.1',
    swapFee: '0',
    status: 'confirmed',
    timestamp,
    hashes: [],
    transactionIds: {},
    ...overrides,
  };
}
