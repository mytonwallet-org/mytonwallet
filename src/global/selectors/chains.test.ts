import type { GlobalState } from '../types';

import { ETH, TONCOIN } from '../../config';
import { mapValues } from '../../util/iteratees';
import { INITIAL_STATE } from '../initialState';
import { selectAccountChainDisplay } from './chains';

const ACCOUNT_ID = 'mainnet-0';
const ONE_TON = 1_000_000_000n;
const ONE_ETH = 1_000_000_000_000_000_000n;

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
            ethereum: { address: '0x0000000000000000000000000000000000000000' },
          },
        },
      },
    },
    byAccountId: {
      [ACCOUNT_ID]: {
        balances: {
          bySlug: {
            [TONCOIN.slug]: ONE_TON,
            [ETH.slug]: 0n,
          },
        },
      },
    },
    tokenInfo: {
      bySlug: {
        [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 0 },
        [ETH.slug]: { ...ETH, priceUsd: 3000, percentChange24h: 0 },
      },
    },
  } as GlobalState;
}

describe('selectAccountChainDisplay', () => {
  it('keeps the result across a price tick', () => {
    const global = buildGlobal();
    const first = selectAccountChainDisplay(global, ACCOUNT_ID);
    const tickedGlobal = {
      ...global,
      tokenInfo: {
        bySlug: mapValues(global.tokenInfo.bySlug, (token) => ({ ...token, priceUsd: token.priceUsd * 2 })),
      },
    } as GlobalState;

    expect(first.visibleChains).toEqual(['ton']);
    expect(selectAccountChainDisplay(tickedGlobal, ACCOUNT_ID)).toBe(first);
  });

  it('recomputes once a chain gets funded', () => {
    const global = buildGlobal();
    const first = selectAccountChainDisplay(global, ACCOUNT_ID);
    const fundedGlobal = {
      ...global,
      byAccountId: {
        [ACCOUNT_ID]: {
          balances: { bySlug: { ...global.byAccountId[ACCOUNT_ID].balances!.bySlug, [ETH.slug]: ONE_ETH } },
        },
      },
    } as GlobalState;
    const second = selectAccountChainDisplay(fundedGlobal, ACCOUNT_ID);

    expect(second).not.toBe(first);
    expect(second.visibleChains).toHaveLength(2);
    expect(second.visibleChains[0]).toBe('ethereum');
  });
});
