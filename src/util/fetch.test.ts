import type { ApiBackendConfig } from '../api/types';

import { DEFAULT_RETRIES } from '../config';
import { setBackendConfigCache } from '../api/common/cache';
import {
  classifyFetchFailure,
  computeRetryBackoffMs,
  fetchWithRetry,
  isNegativeCacheableStatus,
  resetFetchStateForTests,
} from './fetch';

// Pauses between retries are irrelevant to what we assert (call counts, classification, caching)
// and would otherwise make the retry tests wall-clock slow. Everything else stays real.
jest.mock('./schedulers', () => ({
  ...jest.requireActual('./schedulers'),
  pause: jest.fn(() => Promise.resolve()),
}));

function mockResponse(status: number, body: AnyLiteral = {}, headers: Record<string, string> = {}): Response {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: () => Promise.resolve(body),
    headers: {
      get: (name: string) => headers[name.toLowerCase()] ?? headers[name] ?? undefined,
    },
  } as unknown as Response;
}

function setNegVerdictCacheFlag(enabled: boolean) {
  setBackendConfigCache({ isNegVerdictCacheEnabled: enabled } as unknown as ApiBackendConfig);
}

const BURN_URL = 'https://evmapi.mytonwallet.org/v1/wallets/0xdead/transactions/?page[size]=50';
const OTHER_URL = 'https://evmapi.mytonwallet.org/v1/wallets/0xbeef/transactions/?page[size]=50';

describe('classifyFetchFailure', () => {
  it.each([undefined, 408, 429, 500, 502, 503, 504])('treats %s as retryable', (status) => {
    expect(classifyFetchFailure(status)).toBe('retryable');
  });

  it.each([400, 401, 403, 404, 405, 410, 422, 451])('treats %s as terminal', (status) => {
    expect(classifyFetchFailure(status)).toBe('terminal');
  });
});

describe('isNegativeCacheableStatus', () => {
  it.each([400, 404, 422])('caches %s', (status) => {
    expect(isNegativeCacheableStatus(status)).toBe(true);
  });

  it.each([undefined, 401, 403, 429, 500])('does not cache %s', (status) => {
    expect(isNegativeCacheableStatus(status)).toBe(false);
  });
});

describe('computeRetryBackoffMs', () => {
  it('stays within [0, min(MAX, BASE * 2^attempt)] across samples', () => {
    for (let attempt = 1; attempt <= 6; attempt++) {
      const ceiling = Math.min(10000, 500 * 2 ** attempt);
      for (let i = 0; i < 200; i++) {
        const backoff = computeRetryBackoffMs(attempt);
        expect(backoff).toBeGreaterThanOrEqual(0);
        expect(backoff).toBeLessThanOrEqual(ceiling);
      }
    }
  });
});

describe('fetchWithRetry negative-verdict cache', () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    resetFetchStateForTests();
    fetchMock = jest.fn();
    (global as unknown as { fetch: jest.Mock }).fetch = fetchMock;
    setNegVerdictCacheFlag(false);
  });

  it('collapses a deterministic-400 storm to a single upstream call when enabled', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'untrackable wallet address' }));

    for (let i = 0; i < 25; i++) {
      await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 400 });
    }

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('keys the cache by exact URL - a different address still hits upstream once', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'untrackable wallet address' }));

    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 400 });
    await expect(fetchWithRetry(OTHER_URL)).rejects.toMatchObject({ statusCode: 400 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not cache when the flag is off - every repeat hits upstream', async () => {
    setNegVerdictCacheFlag(false);
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'untrackable wallet address' }));

    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 400 });
    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 400 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not cache non-evmapi origins even when enabled (scope is evmapi-only)', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'bad' }));
    const nonEvmUrl = 'https://tonapiio.mytonwallet.org/v2/accounts/0xdead?x=1';

    await expect(fetchWithRetry(nonEvmUrl)).rejects.toMatchObject({ statusCode: 400 });
    await expect(fetchWithRetry(nonEvmUrl)).rejects.toMatchObject({ statusCode: 400 });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('never caches 401 even when enabled - a transient auth state is not masked', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(401, { error: 'unauthorized' }));

    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 401 });
    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 401 });

    // 401 is terminal (one attempt each) but NOT cached, so the second call still hits upstream.
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('retries a 503 and never caches it', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(503, { error: 'unavailable' }));

    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 503 });
    expect(fetchMock).toHaveBeenCalledTimes(DEFAULT_RETRIES);

    fetchMock.mockClear();
    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 503 });
    expect(fetchMock).toHaveBeenCalledTimes(DEFAULT_RETRIES);
  });
});
