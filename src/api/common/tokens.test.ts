import type { ApiTokenWithPrice } from '../types';

import { buildTokenDetailsPayload, buildTokenSlug, getTokenByAddress, getTokensCache } from './tokens';

function makeToken(
  slug: string,
  chain: ApiTokenWithPrice['chain'],
  tokenAddress: string,
  rest?: Partial<ApiTokenWithPrice>,
): ApiTokenWithPrice {
  return {
    slug,
    chain,
    tokenAddress,
    name: slug,
    symbol: slug.toUpperCase(),
    decimals: 18,
    priceUsd: 0,
    percentChange24h: 0,
    ...rest,
  };
}

describe('token lookup', () => {
  it('does not resolve a chainless address when multiple cached tokens share it', () => {
    const cache = getTokensCache();
    const address = '0x00000000000000000000000000000000ABCDEF12';
    const ethereumSlug = buildTokenSlug('ethereum', address);
    const baseSlug = buildTokenSlug('base', address);
    const previousEthereumToken = cache.bySlug[ethereumSlug];
    const previousBaseToken = cache.bySlug[baseSlug];

    cache.bySlug[ethereumSlug] = makeToken(ethereumSlug, 'ethereum', address.toLowerCase());
    cache.bySlug[baseSlug] = makeToken(baseSlug, 'base', address.toUpperCase());

    try {
      expect(getTokenByAddress(address)).toBeUndefined();
      expect(getTokenByAddress(address, 'ethereum')?.slug).toBe(ethereumSlug);
      expect(getTokenByAddress(address, 'base')?.slug).toBe(baseSlug);
    } finally {
      if (previousEthereumToken) {
        cache.bySlug[ethereumSlug] = previousEthereumToken;
      } else {
        delete cache.bySlug[ethereumSlug];
      }

      if (previousBaseToken) {
        cache.bySlug[baseSlug] = previousBaseToken;
      } else {
        delete cache.bySlug[baseSlug];
      }
    }
  });
});

describe('token details payload', () => {
  const held = makeToken('ton-held', 'ton', 'EQHeld');
  const abandoned = makeToken('ton-abandoned', 'ton', 'EQAbandoned');
  const lp = makeToken('ton-lp', 'ton', 'EQLp', { type: 'lp_token' });
  const unclassifiedLp = makeToken('ton-lp-new', 'ton', 'EQLpNew');
  const published = makeToken('ton-published', 'ton', 'EQPublished', { isFromBackend: true });
  const native = makeToken('toncoin', 'ton', '', { tokenAddress: undefined });

  const backendSlugs = new Set([published.slug]);
  const heldSlugs = new Set([held.slug, lp.slug, unclassifiedLp.slug, native.slug]);
  const allTokens = [held, abandoned, lp, unclassifiedLp, published, native];

  it('requests the held tokens only, LP aside', () => {
    expect(buildTokenDetailsPayload(allTokens, { backendSlugs, heldSlugs, maxCount: 100 }))
      .toEqual([held.tokenAddress, unclassifiedLp.tokenAddress]);
  });

  it('keeps requesting every non-published token when the held ones are unknown', () => {
    expect(buildTokenDetailsPayload(allTokens, { backendSlugs, maxCount: 100 }))
      .toEqual([held.tokenAddress, abandoned.tokenAddress, unclassifiedLp.tokenAddress]);
  });

  it('requests a token the backend used to publish but stopped', () => {
    const delisted = { ...published, slug: 'ton-delisted', tokenAddress: 'EQDelisted' };

    expect(buildTokenDetailsPayload([delisted], { backendSlugs, maxCount: 100 }))
      .toEqual([delisted.tokenAddress]);
  });

  it('skips a locally imported token once the backend starts publishing it', () => {
    const adopted = makeToken(published.slug, 'ton', 'EQAdopted');

    expect(buildTokenDetailsPayload([adopted], { backendSlugs, maxCount: 100 })).toEqual([]);
  });

  it('never exceeds the cap', () => {
    expect(buildTokenDetailsPayload(allTokens, { backendSlugs, maxCount: 1 }))
      .toEqual([held.tokenAddress]);
  });
});
