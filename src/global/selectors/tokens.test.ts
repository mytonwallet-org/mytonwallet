import type { GlobalState } from '../types';

import {
  BASE,
  ETH,
  ETH_USDT_MAINNET,
  TONCOIN,
} from '../../config';
import { INITIAL_STATE } from '../initialState';
import { selectTokenInfoUserTokens } from './tokens';

const ACCOUNT_ID = 'mainnet-0';

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
            base: { address: '0x0000000000000000000000000000000000000000' },
          },
        },
      },
    },
    byAccountId: {
      [ACCOUNT_ID]: {
        balances: {
          bySlug: {
            [TONCOIN.slug]: 1_000_000_000n,
            [ETH.slug]: 2_000_000_000_000_000_000n,
          },
        },
      },
    },
    tokenInfo: {
      bySlug: {
        [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 0 },
        [ETH.slug]: { ...ETH, priceUsd: 3000, percentChange24h: 100 },
        [BASE.slug]: { ...BASE, priceUsd: 3000, percentChange24h: 100 },
        [ETH_USDT_MAINNET.slug]: { ...ETH_USDT_MAINNET, priceUsd: 1, percentChange24h: 0 },
      },
    },
    swapTokenInfo: {
      bySlug: {
        [TONCOIN.slug]: { ...TONCOIN, isPopular: true },
      },
    },
  } as GlobalState;
}

describe('selectTokenInfoUserTokens', () => {
  it('uses tokenInfo, not swapTokenInfo, so Settings asset search can find EVM assets', () => {
    const global = buildGlobal();
    const tokens = selectTokenInfoUserTokens(global)!;
    const tokensBySlug = Object.fromEntries(tokens.map((token) => [token.slug, token]));

    expect(Object.keys(tokensBySlug)).toEqual(expect.arrayContaining([
      TONCOIN.slug,
      ETH.slug,
      BASE.slug,
      ETH_USDT_MAINNET.slug,
    ]));
    expect(tokensBySlug[BASE.slug].chain).toBe('base');
    expect(tokensBySlug[BASE.slug].amount).toBe(0n);
    expect(tokensBySlug[ETH.slug].amount).toBe(2_000_000_000_000_000_000n);
    expect(tokensBySlug[ETH.slug].price).toBe(3000);
    expect(tokensBySlug[ETH.slug].change24h).toBe(1);
  });

  it('memoizes the list across unrelated global changes', () => {
    const global = buildGlobal();

    expect(selectTokenInfoUserTokens({
      ...global,
      isBackupWalletModalOpen: true,
    })).toBe(selectTokenInfoUserTokens(global));
  });
});
