import type { ApiActivity } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { addInitialActivities, addPastActivities } from './activities';

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

function makeActivity(id: string, slug: string, timestamp: number): ApiActivity {
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
    status: 'completed',
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
