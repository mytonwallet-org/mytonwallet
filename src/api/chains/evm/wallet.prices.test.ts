/* eslint-disable no-null/no-null -- Zerion responses use null for absent prices and metadata. */

import type { ZerionPositionsResponse } from './types';

import { fetchWithRetry } from '../../../util/fetch';
import { callBackendGet } from '../../common/backend';
import {
  buildTokenSlug, getTokenBySlug, getTokensCache, loadTokensCache, resetLastTokens,
  sendUpdateTokens, updateTokens, updateTokensFromBackend,
} from '../../common/tokens';
import { fetchAccountAssets } from './wallet';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchWithRetry: jest.fn(),
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

const TOKEN_ADDRESS = '0x514b9e5467b9eb811519e316263c9099eae546ca';
const TOKEN_SLUG = buildTokenSlug('ethereum', TOKEN_ADDRESS);
const WALLET_ADDRESS = '0x1111111111111111111111111111111111111111';
const OLD_PRICE = 0.001387062673283777;

describe('EVM token price invalidation', () => {
  const onUpdate = jest.fn();
  const sendUpdate = () => sendUpdateTokens(onUpdate);

  beforeEach(async () => {
    jest.clearAllMocks();
    delete getTokensCache().bySlug[TOKEN_SLUG];
    resetLastTokens();
    await loadTokensCache();
    await updateTokensFromBackend(onUpdate);
    onUpdate.mockClear();
  });

  it.each([OLD_PRICE, null])('clears a cached quote when a token becomes trash (provider price %s)', async (price) => {
    await pollPosition(false, OLD_PRICE);
    expect(getTokenBySlug(TOKEN_SLUG)?.priceUsd).toBe(OLD_PRICE);
    onUpdate.mockClear();

    const { balances } = await pollPosition(true, price);

    expect(balances[TOKEN_SLUG]).toBe(100000000000000n);
    expect(getTokenBySlug(TOKEN_SLUG)?.priceUsd).toBe(0);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      kind: 'partial',
      tokens: expect.objectContaining({ [TOKEN_SLUG]: expect.objectContaining({ priceUsd: 0 }) }),
    }));
    expect(onUpdate.mock.lastCall![0].unpricedSlugs ?? []).not.toContain(TOKEN_SLUG);
  });

  it('sends a real zero on discovery so iOS can replace its separately persisted quote', async () => {
    await pollPosition(true, OLD_PRICE);

    expect(onUpdate.mock.lastCall![0].tokens[TOKEN_SLUG].priceUsd).toBe(0);
    expect(onUpdate.mock.lastCall![0].unpricedSlugs ?? []).not.toContain(TOKEN_SLUG);
  });

  it('preserves a cached quote when a non-trash token has no price', async () => {
    await pollPosition(false, OLD_PRICE);
    await pollPosition(false, null);

    expect(getTokenBySlug(TOKEN_SLUG)?.priceUsd).toBe(OLD_PRICE);
  });

  it('keeps an explicit backend quote ahead of the provider trash flag', async () => {
    await pollPosition(false, OLD_PRICE);
    jest.mocked(callBackendGet).mockResolvedValueOnce([{ ...getTokenBySlug(TOKEN_SLUG)!, priceUsd: 2 }]);
    await updateTokensFromBackend(onUpdate);
    await pollPosition(true, OLD_PRICE);

    expect(getTokenBySlug(TOKEN_SLUG)?.priceUsd).toBe(2);
  });

  it('keeps a backend zero when later balance responses quote a positive price', async () => {
    await pollPosition(false, OLD_PRICE);
    await updateTokens([], sendUpdate, [{ slug: TOKEN_SLUG, priceUsd: 0, percentChange24h: 0 }], true);
    await pollPosition(false, OLD_PRICE);

    expect(getTokenBySlug(TOKEN_SLUG)?.priceUsd).toBe(0);
  });

  async function pollPosition(isTrash: boolean, price: number | null) {
    const response: ZerionPositionsResponse = {
      links: { self: 'https://example.com/positions' },
      data: [{
        type: 'positions',
        id: 'privacy-coin-position',
        attributes: {
          parent: null,
          protocol: null,
          name: 'Privacy Coin',
          position_type: 'wallet',
          quantity: { int: '100000000000000', decimals: 8, float: 1000000, numeric: '1000000' },
          value: price === null ? null : price * 1000000,
          price,
          changes: null,
          fungible_info: {
            name: 'Privacy Coin',
            symbol: 'PVC',
            icon: null,
            flags: { verified: false },
            implementations: [{ chain_id: 'ethereum', address: TOKEN_ADDRESS, decimals: 8 }],
          },
          flags: { displayable: true, is_trash: isTrash },
          updated_at: '2026-09-21T00:00:00Z',
          updated_at_block: 1,
        },
        relationships: {
          chain: { links: { related: '' }, data: { type: 'chains', id: 'ethereum' } },
          fungible: { links: { related: '' }, data: { type: 'fungibles', id: 'privacy-coin' } },
        },
      }],
    };
    jest.mocked(fetchWithRetry).mockResolvedValueOnce({
      headers: { get: () => null },
      json: () => Promise.resolve(response),
    } as unknown as Response);
    return fetchAccountAssets('ethereum', 'mainnet', WALLET_ADDRESS, sendUpdate);
  }
});
