import type { ApiTokenWithPrice } from '../types';

import { getChainConfig, getSupportedChains } from '../../util/chain';
import { tokenRepository } from '../db';
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
  waitForTokenSlugResolver,
} from './tokens';
import { onTokenSlugsMove } from './tokenSlugMoves';

jest.mock('../db', () => ({
  tokenRepository: {
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));

jest.mock('./backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));

// The catalog lists AUSD under `ethereum-0x00000000`, the backend slug of every address that starts with eight zeros
const AUSD_SLUG = 'ethereum-0x00000000';
const AUSD_ADDRESS = '0x00000000efe302beaa2b3e6e1b18d08d69a9012a';
const SPAM_ADDRESS = '0x00000000f9fd50c832d79facfe6f4e8ce90a5efb';
const SPAM_SLUG = `ethereum-${SPAM_ADDRESS}`;
const OTHER_SPAM_ADDRESS = '0x0000000000c39a0f674c12a5e63eb8031b550b6f';
const OTHER_SPAM_SLUG = `ethereum-${OTHER_SPAM_ADDRESS}`;

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
  it.each([false, true])('does not resolve an address shared across chains (same-chain alias: %s)', (hasAlias) => {
    const cache = getTokensCache();
    const address = '0x00000000000000000000000000000000ABCDEF12';
    const ethereumSlug = buildTokenSlug('ethereum', address);
    const baseSlug = buildTokenSlug('base', address);
    const aliasSlug = `ethereum-${address.toLowerCase()}`;
    const previousEthereumToken = cache.bySlug[ethereumSlug];
    const previousBaseToken = cache.bySlug[baseSlug];
    const previousAliasToken = cache.bySlug[aliasSlug];

    cache.bySlug[ethereumSlug] = makeToken(ethereumSlug, 'ethereum', address.toLowerCase());
    cache.bySlug[baseSlug] = makeToken(baseSlug, 'base', address.toUpperCase());
    if (hasAlias) cache.bySlug[aliasSlug] = makeToken(aliasSlug, 'ethereum', address.toUpperCase());

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

      if (previousAliasToken) {
        cache.bySlug[aliasSlug] = previousAliasToken;
      } else {
        delete cache.bySlug[aliasSlug];
      }
    }
  });

  it('resolves a token cached only under its full slug', () => {
    const cache = getTokensCache();
    const token = makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS);
    cache.bySlug[SPAM_SLUG] = token;

    try {
      expect(getTokenByAddress(SPAM_ADDRESS)).toBe(token);
    } finally {
      delete cache.bySlug[SPAM_SLUG];
    }
  });

  it.each([false, true])('chooses the canonical token among same-chain aliases (alias first: %s)', (isAliasFirst) => {
    const cache = getTokensCache();
    const canonicalToken = makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, { priceUsd: 2 });
    const aliasToken = makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS.toUpperCase(), { priceUsd: 1 });
    const tokens = isAliasFirst ? [aliasToken, canonicalToken] : [canonicalToken, aliasToken];
    for (const token of tokens) cache.bySlug[token.slug] = token;

    try {
      expect(getTokenByAddress(SPAM_ADDRESS)).toBe(canonicalToken);
      expect(getTokenByAddress(SPAM_ADDRESS, 'ethereum')).toBe(canonicalToken);
    } finally {
      delete cache.bySlug[AUSD_SLUG];
      delete cache.bySlug[SPAM_SLUG];
    }
  });
});

describe('token slugs', () => {
  const cache = getTokensCache();
  const ausd = makeToken(AUSD_SLUG, 'ethereum', AUSD_ADDRESS, { symbol: 'AUSD', decimals: 6, isFromBackend: true });

  afterEach(() => {
    delete cache.bySlug[AUSD_SLUG];
    delete cache.bySlug[SPAM_SLUG];
    delete cache.bySlug[OTHER_SPAM_SLUG];
  });

  it('keeps the slug of every config token', () => {
    const tokens = getSupportedChains().flatMap((chain) => getChainConfig(chain).tokenInfo)
      .filter((token) => token.tokenAddress);

    expect(tokens.map((token) => buildTokenSlug(token.chain, token.tokenAddress!)))
      .toEqual(tokens.map((token) => token.slug));
  });

  it('gives an address its full slug when another token holds its backend slug', () => {
    cache.bySlug[ausd.slug] = ausd;

    expect(buildTokenSlug('ethereum', SPAM_ADDRESS)).toBe(SPAM_SLUG);
    expect(buildTokenSlug('ethereum', AUSD_ADDRESS.toUpperCase())).toBe(AUSD_SLUG);
    expect(getTokenByAddress(SPAM_ADDRESS, 'ethereum')).toBeUndefined();
  });

  it('builds a lower-case slug whatever the case of the chain', () => {
    expect(buildTokenSlug('Ethereum' as ApiTokenWithPrice['chain'], AUSD_ADDRESS)).toBe(AUSD_SLUG);
  });

  it.each([false, true])('gives the backend slug to the smallest address found together (reversed: %s)', async (
    isReversed,
  ) => {
    const resolveTokenSlugs = await waitForTokenSlugResolver();
    const addresses = [SPAM_ADDRESS, OTHER_SPAM_ADDRESS, SPAM_ADDRESS.toUpperCase()];
    if (isReversed) addresses.reverse();

    const slugs = resolveTokenSlugs(addresses.map((address) => ({ chain: 'ethereum', address })));

    expect(Object.fromEntries(addresses.map((address, i) => [address, slugs[i]]))).toEqual({
      [SPAM_ADDRESS]: SPAM_SLUG,
      [SPAM_ADDRESS.toUpperCase()]: SPAM_SLUG,
      [OTHER_SPAM_ADDRESS]: AUSD_SLUG,
    });
  });

  it('moves the token found first to its full slug when the catalog gives that slug to another token', async () => {
    await updateTokens([makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, {
      symbol: 'POL', priceUsd: 5, isPriceFromBackend: true,
    })]);
    await updateTokens([ausd]);

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ tokenAddress: AUSD_ADDRESS, symbol: 'AUSD', decimals: 6 });
    expect(cache.bySlug[SPAM_SLUG]).toMatchObject({
      tokenAddress: SPAM_ADDRESS, symbol: 'POL', decimals: 18, isPriceFromBackend: false,
    });
    expect(tokenRepository.bulkPut).toHaveBeenLastCalledWith([
      expect.objectContaining({ slug: SPAM_SLUG }),
      expect.objectContaining({ slug: AUSD_SLUG }),
    ]);

    await updateTokens([makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS, { priceUsd: 7 })]);
    expect(cache.bySlug[SPAM_SLUG]).toMatchObject({ priceUsd: 7 });
  });

  it('keeps one holder of a slug the catalog gives to two tokens, whatever their order', async () => {
    const other = makeToken(AUSD_SLUG, 'ethereum', OTHER_SPAM_ADDRESS, { symbol: 'OTHER', isFromBackend: true });

    await updateTokens([ausd, other]);
    await updateTokens([other, ausd]);

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ tokenAddress: OTHER_SPAM_ADDRESS });
    expect(cache.bySlug[`ethereum-${AUSD_ADDRESS}`]).toMatchObject({ tokenAddress: AUSD_ADDRESS });
    delete cache.bySlug[`ethereum-${AUSD_ADDRESS}`];
  });

  it('gives the slug to the token the catalog lists now when it no longer lists the holder', async () => {
    const onMove = jest.fn();
    const removeMoveListener = onTokenSlugsMove(onMove);
    // The smaller address key, which keeps the slug only while the catalog lists both
    const delisted = makeToken(AUSD_SLUG, 'ethereum', OTHER_SPAM_ADDRESS, {
      symbol: 'OLD', priceUsd: 5, isFromBackend: true, isPriceFromBackend: true,
    });

    try {
      await updateTokens([delisted]);
      await updateTokens([ausd]);
    } finally {
      removeMoveListener();
    }

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ tokenAddress: AUSD_ADDRESS, symbol: 'AUSD' });
    expect(cache.bySlug[OTHER_SPAM_SLUG])
      .toMatchObject({ tokenAddress: OTHER_SPAM_ADDRESS, isPriceFromBackend: false });
    expect(onMove).toHaveBeenCalledWith([AUSD_SLUG]);

    await updateTokens([makeToken(OTHER_SPAM_SLUG, 'ethereum', OTHER_SPAM_ADDRESS, { priceUsd: 7 })]);
    expect(cache.bySlug[OTHER_SPAM_SLUG]).toMatchObject({ priceUsd: 7 });
  });

  it('asks no details for a token whose backend slug belongs to another token', () => {
    const spam = makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS);

    expect(pickTokensForDetails([spam], { backendSlugs: new Set([AUSD_SLUG]), maxCount: 100 })).toEqual([]);
  });
});

describe('token details payload', () => {
  const held = makeToken(buildTokenSlug('ton', 'EQHeld'), 'ton', 'EQHeld');
  const abandoned = makeToken(buildTokenSlug('ton', 'EQAbandoned'), 'ton', 'EQAbandoned');
  const lp = makeToken(buildTokenSlug('ton', 'EQLp'), 'ton', 'EQLp', { type: 'lp_token' });
  const unclassifiedLp = makeToken(buildTokenSlug('ton', 'EQLpNew'), 'ton', 'EQLpNew');
  const published = makeToken(buildTokenSlug('ton', 'EQPublished'), 'ton', 'EQPublished', { isFromBackend: true });
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
    const delisted = { ...published, slug: buildTokenSlug('ton', 'EQDelisted'), tokenAddress: 'EQDelisted' };

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
