import type { ApiToken } from '../types';

import { callBackendGet } from '../common/backend';
import { getTokenBySlug } from '../common/tokens';
import { fetchPriceHistory } from './prices';

jest.mock('../common/backend', () => ({ callBackendGet: jest.fn() }));
jest.mock('../common/tokens', () => ({
  tokensPreload: { promise: Promise.resolve() },
  getTokenBySlug: jest.fn(),
}));

const TOKEN: ApiToken = {
  slug: 'ton-eqb4iwqwzp',
  name: 'Tesla xStock',
  symbol: 'TSLAx',
  decimals: 8,
  chain: 'ton',
  tokenAddress: 'EQB4IwqWZPUczntdry8vSN2tsJKt-9F7iIb7gEFREYYOB563',
};
const HISTORY = [[1, 399], [2, 400]];

beforeEach(() => {
  jest.mocked(getTokenBySlug).mockReset();
  jest.mocked(callBackendGet).mockReset().mockResolvedValue(HISTORY);
});

it('fetches a search token absent from the SDK cache using its supplied identity', async () => {
  await expect(fetchPriceHistory(TOKEN.slug, '1D', 'EUR', TOKEN)).resolves.toEqual(HISTORY);
  expect(callBackendGet).toHaveBeenCalledWith(
    `/prices/chart/${encodeURIComponent(`ton:${TOKEN.tokenAddress}`)}`,
    { base: 'EUR', period: '1D' },
  );
});

it('prefers the SDK identity and preserves the three-argument API', async () => {
  jest.mocked(getTokenBySlug).mockReturnValue({ ...TOKEN, priceUsd: 400, percentChange24h: 0 });
  await expect(fetchPriceHistory(TOKEN.slug, '7D')).resolves.toEqual(HISTORY);
  await fetchPriceHistory(TOKEN.slug, '7D', 'USD', { ...TOKEN, tokenAddress: 'stale-address' });
  expect(callBackendGet).toHaveBeenNthCalledWith(
    2, `/prices/chart/${encodeURIComponent(`ton:${TOKEN.tokenAddress}`)}`, { base: 'USD', period: '7D' },
  );
});

it('rejects an unresolved token instead of reporting successful empty history', async () => {
  await expect(fetchPriceHistory(TOKEN.slug, '1D')).rejects.toThrow('Token not found');
  expect(callBackendGet).not.toHaveBeenCalled();
});

it('uses the symbol for a native token and encodes its asset identity as one path segment', async () => {
  await fetchPriceHistory('native-token', '1D', 'USD', { chain: 'ton', symbol: 'TON/path?query#fragment' });
  expect(callBackendGet).toHaveBeenCalledWith(
    '/prices/chart/ton%3ATON%2Fpath%3Fquery%23fragment', { base: 'USD', period: '1D' },
  );
});

it('distinguishes a genuinely empty backend response from a failed request', async () => {
  jest.mocked(callBackendGet).mockResolvedValueOnce([]).mockRejectedValueOnce(new Error('Network unavailable'));
  await expect(fetchPriceHistory(TOKEN.slug, '1D', 'USD', TOKEN)).resolves.toEqual([]);
  await expect(fetchPriceHistory(TOKEN.slug, '1D', 'USD', TOKEN)).rejects.toThrow('Network unavailable');
});
