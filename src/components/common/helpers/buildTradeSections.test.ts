import type { UserSwapToken } from '../../../global/types';

import { buildTradeSections } from './buildTradeSections';

const STABLE_SLUGS = new Set(['tron-usdt', 'ton-usdt']);
const isStablecoin = (slug: string) => STABLE_SLUGS.has(slug);

function makeToken(slug: string, amount: bigint, totalValue: string, isPopular = false): UserSwapToken {
  return {
    slug,
    amount,
    totalValue,
    isPopular,
    symbol: slug,
    name: slug,
    price: 0,
    priceUsd: 0,
    decimals: 9,
    chain: 'ton',
  };
}

const usdtTron = makeToken('tron-usdt', 500n, '500');
const bitcoin = makeToken('bitcoin', 1n, '648');
const ton = makeToken('toncoin', 0n, '0', true);
const usdtTon = makeToken('ton-usdt', 0n, '0', true);
const ethereum = makeToken('ethereum', 0n, '0', true);
const solana = makeToken('solana', 0n, '0');

const userTokens = [usdtTron, ton, bitcoin];
const popularTokens = [ton, usdtTon, ethereum];
const swapTokens = [usdtTron, ton, usdtTon, ethereum, bitcoin, solana];

function slugs(tokens: UserSwapToken[]) {
  return tokens.map((token) => token.slug);
}

describe('buildTradeSections', () => {
  it('lists the owned tokens by value and the rest by name when selling', () => {
    const sections = buildTradeSections({
      direction: 'sell', category: 'all', userTokens, popularTokens, swapTokens, isStablecoin,
    });

    expect(slugs(sections.my)).toEqual(['bitcoin', 'tron-usdt']);
    expect(slugs(sections.stablecoins)).toEqual(['ton-usdt']);
    expect(slugs(sections.tokens)).toEqual(['ethereum', 'toncoin']);
  });

  it('leaves the traded token out of every section', () => {
    const sections = buildTradeSections({
      direction: 'sell',
      category: 'all',
      screenTokenSlug: 'toncoin',
      userTokens: [...userTokens, makeToken('toncoin', 5n, '20', true)],
      popularTokens,
      swapTokens,
      isStablecoin,
    });

    expect(slugs(sections.my)).toEqual(['bitcoin', 'tron-usdt']);
    expect(slugs(sections.tokens)).toEqual(['ethereum']);
  });

  it('lists only the owned tokens when buying', () => {
    const sections = buildTradeSections({
      direction: 'buy', category: 'all', userTokens, popularTokens, swapTokens, isStablecoin,
    });

    expect(slugs(sections.my)).toEqual(['bitcoin', 'tron-usdt']);
    expect(sections.stablecoins).toEqual([]);
    expect(sections.tokens).toEqual([]);
  });

  it('keeps only the fiat section on the fiat tab', () => {
    const sections = buildTradeSections({
      direction: 'sell', category: 'fiat', userTokens, popularTokens, swapTokens, isStablecoin,
    });

    expect(sections.my).toEqual([]);
    expect(sections.stablecoins).toEqual([]);
    expect(sections.tokens).toEqual([]);
  });

  it('narrows the owned tokens to stablecoins on the stablecoins tab', () => {
    const sections = buildTradeSections({
      direction: 'sell', category: 'stablecoins', userTokens, popularTokens, swapTokens, isStablecoin,
    });

    expect(slugs(sections.my)).toEqual(['tron-usdt']);
    expect(slugs(sections.stablecoins)).toEqual(['ton-usdt']);
    expect(sections.tokens).toEqual([]);
  });

  it('folds stablecoins into the popular tokens on the tokens tab', () => {
    const sections = buildTradeSections({
      direction: 'sell', category: 'tokens', userTokens, popularTokens, swapTokens, isStablecoin,
    });

    expect(slugs(sections.my)).toEqual(['bitcoin', 'tron-usdt']);
    expect(sections.stablecoins).toEqual([]);
    expect(slugs(sections.tokens)).toEqual(['ethereum', 'ton-usdt', 'toncoin']);
  });

  it('lists every match in the search order when searching', () => {
    const matches = [solana, usdtTon, ton, usdtTron, bitcoin];
    const sections = buildTradeSections({
      direction: 'sell',
      category: 'all',
      userTokens: [usdtTron, bitcoin],
      popularTokens: matches,
      swapTokens: matches,
      isStablecoin,
      isSearch: true,
    });

    expect(slugs(sections.my)).toEqual(['tron-usdt', 'bitcoin']);
    expect(slugs(sections.stablecoins)).toEqual(['ton-usdt']);
    expect(slugs(sections.tokens)).toEqual(['solana', 'toncoin']);
  });
});
