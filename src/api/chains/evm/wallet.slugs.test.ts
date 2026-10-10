/* eslint-disable no-null/no-null -- Zerion responses use null for absent prices and metadata. */

import type { ApiTokenWithPrice } from '../../types';
import type { ZerionPosition } from './types';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchWithRetry: jest.fn(),
  fetchJson: jest.fn(),
}));
jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
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

    jest.mocked(callBackendGet).mockResolvedValueOnce([AUSD]);
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
    const catalogResolvers: ((assets: ApiTokenWithPrice[]) => void)[] = [];
    jest.mocked(callBackendGet).mockImplementation(() => new Promise((resolve) => {
      catalogResolvers.push(resolve as (assets: ApiTokenWithPrice[]) => void);
    }));

    void tokens.loadTokensCache();
    tokens.pauseTokenUpdates();
    const closedRequest = tokens.updateTokensFromBackend(jest.fn());
    tokens.pauseTokenUpdates();
    const request = tokens.updateTokensFromBackend(jest.fn());
    mockPositions(fetchWithRetry);
    const assetsPromise = trackSettlement(fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn()));

    // Each request is followed by `resumeTokenUpdates`, as in `tryUpdateTokens`
    catalogResolvers[0]([]);
    await closedRequest;
    tokens.resumeTokenUpdates();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(assetsPromise.isSettled()).toBe(false);

    catalogResolvers[1]([AUSD]);
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
    jest.mocked(callBackendGet).mockResolvedValueOnce([AUSD]);
    void tokens.updateTokensFromBackend(jest.fn());
    mockPositions(fetchWithRetry);

    const { balances } = await fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, jest.fn());

    expect(balances).toHaveProperty(SPAM_SLUG);
    expect(balances).not.toHaveProperty(AUSD.slug);
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
