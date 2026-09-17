import type { ApiTokenWithPrice } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { updateTokens } from './misc';

function makeToken(slug: string, priceUsd: number): ApiTokenWithPrice {
  return {
    slug,
    name: slug,
    symbol: slug.toUpperCase(),
    decimals: 9,
    chain: 'ton',
    priceUsd,
    percentChange24h: priceUsd,
  };
}

function makeGlobal(tokens: ApiTokenWithPrice[]): GlobalState {
  return {
    ...INITIAL_STATE,
    tokenInfo: {
      bySlug: Object.fromEntries(tokens.map((token) => [token.slug, token])),
    },
  };
}

describe('updateTokens', () => {
  it('merges partial updates and applies explicit removals', () => {
    const retained = makeToken('retained', 1);
    const changed = makeToken('changed', 1);
    const removed = makeToken('removed', 1);
    const incoming = makeToken('changed', 2);

    const global = updateTokens(
      makeGlobal([retained, changed, removed]),
      { [incoming.slug]: incoming },
      'partial',
      [removed.slug],
    );

    expect(global.tokenInfo.bySlug).toEqual({
      [retained.slug]: retained,
      [incoming.slug]: incoming,
    });
  });

  it('keeps the global for a partial update that changes nothing', () => {
    const retained = makeToken('retained', 1);
    const global = makeGlobal([retained]);

    expect(updateTokens(global, { [retained.slug]: { ...retained } }, 'partial', ['absent'], true)).toBe(global);
    expect(updateTokens(global, {}, 'partial', [retained.slug], true)).not.toBe(global);
    expect(updateTokens(global, { [retained.slug]: makeToken('retained', 2) }, 'partial', [], true)).not.toBe(global);
  });

  it('replaces the token map for full updates', () => {
    const omitted = makeToken('omitted', 1);
    const incoming = makeToken('incoming', 2);

    const global = updateTokens(makeGlobal([omitted]), { [incoming.slug]: incoming }, 'full');

    expect(global.tokenInfo.bySlug).toEqual({ [incoming.slug]: incoming });
  });

  it('replaces the token map but preserves existing prices for cache updates', () => {
    const cached = makeToken('cached', 1);
    const omitted = makeToken('omitted', 1);
    const incoming = makeToken('cached', 2);

    const global = updateTokens(makeGlobal([cached, omitted]), { [incoming.slug]: incoming }, 'fromCache');

    expect(global.tokenInfo.bySlug).toEqual({ [incoming.slug]: cached });
  });
});
