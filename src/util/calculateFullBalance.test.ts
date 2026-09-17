import type { ApiBalanceBySlug, ApiCurrencyRates, ApiStakingState } from '../api/types';
import type { AccountSettings, GlobalState } from '../global/types';

import { DEFAULT_STAKING_STATE, STAKED_TON_SLUG, TONCOIN } from '../config';
import { INITIAL_STATE } from '../global/initialState';
import { selectAccountTokensMemoizedFor } from '../global/selectors/tokens';
import { calculateFullBalance, calculateTotalBalanceValue } from './calculateFullBalance';

const ACCOUNT_ID = 'mainnet-0';
const ONE_TON = 1_000_000_000n; // 9 decimals
const ONE_USDT = 1_000_000n; // 6 decimals
const RATE = '0.9';

const USDT_SLUG = 'ton-usdt';
const DELETED_SLUG = 'ton-deleted';
const UNKNOWN_SLUG = 'ton-unknown'; // present in balances, absent from `tokenInfo`
const PRICELESS_SLUG = 'ton-priceless';

const TOKEN_INFO = {
  bySlug: {
    [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 1 },
    [STAKED_TON_SLUG]: { ...TONCOIN, slug: STAKED_TON_SLUG, symbol: 'STAKED', priceUsd: 5, percentChange24h: 1 },
    [USDT_SLUG]: { ...TONCOIN, slug: USDT_SLUG, symbol: 'USDT', decimals: 6, priceUsd: 1, percentChange24h: 0 },
    [DELETED_SLUG]: { ...TONCOIN, slug: DELETED_SLUG, symbol: 'DEL', priceUsd: 3, percentChange24h: -2 },
    [PRICELESS_SLUG]: { ...TONCOIN, slug: PRICELESS_SLUG, symbol: 'ZERO', priceUsd: 0, percentChange24h: 0 },
  },
} as unknown as GlobalState['tokenInfo'];

const BALANCES: ApiBalanceBySlug = {
  [TONCOIN.slug]: 3n * ONE_TON / 2n, // 1.5 TON -> $7.5
  [STAKED_TON_SLUG]: 2n * ONE_TON, // ignored: the staked jetton is counted via the staking state
  [USDT_SLUG]: 1234n * ONE_USDT / 100n, // 12.34 USDT -> $12.34
  [DELETED_SLUG]: ONE_TON, // ignored: deleted by the user
  [UNKNOWN_SLUG]: 5n * ONE_TON, // ignored: no token info
  [PRICELESS_SLUG]: 7n * ONE_TON, // $0
};

const STAKING_STATES: ApiStakingState[] = [
  { ...DEFAULT_STAKING_STATE, balance: 2n * ONE_TON }, // 2 TON staked -> $10
];

const SETTINGS: AccountSettings = { deletedSlugs: [DELETED_SLUG] };
const CURRENCY_RATES = { ...INITIAL_STATE.currencyRates, USD: RATE } as ApiCurrencyRates;

describe('calculateTotalBalanceValue', () => {
  it('matches `calculateFullBalance` over the account token list', () => {
    const tokens = selectAccountTokensMemoizedFor(ACCOUNT_ID)(
      BALANCES, TOKEN_INFO, SETTINGS, false, 'USD', CURRENCY_RATES, true,
    );
    const expected = calculateFullBalance(tokens, STAKING_STATES, RATE);
    const actual = calculateTotalBalanceValue(BALANCES, TOKEN_INFO, SETTINGS.deletedSlugs, STAKING_STATES, RATE);

    expect(actual).toEqual({
      primaryValue: expected.primaryValue,
      primaryWholePart: expected.primaryWholePart,
      primaryFractionPart: expected.primaryFractionPart,
    });
    // (7.5 + 10 + 12.34) * 0.9
    expect(actual.primaryValue).toBe('26.856');
  });

  it('yields zero without balances', () => {
    expect(calculateTotalBalanceValue(undefined, TOKEN_INFO, undefined).primaryValue).toBe('0');
    expect(calculateFullBalance(undefined).primaryValue).toBe('0');
  });
});
