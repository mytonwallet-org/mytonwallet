import type { ApiCurrencyRates, ApiTokenWithMaybePrice, ApiTokenWithPrice } from '../types';

import { DEFAULT_RETRIES } from '../../config';
import { getChainConfig, getSupportedChains } from '../../util/chain';
import { HOUR } from '../../util/dateFormat';
import Deferred from '../../util/Deferred';
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
  callBackendGet: jest.fn().mockImplementation((path: string) => Promise.resolve(path === '/assets/prices'
    ? { catalogVersion: 'empty', prices: {} }
    : { version: 'empty', assets: [] })),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));

const mockFetch = jest.fn();
jest.mock('../../util/ThrottledFetcher', () => ({
  fetchWithThrottledProvider: (...args: unknown[]) => mockFetch(...args),
  getProviderFetchRetryPolicy: () => undefined,
  getRetryAfterMs: () => undefined,
}));
jest.mock('../../util/abortSignal', () => ({
  ...jest.requireActual('../../util/abortSignal'),
  pauseWithAbortSignal: () => Promise.resolve(),
}));
jest.mock('../environment', () => ({ getEnvironment: () => ({ apiHeaders: {} }) }));
jest.mock('./other', () => ({ getClientId: () => 'token-catalog-test' }));

// The catalog lists AUSD under `ethereum-0x00000000`, the backend slug of every address that starts with eight zeros
const AUSD_SLUG = 'ethereum-0x00000000';
const AUSD_ADDRESS = '0x00000000efe302beaa2b3e6e1b18d08d69a9012a';
const SPAM_ADDRESS = '0x00000000f9fd50c832d79facfe6f4e8ce90a5efb';
const SPAM_SLUG = `ethereum-${SPAM_ADDRESS}`;
const OTHER_SPAM_ADDRESS = '0x0000000000c39a0f674c12a5e63eb8031b550b6f';
const OTHER_SPAM_SLUG = `ethereum-${OTHER_SPAM_ADDRESS}`;
const CURRENCY_RATES: ApiCurrencyRates = { USD: '1', EUR: '0.9', RUB: '90', CNY: '7', BTC: '0.00001', TON: '0.3' };

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
  it.each([false, true])('does not resolve an address shared across chains (same-chain alias: %s)', async (
    hasAlias,
  ) => {
    const cache = getTokensCache();
    const address = '0x00000000000000000000000000000000ABCDEF12';
    const ethereumSlug = buildTokenSlug('ethereum', address);
    const baseSlug = buildTokenSlug('base', address);
    const aliasSlug = `ethereum-${address.toLowerCase()}`;
    const previousEthereumToken = cache.bySlug[ethereumSlug];
    const previousBaseToken = cache.bySlug[baseSlug];
    const previousAliasToken = cache.bySlug[aliasSlug];

    await updateTokens([
      makeToken(ethereumSlug, 'ethereum', address.toLowerCase()),
      makeToken(baseSlug, 'base', address.toUpperCase()),
      ...(hasAlias ? [makeToken(aliasSlug, 'ethereum', address.toUpperCase())] : []),
    ]);

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

  it('resolves a token cached only under its full slug', async () => {
    const cache = getTokensCache();
    await updateTokens([makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS)]);

    try {
      expect(getTokenByAddress(SPAM_ADDRESS)).toBe(cache.bySlug[SPAM_SLUG]);
    } finally {
      delete cache.bySlug[SPAM_SLUG];
    }
  });

  it.each([false, true])('chooses the canonical token among same-chain aliases (alias first: %s)', async (
    isAliasFirst,
  ) => {
    const cache = getTokensCache();
    const canonicalToken = makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, { priceUsd: 2 });
    const aliasToken = makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS.toUpperCase(), { priceUsd: 1 });
    await updateTokens(isAliasFirst ? [aliasToken, canonicalToken] : [canonicalToken, aliasToken]);

    try {
      expect(getTokenByAddress(SPAM_ADDRESS)).toBe(cache.bySlug[AUSD_SLUG]);
      expect(getTokenByAddress(SPAM_ADDRESS, 'ethereum')).toBe(cache.bySlug[AUSD_SLUG]);
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
    // An older copy under the full slug, from a launch where the catalog token held the backend slug
    await updateTokens([makeToken(SPAM_SLUG, 'ethereum', SPAM_ADDRESS, {
      symbol: 'OLD', tokenWalletAddress: '0xWallet',
    })]);
    await updateTokens([makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, {
      symbol: 'POL', priceUsd: 5, isPriceFromBackend: true,
    })]);
    await updateTokens([ausd]);

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ tokenAddress: AUSD_ADDRESS, symbol: 'AUSD', decimals: 6 });
    expect(cache.bySlug[SPAM_SLUG]).toMatchObject({
      tokenAddress: SPAM_ADDRESS,
      symbol: 'POL',
      decimals: 18,
      isPriceFromBackend: false,
      tokenWalletAddress: '0xWallet',
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

  it('keeps the holder of a slug the catalog gives to two tokens and lists on another chain too', async () => {
    const onMove = jest.fn();
    const removeMoveListener = onTokenSlugsMove(onMove);
    const other = makeToken(AUSD_SLUG, 'ethereum', OTHER_SPAM_ADDRESS, { symbol: 'OTHER', isFromBackend: true });
    const otherOnBase = makeToken('base-0x00000000', 'base', OTHER_SPAM_ADDRESS, { isFromBackend: true });

    try {
      await updateTokens([other]);
      await updateTokens([ausd, other, otherOnBase]);
    } finally {
      removeMoveListener();
      delete cache.bySlug[`ethereum-${AUSD_ADDRESS}`];
      delete cache.bySlug[otherOnBase.slug];
    }

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ tokenAddress: OTHER_SPAM_ADDRESS });
    expect(cache.bySlug).not.toHaveProperty(OTHER_SPAM_SLUG);
    expect(onMove).not.toHaveBeenCalled();
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

  it('keeps the chain data of a catalog token that leaves its full slug, and reports that slug', async () => {
    const onMove = jest.fn();
    const removeMoveListener = onTokenSlugsMove(onMove);

    try {
      await updateTokens([makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, { symbol: 'POL' })]);
      await updateTokens([makeToken(`ethereum-${AUSD_ADDRESS}`, 'ethereum', AUSD_ADDRESS, {
        tokenWalletAddress: '0xWallet', priceUsd: 1,
      })]);
      await updateTokens([{ ...ausd, priceUsd: undefined }]);
    } finally {
      removeMoveListener();
      delete cache.bySlug[`ethereum-${AUSD_ADDRESS}`];
    }

    expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ symbol: 'AUSD', tokenWalletAddress: '0xWallet', priceUsd: 1 });
    expect(onMove).toHaveBeenCalledWith([AUSD_SLUG, `ethereum-${AUSD_ADDRESS}`]);
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

  it('requests a token on a slug the backend gave it, and its details reach that token alone', async () => {
    const cache = getTokensCache();
    // The backend gave AUSD a longer slug of its own, while a spam token holds the slug derived from the address
    const ausdSlug = 'ethereum-0x00000000ef';
    const ausd = makeToken(ausdSlug, 'ethereum', AUSD_ADDRESS, { symbol: 'AUSD' });
    const spam = makeToken(AUSD_SLUG, 'ethereum', SPAM_ADDRESS, { symbol: 'POL', priceUsd: 0 });

    try {
      await updateTokens([ausd, spam]);
      expect(pickTokensForDetails([ausd, spam], { backendSlugs, maxCount: 100 })).toEqual([ausd, spam]);

      await updateTokens([], undefined, [{ slug: ausdSlug, priceUsd: 1, isPriceFromBackend: true }]);
      expect(cache.bySlug[ausdSlug]).toMatchObject({ symbol: 'AUSD', priceUsd: 1 });
      expect(cache.bySlug[AUSD_SLUG]).toMatchObject({ symbol: 'POL', priceUsd: 0 });
    } finally {
      delete cache.bySlug[ausdSlug];
      delete cache.bySlug[AUSD_SLUG];
    }
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
    resolvers[index]({ catalogVersion: 'reconnect', prices: { [slug]: [priceUsd, 0] } });
  };
  let resolvers: ((prices: { catalogVersion: string; prices: Record<string, [number, number]> }) => void)[];
  let closedRequest: Promise<void>;
  let request: Promise<void>;

  beforeEach(() => {
    resolvers = [];
    (callBackendGet as jest.Mock).mockImplementation((path: string) => {
      if (path === '/assets/prices') return new Promise((resolve) => resolvers.push(resolve));
      return Promise.resolve({ version: 'reconnect', assets: [makeToken(slug, 'ton', 'reconnect-token')] });
    });
    tokensPreload.resolve();
    pauseTokenUpdates();
    closedRequest = updateTokensFromBackend(closedOnUpdate);
    pauseTokenUpdates();
    request = updateTokensFromBackend(onUpdate);
  });

  afterEach(() => {
    (callBackendGet as jest.Mock).mockImplementation((path: string) => Promise.resolve(path === '/assets/prices'
      ? { catalogVersion: 'empty', prices: {} }
      : { version: 'empty', assets: [] }));
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

describe('backend token catalog and prices', () => {
  let sdk: typeof import('./tokens');
  let backend: typeof import('./backend');
  type Reply = { body: unknown; status?: number; error?: Error; pending?: Promise<void> };
  let replies: Record<string, Reply>;
  const token = makeToken('catalog-token', 'ton', 'catalog-address', { priceUsd: 2, percentChange24h: 3 });
  const { priceUsd, percentChange24h, ...catalogToken } = token;

  beforeEach(() => {
    jest.useFakeTimers();
    mockFetch.mockReset();
    jest.isolateModules(() => {
      sdk = jest.requireActual('./tokens');
      backend = jest.requireActual('./backend');
      jest.requireMock('./backend').callBackendGet.mockImplementation(backend.callBackendGet);
    });
    sdk.tokensPreload.resolve();
    replies = {
      '/assets/prices': { body: { catalogVersion: 'v1', prices: { [token.slug]: [priceUsd, percentChange24h] } } },
      '/assets/catalog': { body: { version: 'v1', assets: [catalogToken] } },
      '/assets': { body: [token] },
    };
    mockFetch.mockImplementation(async (url: string | URL) => {
      const reply = replies[new URL(url).pathname];
      if (!reply) throw new Error(`Unexpected backend URL: ${url}`);
      if (reply.error) throw reply.error;
      await reply.pending;
      const status = reply.status ?? 200;
      return {
        status,
        ok: status >= 200 && status < 300,
        json: () => Promise.resolve(JSON.parse(JSON.stringify(reply.body))),
        headers: { get: () => undefined },
      };
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('requests prices on every update and the unchanged catalog only once', async () => {
    replies['/assets/prices'].body = { ...replies['/assets/prices'].body as object, rates: CURRENCY_RATES };
    const onCurrencyRates = jest.fn();
    for (let i = 0; i < 4; i++) {
      await sdk.updateTokensFromBackend(jest.fn(), { langCode: 'en' }, onCurrencyRates);
    }

    expect(requestCount('/assets/prices')).toBe(4);
    expect(onCurrencyRates.mock.calls).toEqual(Array.from({ length: 4 }, () => [CURRENCY_RATES]));
    expect(requestCount('/assets/catalog')).toBe(1);
    expect(requestCount('/assets')).toBe(0);
    const urls = mockFetch.mock.calls.map(([url]) => new URL(url));
    expect(urls.filter((url) => url.pathname === '/assets/prices').every((url) => !url.search)).toBe(true);
    expect(urls.find((url) => url.pathname === '/assets/catalog')?.searchParams.get('langCode')).toBe('en');
  });

  it.each([
    undefined,
    'invalid',
    { USD: '1' },
    { ...CURRENCY_RATES, EUR: 0.9 },
  ])('reports unavailable currency rates for a missing or malformed prices field: %p', async (rates) => {
    replies['/assets/prices'].body = { ...replies['/assets/prices'].body as object, rates };
    const onCurrencyRates = jest.fn();

    await sdk.updateTokensFromBackend(jest.fn(), {}, onCurrencyRates);

    expect(onCurrencyRates.mock.calls).toEqual([[undefined]]);
  });

  it('rejects an undefined prices response without reporting valid rates', async () => {
    jest.requireMock('./backend').callBackendGet.mockResolvedValueOnce(undefined);
    const onCurrencyRates = jest.fn();

    await expect(sdk.updateTokensFromBackend(jest.fn(), {}, onCurrencyRates)).rejects.toThrow(TypeError);

    expect(onCurrencyRates).not.toHaveBeenCalled();
  });

  it('refreshes the catalog once for a new version and once for a new language', async () => {
    await sdk.fetchBackendTokens('en');
    replies['/assets/prices'].body = { catalogVersion: 'v2', prices: {} };
    replies['/assets/catalog'].body = { version: 'v2', assets: [catalogToken] };
    await sdk.fetchBackendTokens('en');
    await sdk.fetchBackendTokens('en');
    expect(requestCount('/assets/catalog')).toBe(2);

    replies['/assets/catalog'].body = { version: 'v2', assets: [{ ...catalogToken, localizedName: 'Localized' }] };
    expect((await sdk.fetchBackendTokens('ru'))[0].localizedName).toBe('Localized');
    await sdk.fetchBackendTokens('ru');
    expect(requestCount('/assets/catalog')).toBe(3);
    expect(mockFetch.mock.calls.map(([url]) => new URL(url))
      .filter((url) => url.pathname === '/assets/catalog').map((url) => url.searchParams.get('langCode')))
      .toEqual(['en', 'en', 'ru']);
    expect(requestCount('/assets')).toBe(0);
  });

  it('joins the legacy token fields and preserves UI handling of absent prices and null changes', async () => {
    const assets = [catalogToken, { ...catalogToken, slug: 'null-change' }, { ...catalogToken, slug: 'unpriced' }];
    const legacyTokens: ApiTokenWithMaybePrice[] = [
      { ...token, precision: 2 },
      { ...assets[1], priceUsd: 4, percentChange24h: undefined, precision: 2 },
      { ...assets[2], priceUsd: undefined, percentChange24h: undefined },
    ];
    replies['/assets/catalog'].body = { version: 'v1', assets };
    replies['/assets/prices'].body = {
      catalogVersion: 'v1',
      // eslint-disable-next-line no-null/no-null
      prices: { [token.slug]: [2, 3], 'null-change': [4, null], 'unknown-slug': [99, 1] },
    };
    // JSON null from the legacy endpoint follows the same nullish merge path as an absent change
    replies['/assets'].body = legacyTokens.map((item) => (
      // eslint-disable-next-line no-null/no-null
      item.slug === 'null-change' ? { ...item, percentChange24h: null } : item
    ));

    const joined = await sdk.fetchBackendTokens();
    expect(joined).toStrictEqual(legacyTokens);
    const legacy = await backend.callBackendGet<ApiTokenWithPrice[]>('/assets');
    for (const item of legacy) {
      item.isFromBackend = true;
      item.isPriceFromBackend = item.priceUsd !== undefined;
    }
    await sdk.updateTokens([makeToken('null-change', 'ton', 'catalog-address', { percentChange24h: 7 })]);
    await sdk.updateTokens(legacy);
    const expected = legacy.map(({ slug }) => sdk.getTokensCache().bySlug[slug]);
    await sdk.updateTokensFromBackend(jest.fn());
    expect(legacy.map(({ slug }) => sdk.getTokensCache().bySlug[slug])).toEqual(expected);
    expect(sdk.getTokensCache().bySlug['null-change'].percentChange24h).toBe(7);
    expect(sdk.getTokensCache().bySlug.unpriced.isPriceFromBackend).toBe(false);
    expect(sdk.getTokensCache().bySlug['unknown-slug']).toBeUndefined();
  });

  it.each(['/assets/prices', '/assets/catalog'])('uses legacy data for one hour after a 404 from %s', async (
    path,
  ) => {
    replies[path] = { body: { error: 'Not found' }, status: 404 };
    expect(await sdk.fetchBackendTokens('ru')).toEqual([token]);
    expect(requestCount(path)).toBe(1);
    const pricesCount = requestCount('/assets/prices');
    const catalogCount = requestCount('/assets/catalog');
    await jest.advanceTimersByTimeAsync(HOUR - 1);
    const onCurrencyRates = jest.fn();
    expect(await sdk.fetchBackendTokens('ru', onCurrencyRates)).toEqual([token]);
    expect(onCurrencyRates.mock.calls).toEqual([[undefined]]);
    expect(requestCount('/assets/prices')).toBe(pricesCount);
    expect(requestCount('/assets/catalog')).toBe(catalogCount);
    expect(requestCount('/assets')).toBe(2);

    replies['/assets/prices'] = { body: { catalogVersion: 'v2', prices: {} } };
    replies['/assets/catalog'] = { body: { version: 'v2', assets: [catalogToken] } };
    await jest.advanceTimersByTimeAsync(1);
    await sdk.fetchBackendTokens('ru');
    expect(requestCount('/assets/prices')).toBe(pricesCount + 1);
    expect(requestCount('/assets/catalog')).toBe(catalogCount + 1);
    expect(requestCount('/assets')).toBe(2);
  });

  it.each(['network', '500'])('keeps the cold catalog after a prices %s failure and settles preload', async (
    failure,
  ) => {
    replies['/assets/prices'] = failure === 'network'
      ? { body: {}, error: new Error('Offline') }
      : { body: { error: 'Server unavailable' }, status: 500 };
    sdk.pauseTokenUpdates();
    const resolver = sdk.waitForTokenSlugResolver();
    const onUpdate = jest.fn();
    const onCurrencyRates = jest.fn();
    await expect(sdk.updateTokensFromBackend(onUpdate, {}, onCurrencyRates)).rejects.toMatchObject({
      statusCode: failure === 'network' ? undefined : 500,
    });
    await expect(resolver).resolves.toEqual(expect.any(Function));
    expect(onUpdate).not.toHaveBeenCalled();
    expect(onCurrencyRates).not.toHaveBeenCalled();
    expect(requestCount('/assets/prices')).toBe(DEFAULT_RETRIES);
    expect(requestCount('/assets/catalog')).toBe(1);
    expect(requestCount('/assets')).toBe(0);

    replies['/assets/prices'] = { body: { catalogVersion: 'v1', prices: {} } };
    await sdk.updateTokensFromBackend(onUpdate);
    expect(requestCount('/assets/prices')).toBe(DEFAULT_RETRIES + 1);
    expect(requestCount('/assets/catalog')).toBe(1);
  });

  it('shares an in-flight catalog between parallel updates', async () => {
    const pending = new Deferred();
    const requested = new Deferred();
    replies['/assets/catalog'].pending = pending.promise;
    replies['/assets/prices'].body = { ...replies['/assets/prices'].body as object, rates: CURRENCY_RATES };
    const onCurrencyRates = jest.fn();
    const fetch = mockFetch.getMockImplementation()!;
    mockFetch.mockImplementation((url: string | URL, ...args: unknown[]) => {
      if (new URL(url).pathname === '/assets/catalog') requested.resolve();
      return fetch(url, ...args);
    });
    const first = sdk.updateTokensFromBackend(jest.fn(), { langCode: 'en' }, onCurrencyRates);
    const second = sdk.updateTokensFromBackend(jest.fn(), { langCode: 'en' }, onCurrencyRates);
    await requested.promise;
    await jest.advanceTimersByTimeAsync(0);
    expect(requestCount('/assets/prices')).toBe(2);
    expect(requestCount('/assets/catalog')).toBe(1);
    expect(onCurrencyRates.mock.calls).toEqual([[CURRENCY_RATES], [CURRENCY_RATES]]);
    pending.resolve();
    await Promise.all([first, second]);
    expect(requestCount('/assets/catalog')).toBe(1);
  });

  it('starts a cold catalog request before the pending prices respond', async () => {
    const pending = new Deferred();
    replies['/assets/prices'].pending = pending.promise;
    const request = sdk.fetchBackendTokens('en');
    await jest.advanceTimersByTimeAsync(0);

    expect(requestCount('/assets/prices')).toBe(1);
    expect(requestCount('/assets/catalog')).toBe(1);

    pending.resolve();
    expect(await request).toEqual([{ ...token, precision: 2 }]);
  });

  it('uses legacy after prices return 404 even when the parallel catalog rejects later', async () => {
    const pending = new Deferred();
    const onUnhandledRejection = jest.fn();
    process.on('unhandledRejection', onUnhandledRejection);
    replies['/assets/prices'] = { body: { error: 'Not found' }, status: 404 };
    replies['/assets/catalog'].pending = pending.promise;

    try {
      const request = sdk.fetchBackendTokens('en');
      const result = expect(request).resolves.toEqual([token]);
      await jest.advanceTimersByTimeAsync(0);
      expect(requestCount('/assets/prices')).toBe(1);
      expect(requestCount('/assets/catalog')).toBe(1);
      pending.reject(new Error('Offline'));
      await result;
      await jest.advanceTimersByTimeAsync(0);

      expect(onUnhandledRejection).not.toHaveBeenCalled();
      expect(requestCount('/assets/catalog')).toBe(DEFAULT_RETRIES);
      expect(requestCount('/assets')).toBe(1);
      await sdk.fetchBackendTokens('en');
      expect(requestCount('/assets/prices')).toBe(1);
      expect(requestCount('/assets/catalog')).toBe(DEFAULT_RETRIES);
      expect(requestCount('/assets')).toBe(2);
    } finally {
      process.off('unhandledRejection', onUnhandledRejection);
    }
  });

  it('accepts a different catalog version and checks it again on the next call', async () => {
    replies['/assets/catalog'].body = { version: 'other-pod', assets: [catalogToken] };
    expect(await sdk.fetchBackendTokens()).toStrictEqual([{
      ...catalogToken, priceUsd: undefined, percentChange24h: undefined,
    }]);
    replies['/assets/catalog'].body = { version: 'v1', assets: [catalogToken] };
    await sdk.fetchBackendTokens();
    await sdk.fetchBackendTokens();
    expect(requestCount('/assets/catalog')).toBe(2);
  });

  it('uses a same-language catalog after a refresh failure and retries its version on the next call', async () => {
    await sdk.fetchBackendTokens('en');
    replies['/assets/prices'].body = { catalogVersion: 'v2', prices: { [token.slug]: [5, 6] } };
    replies['/assets/catalog'].error = new Error('Offline');
    expect(await sdk.fetchBackendTokens('en')).toStrictEqual([{
      ...catalogToken, priceUsd: undefined, percentChange24h: undefined,
    }]);
    expect(requestCount('/assets/catalog')).toBe(1 + DEFAULT_RETRIES);
    delete replies['/assets/catalog'].error;
    replies['/assets/catalog'].body = { version: 'v2', assets: [catalogToken] };
    await sdk.fetchBackendTokens('en');
    expect(requestCount('/assets/catalog')).toBe(2 + DEFAULT_RETRIES);
    expect(requestCount('/assets')).toBe(0);
  });

  it.each(['failed refresh', 'different pod'])('keeps the old quote across a slug reassignment after %s', async (
    failure,
  ) => {
    const { priceUsd: oldPrice, percentChange24h: oldChange, ...oldOwner } = makeToken(
      AUSD_SLUG, 'ethereum', AUSD_ADDRESS, { priceUsd: 2, percentChange24h: 3 },
    );
    const newOwner = { ...oldOwner, tokenAddress: SPAM_ADDRESS, name: 'New owner' };
    replies['/assets/catalog'].body = { version: 'v1', assets: [oldOwner] };
    replies['/assets/prices'].body = { catalogVersion: 'v1', prices: { [AUSD_SLUG]: [oldPrice, oldChange] } };
    const onUpdate = jest.fn();
    await sdk.updateTokensFromBackend(onUpdate, { langCode: 'en' });
    expect(sdk.getTokenBySlug(AUSD_SLUG)).toMatchObject({
      tokenAddress: AUSD_ADDRESS, priceUsd: 2, percentChange24h: 3, isPriceFromBackend: true,
    });

    replies['/assets/prices'].body = { catalogVersion: 'v2', prices: { [AUSD_SLUG]: [9, 10] } };
    if (failure === 'failed refresh') replies['/assets/catalog'].error = new Error('Offline');
    await sdk.updateTokensFromBackend(onUpdate, { langCode: 'en' });
    expect(sdk.getTokenBySlug(AUSD_SLUG)).toMatchObject({
      tokenAddress: AUSD_ADDRESS, priceUsd: 2, percentChange24h: 3, isPriceFromBackend: false,
    });

    delete replies['/assets/catalog'].error;
    replies['/assets/catalog'].body = { version: 'v2', assets: [newOwner] };
    await sdk.updateTokensFromBackend(onUpdate, { langCode: 'en' });
    expect(sdk.getTokenBySlug(AUSD_SLUG)).toMatchObject({
      tokenAddress: SPAM_ADDRESS, priceUsd: 9, percentChange24h: 10, isPriceFromBackend: true,
    });
    expect(sdk.getTokenBySlug(`ethereum-${AUSD_ADDRESS}`)).toMatchObject({
      tokenAddress: AUSD_ADDRESS, priceUsd: 2, percentChange24h: 3, isPriceFromBackend: false,
    });
  });

  it.each([undefined, 'en'])('rejects a catalog failure without a cached ru catalog (cached language: %s)', async (
    langCode,
  ) => {
    if (langCode) await sdk.fetchBackendTokens(langCode);
    replies['/assets/catalog'].error = new Error('Offline');
    const onUpdate = jest.fn();
    await expect(sdk.updateTokensFromBackend(onUpdate, { langCode: 'ru' })).rejects.toThrow('Offline');
    expect(onUpdate).not.toHaveBeenCalled();
    expect(requestCount('/assets')).toBe(0);
  });

  function requestCount(path: string) {
    return mockFetch.mock.calls.filter(([url]) => new URL(url).pathname === path).length;
  }
});
