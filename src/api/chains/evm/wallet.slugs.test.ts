/* eslint-disable no-null/no-null -- Zerion responses use null for absent prices and metadata. */

import type { ApiTokenWithPrice } from '../../types';
import type { ZerionPosition } from './types';

import { SECOND } from '../../../util/dateFormat';
import Deferred from '../../../util/Deferred';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchWithRetry: jest.fn(),
  fetchJson: jest.fn(),
}));
jest.mock('./util/client', () => ({
  getEvmProvider: jest.fn(() => ({
    send: jest.fn((method: string) => Promise.resolve(method === 'eth_blockNumber' ? '0x64' : '0x0')),
  })),
}));
jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockImplementation((path: string) => Promise.resolve(path === '/assets/prices'
    ? { catalogVersion: 'empty', prices: {} }
    : { version: 'empty', assets: [] })),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));
jest.mock('../../db', () => ({
  tokenRepository: {
    all: jest.fn().mockResolvedValue([]),
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));

const WALLET_ADDRESS = '0x1111111111111111111111111111111111111111';
// The catalog lists AUSD under `ethereum-0x00000000`, the backend slug of every address that starts with eight zeros
const AUSD: ApiTokenWithPrice = {
  slug: 'ethereum-0x00000000',
  chain: 'ethereum',
  tokenAddress: '0x00000000efe302beaa2b3e6e1b18d08d69a9012a',
  name: 'AUSD',
  symbol: 'AUSD',
  decimals: 6,
  priceUsd: 0.9993,
  percentChange24h: 0,
  isFromBackend: true,
};
const { priceUsd, percentChange24h, isFromBackend, ...AUSD_CATALOG } = AUSD;
const SPAM_ADDRESS = '0x00000000f9fd50c832d79facfe6f4e8ce90a5efb';
const SPAM_SLUG = `ethereum-${SPAM_ADDRESS}`;
const OTHER_SPAM_ADDRESS = '0x0000000000c39a0f674c12a5e63eb8031b550b6f';
const OTHER_SPAM_SLUG = `ethereum-${OTHER_SPAM_ADDRESS}`;

describe('EVM token slugs', () => {
  beforeEach(() => {
    jest.resetModules();
  });

  it('assigns the slugs of a balance that outruns the catalog once the catalog arrives', async () => {
    const { fetchWithRetry } = await import('../../../util/fetch');
    const { callBackendGet } = await import('../../common/backend');
    const tokens = await import('../../common/tokens');
    const { fetchAccountAssets } = await import('./wallet');

    void tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    mockPositions(fetchWithRetry);

    const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(assetsPromise.isSettled()).toBe(false);

    jest.mocked(callBackendGet).mockImplementation((path: string) => Promise.resolve(path === '/assets/prices'
      ? { catalogVersion: 'ausd', prices: { [AUSD.slug]: [priceUsd, percentChange24h] } }
      : { version: 'ausd', assets: [AUSD_CATALOG] }));
    await tokens.updateTokensFromBackend(jest.fn());
    tokens.resumeTokenUpdates();
    const { balances } = await assetsPromise.promise;

    expect(balances).toEqual(expect.objectContaining({
      [SPAM_SLUG]: 400000000000000000000000000n,
      [OTHER_SPAM_SLUG]: 32000000000000000000n,
    }));
    expect(balances).not.toHaveProperty(AUSD.slug);
    expect(tokens.getTokenBySlug(AUSD.slug)).toMatchObject({ tokenAddress: AUSD.tokenAddress, decimals: 6 });
    expect(tokens.getTokenBySlug(SPAM_SLUG)).toMatchObject({ tokenAddress: SPAM_ADDRESS, decimals: 18, symbol: 'POL' });
  });

  it('keeps waiting when the catalog request of a closed UI settles first', async () => {
    const { fetchWithRetry } = await import('../../../util/fetch');
    const { callBackendGet } = await import('../../common/backend');
    const tokens = await import('../../common/tokens');
    const { fetchAccountAssets } = await import('./wallet');
    const catalog = new Deferred<{ version: string; assets: (typeof AUSD_CATALOG)[] }>();
    const closedPrices = new Deferred<never>();
    let pricesCount = 0;
    jest.mocked(callBackendGet).mockImplementation((path: string) => {
      if (path === '/assets/catalog') return catalog.promise;
      pricesCount += 1;
      return pricesCount === 1 ? closedPrices.promise : Promise.resolve({
        catalogVersion: 'current', prices: { [AUSD.slug]: [priceUsd, percentChange24h] },
      });
    });

    void tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    const closedRequest = tokens.updateTokensFromBackend(jest.fn());
    const closedResult = expect(closedRequest).rejects.toThrow('Offline');
    tokens.pauseTokenUpdates();
    const request = tokens.updateTokensFromBackend(jest.fn());
    mockPositions(fetchWithRetry);
    const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Each request is followed by `resumeTokenUpdates`, as in `tryUpdateTokens`
    closedPrices.reject(new Error('Offline'));
    await closedResult;
    tokens.resumeTokenUpdates();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(assetsPromise.isSettled()).toBe(false);
    expect(jest.mocked(callBackendGet).mock.calls.filter(([path]) => path === '/assets/catalog')).toHaveLength(1);

    catalog.resolve({ version: 'current', assets: [AUSD_CATALOG] });
    await request;
    tokens.resumeTokenUpdates();
    const { balances } = await assetsPromise.promise;

    expect(balances).toHaveProperty(SPAM_SLUG);
    expect(balances).not.toHaveProperty(AUSD.slug);
  });

  it('assigns the slugs once the catalog is in the cache, without waiting for its database write', async () => {
    const { fetchWithRetry } = await import('../../../util/fetch');
    const { callBackendGet } = await import('../../common/backend');
    const { tokenRepository } = await import('../../db');
    const tokens = await import('../../common/tokens');
    const { fetchAccountAssets } = await import('./wallet');
    // The first write is the cache load, the second one is the catalog
    jest.mocked(tokenRepository.bulkPut)
      .mockResolvedValueOnce(undefined)
      .mockReturnValueOnce(new Promise(() => undefined));

    await tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    jest.mocked(callBackendGet).mockImplementation((path: string) => Promise.resolve(path === '/assets/prices'
      ? { catalogVersion: 'ausd', prices: { [AUSD.slug]: [priceUsd, percentChange24h] } }
      : { version: 'ausd', assets: [AUSD_CATALOG] }));
    void tokens.updateTokensFromBackend(jest.fn());
    mockPositions(fetchWithRetry);

    const { balances } = await fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn());

    expect(balances).toHaveProperty(SPAM_SLUG);
    expect(balances).not.toHaveProperty(AUSD.slug);
  });

  it('stops waiting for a catalog that is late by the timeout, which then moves the slug it gives', async () => {
    jest.useFakeTimers();

    try {
      const { fetchWithRetry } = await import('../../../util/fetch');
      const { callBackendGet } = await import('../../common/backend');
      const tokens = await import('../../common/tokens');
      const { onTokenSlugsMove } = await import('../../common/tokenSlugMoves');
      const { fetchAccountAssets } = await import('./wallet');
      const catalog = new Deferred<{ version: string; assets: (typeof AUSD_CATALOG)[] }>();
      const onMove = jest.fn();
      jest.mocked(callBackendGet).mockImplementation((path: string) => (path === '/assets/catalog'
        ? catalog.promise
        : Promise.resolve({ catalogVersion: 'ausd', prices: { [AUSD.slug]: [priceUsd, percentChange24h] } })));
      onTokenSlugsMove(onMove);

      await tokens.loadTokensCache();
      tokens.pauseTokenUpdates();
      const request = tokens.updateTokensFromBackend(jest.fn());
      mockPositions(fetchWithRetry);

      const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));
      await jest.advanceTimersByTimeAsync(4 * SECOND);
      expect(assetsPromise.isSettled()).toBe(false);

      await jest.advanceTimersByTimeAsync(SECOND);
      const { balances } = await assetsPromise.promise;

      // Without the catalog, the smaller address key takes the slug the catalog gives to AUSD
      expect(balances).toEqual(expect.objectContaining({
        [AUSD.slug]: 32000000000000000000n,
        [SPAM_SLUG]: 400000000000000000000000000n,
      }));

      catalog.resolve({ version: 'ausd', assets: [AUSD_CATALOG] });
      await request;

      expect(onMove).toHaveBeenCalledWith([AUSD.slug]);
      expect(tokens.getTokenBySlug(AUSD.slug)).toMatchObject({ tokenAddress: AUSD.tokenAddress });
      expect(tokens.getTokenBySlug(OTHER_SPAM_SLUG)).toMatchObject({ tokenAddress: OTHER_SPAM_ADDRESS });
    } finally {
      jest.useRealTimers();
    }
  });

  it('assigns the slugs after the cached tokens load when the catalog request fails first', async () => {
    const { fetchWithRetry } = await import('../../../util/fetch');
    const { callBackendGet } = await import('../../common/backend');
    const { tokenRepository } = await import('../../db');
    const tokens = await import('../../common/tokens');
    const { fetchAccountAssets } = await import('./wallet');
    const cachedTokens = new Deferred<ApiTokenWithPrice[]>();
    jest.mocked(tokenRepository.all).mockReturnValueOnce(cachedTokens.promise);
    jest.mocked(callBackendGet).mockImplementation((path: string) => (path === '/assets/catalog'
      ? Promise.reject(new Error('Offline'))
      : Promise.resolve({ catalogVersion: 'ausd', prices: { [AUSD.slug]: [priceUsd, percentChange24h] } })));

    void tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    await expect(tokens.updateTokensFromBackend(jest.fn())).rejects.toThrow('Offline');
    mockPositions(fetchWithRetry);

    const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(assetsPromise.isSettled()).toBe(false);

    cachedTokens.resolve([AUSD]);
    const { balances } = await assetsPromise.promise;

    expect(balances).toHaveProperty(SPAM_SLUG);
    expect(balances).not.toHaveProperty(AUSD.slug);
  });

  it('counts the catalog timeout from the moment the cached tokens load', async () => {
    jest.useFakeTimers();

    try {
      const { fetchWithRetry } = await import('../../../util/fetch');
      const { callBackendGet } = await import('../../common/backend');
      const { tokenRepository } = await import('../../db');
      const tokens = await import('../../common/tokens');
      const { fetchAccountAssets } = await import('./wallet');
      const cachedTokens = new Deferred<ApiTokenWithPrice[]>();
      const catalog = new Deferred<{ version: string; assets: (typeof AUSD_CATALOG)[] }>();
      jest.mocked(tokenRepository.all).mockReturnValueOnce(cachedTokens.promise);
      jest.mocked(callBackendGet).mockImplementation((path: string) => (path === '/assets/catalog'
        ? catalog.promise
        : Promise.resolve({ catalogVersion: 'ausd', prices: { [AUSD.slug]: [priceUsd, percentChange24h] } })));

      void tokens.loadTokensCache();
      tokens.pauseTokenUpdates();
      const request = tokens.updateTokensFromBackend(jest.fn());
      mockPositions(fetchWithRetry);

      const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));
      await jest.advanceTimersByTimeAsync(6 * SECOND);
      cachedTokens.resolve([]);
      await jest.advanceTimersByTimeAsync(SECOND);
      expect(assetsPromise.isSettled()).toBe(false);

      catalog.resolve({ version: 'ausd', assets: [AUSD_CATALOG] });
      await request;
      const { balances } = await assetsPromise.promise;

      expect(balances).toHaveProperty(SPAM_SLUG);
      expect(balances).not.toHaveProperty(AUSD.slug);
    } finally {
      jest.useRealTimers();
    }
  });

  it('caches the tokens whose metadata is fetched together under slugs of their own', async () => {
    const { fetchJson } = await import('../../../util/fetch');
    const tokens = await import('../../common/tokens');
    const { updateTokensMetadataByAddress } = await import('./util/metadata');
    const symbolByAddress: Record<string, string> = { [SPAM_ADDRESS]: 'POL', [OTHER_SPAM_ADDRESS]: 'NFSC' };
    jest.mocked(fetchJson).mockImplementation((_url, _data, init) => {
      const [address] = JSON.parse(init!.body as string).params as string[];
      const symbol = symbolByAddress[address];
      return Promise.resolve({ result: { name: symbol, symbol, decimals: 18, logo: null } });
    });

    await updateTokensMetadataByAddress('mainnet', 'ethereum', [SPAM_ADDRESS, OTHER_SPAM_ADDRESS]);

    expect(tokens.getTokenBySlug(tokens.buildTokenSlug('ethereum', SPAM_ADDRESS))).toMatchObject({ symbol: 'POL' });
    expect(tokens.getTokenBySlug(tokens.buildTokenSlug('ethereum', OTHER_SPAM_ADDRESS)))
      .toMatchObject({ symbol: 'NFSC' });
  });
});

function mockPositions(fetchWithRetry: typeof import('../../../util/fetch').fetchWithRetry) {
  jest.mocked(fetchWithRetry).mockResolvedValueOnce({
    headers: { get: () => null },
    json: () => Promise.resolve({
      links: { self: '' },
      data: [
        buildPosition('POL', SPAM_ADDRESS, '400000000000000000000000000'),
        buildPosition('NFSC', OTHER_SPAM_ADDRESS, '32000000000000000000'),
      ],
    }),
  } as unknown as Response);
}

function trackSettlement<T>(promise: Promise<T>) {
  let isSettled = false;
  const trackedPromise = promise.finally(() => {
    isSettled = true;
  });

  return { promise: trackedPromise, isSettled: () => isSettled };
}

function buildPosition(symbol: string, address: string, quantity: string): ZerionPosition {
  return {
    type: 'positions',
    id: `${symbol}-position`,
    attributes: {
      parent: null,
      protocol: null,
      name: symbol,
      position_type: 'wallet',
      quantity: { int: quantity, decimals: 18, float: 0, numeric: '0' },
      value: null,
      price: 0,
      changes: null,
      fungible_info: {
        name: symbol,
        symbol,
        icon: null,
        flags: { verified: false },
        implementations: [{ chain_id: 'ethereum', address, decimals: 18 }],
      },
      flags: { displayable: true, is_trash: false },
      updated_at: '2026-10-09T00:00:00Z',
      updated_at_block: 1,
    },
    relationships: {
      chain: { links: { related: '' }, data: { type: 'chains', id: 'ethereum' } },
      fungible: { links: { related: '' }, data: { type: 'fungibles', id: symbol } },
    },
  };
}
