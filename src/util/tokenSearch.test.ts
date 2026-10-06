import type { UserSwapToken } from '../global/types';
import type { LangFn } from './langProvider';

import { TON_USDT_MAINNET, TRC20_USDT_MAINNET } from '../config';
import { findTokensByQuery } from './tokenSearch';

const lang = ((key: string) => key) as unknown as LangFn;

function makeToken(slug: string, overrides: Partial<UserSwapToken> = {}): UserSwapToken {
  return {
    slug,
    name: slug,
    symbol: slug.toUpperCase(),
    chain: 'ethereum',
    amount: 0n,
    price: 0,
    priceUsd: 0,
    decimals: 18,
    totalValue: '0',
    isPopular: false,
    ...overrides,
  };
}

function findSlugs(tokens: UserSwapToken[], query: string, trackedSlugs?: string[]) {
  return findTokensByQuery(lang, tokens, query, trackedSlugs).map(({ slug }) => slug);
}

it('ranks an exact slug, then an exact name, then a name prefix, then a substring', () => {
  const tokens = [
    makeToken('robinhood-coin', { name: 'Coinbase', symbol: 'COIN', chain: 'robinhood' }),
    makeToken('ethereum-based1', { name: 'Based one', symbol: 'BASED1' }),
    makeToken('base-cbeth', { name: 'Coinbase Wrapped Staked ETH', symbol: 'cbETH', chain: 'base', label: 'Base' }),
    makeToken('base', { name: 'Ethereum', symbol: 'ETH', chain: 'base', label: 'Base' }),
  ];

  expect(findSlugs(tokens, 'Base')).toEqual(['base', 'base-cbeth', 'ethereum-based1', 'robinhood-coin']);
});

it('puts held, then tracked, then popular tokens first among equal matches', () => {
  const tokens = [
    makeToken('a-usdt', { symbol: 'USDT' }),
    makeToken('b-usdt', { symbol: 'USDT', isPopular: true }),
    makeToken('c-usdt', { symbol: 'USDT' }),
    makeToken('d-usdt', { symbol: 'USDT', amount: 1n }),
  ];

  expect(findSlugs(tokens, 'usdt', ['c-usdt'])).toEqual(['d-usdt', 'c-usdt', 'b-usdt', 'a-usdt']);
});

it('puts trusted USDT in the display chain order above an equally relevant held look-alike', () => {
  const tokens = [
    makeToken('ton-lookalike', { symbol: 'USDT', chain: 'ton', amount: 1n }),
    makeToken(TRC20_USDT_MAINNET.slug, { symbol: 'USDT', chain: 'tron' }),
    makeToken(TON_USDT_MAINNET.slug, { symbol: 'USDT', chain: 'ton' }),
    makeToken('toncoin', { name: 'Toncoin', symbol: 'TON', chain: 'ton' }),
  ];

  expect(findSlugs(tokens, 'usdt')).toEqual([TON_USDT_MAINNET.slug, TRC20_USDT_MAINNET.slug, 'ton-lookalike']);
  expect(findSlugs(tokens, 'ton')[0]).toBe('toncoin');
});

it('breaks full ties by slug', () => {
  const tokens = ['c-dai', 'a-dai', 'b-dai'].map((slug) => makeToken(slug, { symbol: 'DAI' }));

  expect(findSlugs(tokens, 'dai')).toEqual(['a-dai', 'b-dai', 'c-dai']);
});

it('recovers one typo, including in the leading characters', () => {
  const tokens = [makeToken('bitcoin', { name: 'Bitcoin', symbol: 'BTC' })];

  expect(findSlugs(tokens, 'xitcoin')).toEqual(['bitcoin']);
  expect(findSlugs(tokens, 'bitcon')).toEqual(['bitcoin']);
  expect(findSlugs(tokens, 'bitcoiin')).toEqual(['bitcoin']);
  expect(findSlugs(tokens, 'bitocin')).toEqual([]);
});

it('requires stop words of a multiword query to match whole words', () => {
  const tokens = [
    makeToken('toncoin', { name: 'Toncoin', symbol: 'TON', chain: 'ton' }),
    makeToken('isle', { name: 'Isle', symbol: 'ISL' }),
  ];

  expect(findSlugs(tokens, 'what is toncoin')).toEqual(['toncoin']);
  expect(findSlugs(tokens, 'is')).toEqual(['isle']);
});

it('matches a long unbroken query only as an exact address', () => {
  const address = 'EQBynBO23ywHy_CgarY9NK9FTz0yDsG82PtcbSTQgGoXwiuA';
  const tokens = [makeToken('ton-jetton', { name: 'Jetton', chain: 'ton', tokenAddress: address })];

  expect(findSlugs(tokens, address)).toEqual(['ton-jetton']);
  expect(findSlugs(tokens, address.slice(0, 30))).toEqual([]);
});

it('matches Cyrillic queries through transliteration', () => {
  const tokens = [
    makeToken('toncoin', { name: 'Toncoin', symbol: 'TON', chain: 'ton' }),
    makeToken('bitcoin', { name: 'Bitcoin', symbol: 'BTC' }),
  ];

  expect(findSlugs(tokens, 'тон')).toEqual(['toncoin']);
  expect(findSlugs(tokens, 'биткоин')).toEqual(['bitcoin']);
});

it('finds nothing for a query without letters or digits', () => {
  expect(findSlugs([makeToken('toncoin')], ' $ ')).toEqual([]);
});
