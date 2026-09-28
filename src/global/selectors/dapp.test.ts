import type { ApiBaseCurrency, ApiCurrencyRates, ApiTokenWithPrice } from '../../api/types';

import { STON_PTON_SLUG, TONCOIN } from '../../config';
import { INITIAL_STATE } from '../initialState';
import { selectDappTransferTotalInBaseCurrency } from './dapp';

const USDT_SLUG = 'ton-eqcxe6mutq';
const ONE_TON = 1_000_000_000n; // 1 TON, 9 decimals
const ONE_USDT = 1_000_000n; // 1 USDT, 6 decimals

const TOKENS_BY_SLUG = {
  [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 0 },
  [USDT_SLUG]: { ...TONCOIN, slug: USDT_SLUG, symbol: 'USD₮', decimals: 6, priceUsd: 1, percentChange24h: 0 },
} as unknown as Record<string, ApiTokenWithPrice>;

const CURRENCY_RATES = { ...INITIAL_STATE.currencyRates, USD: '1', EUR: '0.5' } as ApiCurrencyRates;
const USD: ApiBaseCurrency = 'USD';

describe('selectDappTransferTotalInBaseCurrency', () => {
  it('sums up every token of the request', () => {
    const total = selectDappTransferTotalInBaseCurrency(
      { [TONCOIN.slug]: 2n * ONE_TON, [USDT_SLUG]: 3n * ONE_USDT },
      TOKENS_BY_SLUG,
      USD,
      CURRENCY_RATES,
    );

    expect(total).toBe('13');
  });

  it('converts the total into the base currency', () => {
    const total = selectDappTransferTotalInBaseCurrency(
      { [TONCOIN.slug]: ONE_TON },
      TOKENS_BY_SLUG,
      'EUR',
      CURRENCY_RATES,
    );

    expect(total).toBe('2.5');
  });

  it('skips tokens with an unknown price', () => {
    const tokensBySlug = {
      ...TOKENS_BY_SLUG,
      [USDT_SLUG]: { ...TOKENS_BY_SLUG[USDT_SLUG], priceUsd: undefined },
    } as unknown as Record<string, ApiTokenWithPrice>;

    const total = selectDappTransferTotalInBaseCurrency(
      { [TONCOIN.slug]: ONE_TON, [USDT_SLUG]: 1000n * ONE_USDT },
      tokensBySlug,
      USD,
      CURRENCY_RATES,
    );

    expect(total).toBe('5');
  });

  it('does not count pTON on top of the Toncoin it wraps', () => {
    const tokensBySlug = {
      ...TOKENS_BY_SLUG,
      [STON_PTON_SLUG]: { ...TOKENS_BY_SLUG[TONCOIN.slug], slug: STON_PTON_SLUG },
    } as unknown as Record<string, ApiTokenWithPrice>;

    const total = selectDappTransferTotalInBaseCurrency(
      { [TONCOIN.slug]: ONE_TON, [STON_PTON_SLUG]: ONE_TON },
      tokensBySlug,
      USD,
      CURRENCY_RATES,
    );

    expect(total).toBe('5');
  });

  it('returns nothing when the total is not above half a dollar', () => {
    const total = selectDappTransferTotalInBaseCurrency(
      { [TONCOIN.slug]: ONE_TON / 10n },
      TOKENS_BY_SLUG,
      USD,
      CURRENCY_RATES,
    );

    expect(total).toBeUndefined();
  });

  it('returns nothing when no token has a known price', () => {
    const total = selectDappTransferTotalInBaseCurrency({ 'ton-nft': 1n }, TOKENS_BY_SLUG, USD, CURRENCY_RATES);

    expect(total).toBeUndefined();
  });
});
