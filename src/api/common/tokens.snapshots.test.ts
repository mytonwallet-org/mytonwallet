import type { ApiTokenWithMaybePrice, ApiTokenWithPrice } from '../types';

import { TRC20_USDT_MAINNET } from '../../config';

jest.mock('../db', () => ({
  tokenRepository: {
    all: jest.fn().mockResolvedValue([]),
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));
jest.mock('./backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));

describe('initial token snapshots and quote availability', () => {
  const previousIsAirApp = process.env.IS_AIR_APP;
  let sdk: typeof import('./tokens');
  let backend: typeof import('./backend');

  beforeEach(async () => {
    jest.resetModules();
    sdk = await import('./tokens');
    backend = await import('./backend');
    await sdk.loadTokensCache();
  });

  afterEach(() => {
    if (previousIsAirApp === undefined) delete process.env.IS_AIR_APP;
    else process.env.IS_AIR_APP = previousIsAirApp;
  });

  it.each(['0', '1'])('marks only startup snapshots incomplete (IS_AIR_APP=%s)', async (isAirApp) => {
    process.env.IS_AIR_APP = isAirApp;
    const onUpdate = jest.fn();
    const token = makeToken({ priceUsd: 1 });
    sdk.pauseTokenUpdates();
    await sdk.updateTokens([token], () => sdk.sendUpdateTokens(onUpdate));
    jest.mocked(backend.callBackendGet).mockRejectedValueOnce(new Error('offline'));
    await expect(sdk.updateTokensFromBackend(onUpdate)).rejects.toThrow('offline');
    sdk.resumeTokenUpdates();

    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({ kind: 'fromCache', isIncomplete: true }));
    sdk.sendUpdateTokens(onUpdate);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({ kind: 'fromCache', isIncomplete: true }));

    await sdk.updateTokensFromBackend(onUpdate);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({ kind: 'full', isIncomplete: true }));

    delete sdk.getTokensCache().bySlug[token.slug];
    sdk.sendUpdateTokens(onUpdate);
    expect(onUpdate).toHaveBeenLastCalledWith({
      type: 'updateTokens', kind: 'partial', tokens: {}, removedSlugs: [token.slug],
    });

    sdk.resetLastTokens();
    sdk.sendUpdateTokens(onUpdate);
    expect(onUpdate.mock.lastCall![0].kind).toBe('full');
    expect(onUpdate.mock.lastCall![0].isIncomplete).toBeUndefined();
    expect(onUpdate.mock.lastCall![0].tokens[token.slug]).toBeUndefined();

    sdk.pauseTokenUpdates();
    sdk.sendUpdateTokens(onUpdate);
    sdk.resumeTokenUpdates();
    expect(onUpdate.mock.lastCall![0].isIncomplete).toBeUndefined();
    await sdk.updateTokensFromBackend(onUpdate);
    expect(onUpdate.mock.lastCall![0].kind).toBe('full');
    expect(onUpdate.mock.lastCall![0].isIncomplete).toBeUndefined();
  });

  it('keeps an unfetched default quote marked until a genuine zero quote arrives', async () => {
    const onUpdate = jest.fn();
    const slug = TRC20_USDT_MAINNET.slug;
    await sdk.updateTokensFromBackend(onUpdate);

    expect(onUpdate.mock.lastCall![0].tokens[slug].priceUsd).toBe(0);
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toContain(slug);

    // Resolving a placeholder to a real zero must send a delta even when the numeric token fields match.
    const token = { ...sdk.getTokensCache().bySlug[slug] };
    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([token]);
    await sdk.updateTokensFromBackend(onUpdate);

    expect(onUpdate.mock.lastCall![0]).toEqual({ type: 'updateTokens', kind: 'partial', tokens: { [slug]: token } });
    onUpdate.mockClear();
    sdk.sendUpdateTokens(onUpdate);
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('tracks a discovered token without a quote through metadata updates and a details response', async () => {
    const onUpdate = jest.fn();
    await sdk.updateTokensFromBackend(onUpdate);
    const token = makeToken();
    await sdk.updateTokens([token], () => sdk.sendUpdateTokens(onUpdate));
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toEqual([token.slug]);

    await sdk.updateTokens([{ ...token, name: 'Discovered name' }], () => sdk.sendUpdateTokens(onUpdate), [], true);
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toEqual([token.slug]);

    await sdk.updateTokens([], () => sdk.sendUpdateTokens(onUpdate), [{
      slug: token.slug, priceUsd: 0, percentChange24h: 0,
    }], true);
    expect(onUpdate.mock.lastCall![0].tokens[token.slug].priceUsd).toBe(0);
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toBeUndefined();

    await sdk.updateTokens([token], () => sdk.sendUpdateTokens(onUpdate), [], true);
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toBeUndefined();
  });

  it('does not lose an available quote when later discovery omits its price', async () => {
    const onUpdate = jest.fn();
    await sdk.updateTokensFromBackend(onUpdate);
    const token = makeToken({ priceUsd: 2, percentChange24h: 3 });
    await sdk.updateTokens([token], () => sdk.sendUpdateTokens(onUpdate));
    await sdk.updateTokens([makeToken({ name: 'Updated name' })], () => sdk.sendUpdateTokens(onUpdate), [], true);

    expect(onUpdate.mock.lastCall![0].tokens[token.slug])
      .toEqual(expect.objectContaining({ priceUsd: 2, percentChange24h: 3 }));
    expect(onUpdate.mock.lastCall![0].unpricedSlugs).toBeUndefined();
  });

  it('keeps backend quotes through balance responses and failures, then accepts a backend refresh', async () => {
    const onUpdate = jest.fn();
    const token = makeToken({ priceUsd: 2390, percentChange24h: 2 }) as ApiTokenWithPrice;
    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([token]);
    await sdk.updateTokensFromBackend(onUpdate);
    onUpdate.mockClear();

    await sdk.updateTokens([makeToken({ priceUsd: 2526, percentChange24h: 7 })],
      () => sdk.sendUpdateTokens(onUpdate), [], true);
    expect(onUpdate).not.toHaveBeenCalled();
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({ priceUsd: 2390, percentChange24h: 2 });

    jest.mocked(backend.callBackendGet).mockRejectedValueOnce(new Error('offline'));
    await expect(sdk.updateTokensFromBackend(onUpdate)).rejects.toThrow('offline');
    await sdk.updateTokens([makeToken({ priceUsd: 2500, tokenWalletAddress: 'new-wallet' })]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({
      priceUsd: 2390, percentChange24h: 2, tokenWalletAddress: 'new-wallet',
    });

    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([{ ...token, priceUsd: 2400, percentChange24h: 3 }]);
    await sdk.updateTokensFromBackend(onUpdate);
    expect(onUpdate.mock.lastCall![0].tokens[token.slug]).toMatchObject({ priceUsd: 2400, percentChange24h: 3 });
  });

  it('uses balance quotes as fallback until POST /assets supplies a quote, including zero', async () => {
    const token = makeToken({ priceUsd: 2, percentChange24h: 1 });
    await sdk.updateTokens([token]);
    await sdk.updateTokens([makeToken({ priceUsd: 3, percentChange24h: 2 })]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({ priceUsd: 3, percentChange24h: 2 });

    for (const priceUsd of [4, 0]) {
      await sdk.updateTokens([], undefined, [{ slug: token.slug, priceUsd, percentChange24h: -1 }]);
      await sdk.updateTokens([makeToken({ priceUsd: 5, percentChange24h: 3 })]);
      expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({
        priceUsd, percentChange24h: -1, isPriceFromBackend: true,
      });
      expect(sdk.getTokensCache().bySlug[token.slug].isFromBackend).toBeUndefined();
    }
  });

  it('preserves backend price ownership when a token and its details arrive together', async () => {
    const token = makeToken({ priceUsd: 5 });
    await sdk.updateTokens([token], undefined, [{ slug: token.slug, priceUsd: 0, percentChange24h: 0 }]);
    await sdk.updateTokens([token]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({ priceUsd: 0, isPriceFromBackend: true });
  });

  it('retains a POST /assets quote after reloading the persisted SDK cache', async () => {
    const token = makeToken({ priceUsd: 5 });
    await sdk.updateTokens([token]);
    await sdk.updateTokens([], undefined, [{ slug: token.slug, priceUsd: 4, percentChange24h: 2 }]);
    const storedToken = { ...sdk.getTokensCache().bySlug[token.slug] };

    jest.resetModules();
    const { tokenRepository } = await import('../db');
    jest.mocked(tokenRepository.all).mockResolvedValueOnce([storedToken]);
    sdk = await import('./tokens');
    await sdk.loadTokensCache();
    await sdk.updateTokens([makeToken({ priceUsd: 6, percentChange24h: 3 })]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({
      priceUsd: 4, percentChange24h: 2, isPriceFromBackend: true,
    });
  });

  it('releases omitted requested quotes while retaining quotes outside the request', async () => {
    const onUpdate = jest.fn();
    const token = makeToken({ priceUsd: 4, percentChange24h: 2 }) as ApiTokenWithPrice;
    const unrequested = { ...token, slug: 'base-unrequested', chain: 'base' as const };
    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([token, unrequested]);
    await sdk.updateTokensFromBackend(onUpdate);

    const heldTokens = await import('./heldTokens');
    jest.spyOn(heldTokens, 'getHeldSlugs').mockReturnValue(new Set([token.slug]));
    // The next GET no longer lists either asset, and POST successfully returns no details for the requested one.
    await sdk.updateTokensFromBackend(onUpdate, { shouldNarrowToHeldTokens: true });
    expect(backend.callBackendPost).toHaveBeenLastCalledWith('/assets', { assets: [token.tokenAddress] });
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({ priceUsd: 4, isPriceFromBackend: false });

    const { tokenRepository } = await import('../db');
    expect(tokenRepository.bulkPut).toHaveBeenLastCalledWith(expect.arrayContaining([
      expect.objectContaining({ slug: token.slug, priceUsd: 4, isPriceFromBackend: false }),
    ]));

    await sdk.updateTokens([
      makeToken({ priceUsd: 6, percentChange24h: 3 }),
      { ...unrequested, priceUsd: 6, isFromBackend: undefined, isPriceFromBackend: undefined },
    ]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({ priceUsd: 6, percentChange24h: 3 });
    expect(sdk.getTokensCache().bySlug[unrequested.slug]).toMatchObject({ priceUsd: 4, isPriceFromBackend: true });
  });

  it('does not claim a quote for backend metadata without a price', async () => {
    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([makeToken()]);
    await sdk.updateTokensFromBackend(jest.fn());
    await sdk.updateTokens([makeToken({ priceUsd: 6, percentChange24h: 3 })]);

    expect(sdk.getTokensCache().bySlug['ethereum-snapshot']).toMatchObject({
      priceUsd: 6, percentChange24h: 3, isPriceFromBackend: false,
    });
  });

  it.each(['timeout', 'zero'])('keeps backend ownership after a POST %s', async (response) => {
    const onUpdate = jest.fn();
    const token = makeToken({ priceUsd: 4, percentChange24h: 2 }) as ApiTokenWithPrice;
    jest.mocked(backend.callBackendGet).mockResolvedValueOnce([token]);
    await sdk.updateTokensFromBackend(onUpdate);

    if (response === 'timeout') {
      jest.mocked(backend.callBackendPost).mockRejectedValueOnce(new Error('timeout'));
    } else {
      jest.mocked(backend.callBackendPost).mockResolvedValueOnce([
        { slug: token.slug, priceUsd: 0, percentChange24h: 0 },
      ]);
    }
    await sdk.updateTokensFromBackend(onUpdate);
    await sdk.updateTokens([makeToken({ priceUsd: 6, percentChange24h: 3 })]);
    expect(sdk.getTokensCache().bySlug[token.slug]).toMatchObject({
      priceUsd: response === 'timeout' ? 4 : 0, isPriceFromBackend: true,
    });
  });
});

function makeToken(rest?: Partial<ApiTokenWithPrice>): ApiTokenWithMaybePrice {
  return {
    slug: 'ethereum-snapshot', chain: 'ethereum', tokenAddress: '0xSnapshot',
    name: 'Snapshot', symbol: 'SNAP', decimals: 18,
    priceUsd: undefined, percentChange24h: undefined, ...rest,
  };
}
