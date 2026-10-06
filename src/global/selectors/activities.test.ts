import type { ApiTransactionActivity } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { addPastActivities } from '../reducers/activities';
import { selectLastActivityTimestamp, selectNewestActivityTimestamps } from './activities';

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
          byChain: { ethereum: { address: '0xabc' } },
        },
      },
    },
    byAccountId: { [ACCOUNT_ID]: {} },
  } as unknown as GlobalState;
}

function makeActivity(id: string, timestamp: number): ApiTransactionActivity {
  return {
    id,
    kind: 'transaction',
    amount: 1n,
    fee: 0n,
    fromAddress: 'from',
    toAddress: 'to',
    normalizedAddress: 'to',
    slug: 'eth',
    isIncoming: true,
    status: 'completed',
    timestamp,
  };
}

describe('selectLastActivityTimestamp', () => {
  it('answers for a page that holds nothing but backend swaps', () => {
    // A wallet whose whole slice is swaps merged from our backend used to store the page and
    // still report no anchor, so the next fetch asked for the first page again - and again, for
    // as long as the app ran. Observed in production as ~6,800 first-page requests in a day from
    // one device, with not a single incremental poll among them.
    let global = buildGlobal();
    const page = Array.from({ length: 50 }, (_, i) => makeActivity(`swap-${i}:backend-swap`, 1_000_000 - i));

    global = addPastActivities(global, ACCOUNT_ID, undefined, page, false);

    expect(global.byAccountId[ACCOUNT_ID].activities?.idsMain?.length).toBe(50);
    expect(selectLastActivityTimestamp(global, ACCOUNT_ID)).toBe(1_000_000 - 49);
  });

  it('still prefers an activity the chain can be paged from', () => {
    let global = buildGlobal();
    const page = [
      ...Array.from({ length: 49 }, (_, i) => makeActivity(`swap-${i}:backend-swap`, 1_000_000 - i)),
      makeActivity('plain-1', 900_000),
    ];

    global = addPastActivities(global, ACCOUNT_ID, undefined, page, false);

    expect(selectLastActivityTimestamp(global, ACCOUNT_ID)).toBe(900_000);
  });

  it('has no anchor before anything is stored', () => {
    expect(selectLastActivityTimestamp(buildGlobal(), ACCOUNT_ID)).toBeUndefined();
  });
});

describe('selectActivityPollingTimestamps', () => {
  it('drops a cached cursor when the chain has no stored activity ids', () => {
    let global = buildGlobal();
    global = {
      ...global,
      accounts: {
        byId: {
          [ACCOUNT_ID]: {
            title: 'Test',
            type: 'mnemonic',
            byChain: { zcash: { address: 't1Yu7eHTifSqttLD6X8trcqwDExs6TpL87o' } },
          },
        },
      },
      byAccountId: {
        [ACCOUNT_ID]: {
          activities: {
            byId: {},
            idsMain: [],
            idsBySlug: {},
            newestActivitiesBySlug: {
              zec: makeActivity('d0379a41', 1_790_778_446_000),
            },
            areInitialActivitiesLoaded: { zcash: true },
            mainActivityIdsByChain: { zcash: [] },
          },
        },
      },
    } as unknown as GlobalState;

    expect(selectNewestActivityTimestamps(global, ACCOUNT_ID)).toEqual({ zec: 1_790_778_446_000 });
  });
});
