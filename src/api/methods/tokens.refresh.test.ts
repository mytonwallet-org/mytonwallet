import { callBackendGet } from '../common/backend';
import { getTokensCache, resumeTokenUpdates, sendUpdateTokens, tokensPreload } from '../common/tokens';
import { initTokens, refreshTokens } from './tokens';

jest.mock('../chains', () => ({}));
jest.mock('../db', () => ({
  tokenRepository: { bulkPut: jest.fn().mockResolvedValue(undefined) },
}));
jest.mock('../common/backend', () => ({
  callBackendGet: jest.fn(),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));
jest.mock('../storages', () => ({
  storage: { getItem: jest.fn().mockResolvedValue('en') },
}));

describe('refreshTokens', () => {
  const token = {
    slug: 'ton-refresh-cache', chain: 'ton', tokenAddress: 'EQRefreshCache',
    name: 'Cache test', symbol: 'CACHE', decimals: 9, priceUsd: 1, percentChange24h: 0,
  };

  beforeEach(() => {
    jest.mocked(callBackendGet).mockResolvedValue([token]);
    tokensPreload.resolve();
    resumeTokenUpdates();
  });

  it('restores unchanged tokens after the UI clears its cache', async () => {
    const onUpdate = jest.fn();
    initTokens(onUpdate);
    await refreshTokens();
    onUpdate.mockClear();

    sendUpdateTokens(onUpdate);
    expect(onUpdate).not.toHaveBeenCalled();

    await refreshTokens();

    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'updateTokens', kind: 'full',
      tokens: expect.objectContaining({ [token.slug]: expect.objectContaining(token) }),
    }));
  });

  it('keeps SDK tokens available when the network refresh fails', async () => {
    const onUpdate = jest.fn();
    initTokens(onUpdate);
    await refreshTokens();
    onUpdate.mockClear();
    jest.mocked(callBackendGet).mockRejectedValueOnce(new Error('offline'));

    await expect(refreshTokens()).rejects.toThrow('offline');

    expect(getTokensCache().bySlug[token.slug]).toEqual(expect.objectContaining(token));
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'updateTokens', kind: 'full',
      tokens: expect.objectContaining({ [token.slug]: expect.objectContaining(token) }),
    }));
  });
});
