import type { ApiTokenWithPrice } from '../types';

import { callBackendGet } from './backend';
import {
  buildTokenSlug,
  getTokenByAddress,
  getTokensCache,
  pauseTokenUpdates,
  pickTokensForDetails,
  resetLastTokens,
  resumeTokenUpdates,
  sendUpdateTokens,
  tokensPreload,
  updateTokens,
  updateTokensFromBackend,
} from './tokens';

jest.mock('../db', () => ({
  tokenRepository: {
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));

jest.mock('./backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));

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
    expect(pickTokensForDetails(allTokens, { backendSlugs, heldSlugs, maxCount: 100 }))
      .toEqual([held, unclassifiedLp]);
  });

  it('keeps requesting every non-published token when the held ones are unknown', () => {
    expect(pickTokensForDetails(allTokens, { backendSlugs, maxCount: 100 }))
      .toEqual([held, abandoned, unclassifiedLp]);
  });

  it('requests a token the backend used to publish but stopped', () => {
    const delisted = { ...published, slug: 'ton-delisted', tokenAddress: 'EQDelisted' };

    expect(pickTokensForDetails([delisted], { backendSlugs, maxCount: 100 }))
      .toEqual([delisted]);
  });

  it('skips a locally imported token once the backend starts publishing it', () => {
    const adopted = makeToken(published.slug, 'ton', 'EQAdopted');

    expect(pickTokensForDetails([adopted], { backendSlugs, maxCount: 100 })).toEqual([]);
  });

  it('never exceeds the cap', () => {
    expect(pickTokensForDetails(allTokens, { backendSlugs, maxCount: 1 }))
      .toEqual([held]);
  });
});

describe('token updates', () => {
  beforeEach(pauseTokenUpdates);

  it('only sends repeated updates when explicitly requested', async () => {
    const cache = getTokensCache();
    const slug = 'ton-event-storm-regression';
    const token = makeToken(slug, 'ton', 'EQEventStormRegression');
    const previousToken = cache.bySlug[slug];
    const sendUpdate = jest.fn();

    delete cache.bySlug[slug];

    try {
      await updateTokens([token], sendUpdate);
      expect(sendUpdate).toHaveBeenCalledTimes(1);

      sendUpdate.mockClear();
      await updateTokens([{ ...token, name: 'Updated name' }], sendUpdate);
      expect(sendUpdate).not.toHaveBeenCalled();

      await updateTokens([{ ...token, codeHash: 'hash' }], sendUpdate, [], true);
      expect(sendUpdate).toHaveBeenCalledTimes(1);
    } finally {
      if (previousToken) {
        cache.bySlug[slug] = previousToken;
      } else {
        delete cache.bySlug[slug];
      }
    }
  });

  it('keeps updates paused while the initial backend update is unavailable', () => {
    const onUpdate = jest.fn();

    sendUpdateTokens(onUpdate);

    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('coalesces updates until the initial backend update succeeds', () => {
    const firstOnUpdate = jest.fn();
    const latestOnUpdate = jest.fn();

    sendUpdateTokens(firstOnUpdate);
    sendUpdateTokens(latestOnUpdate);

    expect(firstOnUpdate).not.toHaveBeenCalled();
    expect(latestOnUpdate).not.toHaveBeenCalled();

    resumeTokenUpdates();

    expect(firstOnUpdate).not.toHaveBeenCalled();
    expect(latestOnUpdate).toHaveBeenCalledTimes(1);
    expect(latestOnUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'updateTokens',
      kind: 'fromCache',
    }));
  });

  it('sends updates immediately after the initial backend update succeeds', () => {
    const onUpdate = jest.fn();
    resumeTokenUpdates();

    sendUpdateTokens(onUpdate);

    expect(onUpdate).toHaveBeenCalledTimes(1);
  });

  it('sends only the tokens changed since the previous fresh-price update', async () => {
    const onUpdate = jest.fn();
    const cache = getTokensCache();
    const slug = buildTokenSlug('ton', 'delta-token');
    const lastTokens = () => onUpdate.mock.calls[onUpdate.mock.calls.length - 1][0].tokens;

    tokensPreload.resolve();
    resumeTokenUpdates();
    await updateTokens([makeToken(slug, 'ton', 'delta-token', { priceUsd: 1 })]);
    await updateTokensFromBackend(onUpdate);
    expect(lastTokens()).toBe(cache.bySlug);
    expect(onUpdate.mock.calls[0][0].kind).toBe('full');

    onUpdate.mockClear();
    await updateTokens(
      [makeToken(slug, 'ton', 'delta-token', { priceUsd: 2 })],
      () => sendUpdateTokens(onUpdate),
      [],
      true,
    );
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(Object.keys(lastTokens())).toEqual([slug]);
    expect(onUpdate.mock.calls[0][0].kind).toBe('partial');

    onUpdate.mockClear();
    sendUpdateTokens(onUpdate);
    expect(onUpdate).not.toHaveBeenCalled();

    resetLastTokens();
    sendUpdateTokens(onUpdate);
    expect(lastTokens()).toBe(cache.bySlug);
    expect(onUpdate.mock.calls[0][0].kind).toBe('full');
  });

  it('sends removed token slugs in partial updates', async () => {
    const onUpdate = jest.fn();
    const cache = getTokensCache();
    const slug = buildTokenSlug('ton', 'removed-token');
    const previousToken = cache.bySlug[slug];

    try {
      tokensPreload.resolve();
      resumeTokenUpdates();
      await updateTokens([makeToken(slug, 'ton', 'removed-token')]);
      await updateTokensFromBackend(onUpdate);
      onUpdate.mockClear();
      delete cache.bySlug[slug];

      sendUpdateTokens(onUpdate);

      expect(onUpdate).toHaveBeenCalledWith({
        type: 'updateTokens',
        kind: 'partial',
        tokens: {},
        removedSlugs: [slug],
      });
    } finally {
      if (previousToken) {
        cache.bySlug[slug] = previousToken;
      } else {
        delete cache.bySlug[slug];
      }
      resetLastTokens();
    }
  });
});

describe('token updates across a UI reconnect', () => {
  const cache = getTokensCache();
  const slug = buildTokenSlug('ton', 'reconnect-token');
  const previousToken = cache.bySlug[slug];
  const closedOnUpdate = jest.fn();
  const onUpdate = jest.fn();
  const respond = (index: number, priceUsd: number) => {
    resolvers[index]([makeToken(slug, 'ton', 'reconnect-token', { priceUsd })]);
  };
  let resolvers: ((tokens: ApiTokenWithPrice[]) => void)[];
  let closedRequest: Promise<void>;
  let request: Promise<void>;

  beforeEach(() => {
    resolvers = [];
    (callBackendGet as jest.Mock).mockImplementation(() => new Promise((resolve) => resolvers.push(resolve)));
    tokensPreload.resolve();
    pauseTokenUpdates();
    closedRequest = updateTokensFromBackend(closedOnUpdate);
    pauseTokenUpdates();
    request = updateTokensFromBackend(onUpdate);
  });

  afterEach(() => {
    (callBackendGet as jest.Mock).mockResolvedValue([]);
    closedOnUpdate.mockClear();
    onUpdate.mockClear();
    if (previousToken) {
      cache.bySlug[slug] = previousToken;
    } else {
      delete cache.bySlug[slug];
    }
    resetLastTokens();
  });

  it('sends the full list to the new UI when the request of the closed one finishes first', async () => {
    respond(0, 1);
    await closedRequest;
    resumeTokenUpdates();
    respond(1, 1);
    await request;
    resumeTokenUpdates();

    expect(closedOnUpdate).not.toHaveBeenCalled();
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate.mock.calls[0][0].kind).toBe('full');
  });

  it('drops the response of the closed UI request when it arrives after the current one', async () => {
    respond(1, 2);
    await request;
    resumeTokenUpdates();
    respond(0, 1);
    await closedRequest;
    resumeTokenUpdates();
    sendUpdateTokens(onUpdate);

    expect(closedOnUpdate).not.toHaveBeenCalled();
    expect(cache.bySlug[slug].priceUsd).toBe(2);
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate.mock.calls[0][0].tokens[slug].priceUsd).toBe(2);
  });
});
