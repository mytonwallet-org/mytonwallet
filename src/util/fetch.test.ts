import type { ApiBackendConfig } from '../api/types';

import { DEFAULT_RETRIES } from '../config';
import { setBackendConfigCache } from '../api/common/cache';
import { pauseWithAbortSignal } from './abortSignal';
import { CircuitOpenError } from './circuit-breaker';
import {
  classifyFetchFailure,
  computeRetryBackoffMs,
  fetchWithRetry,
  fetchWithTimeout,
  isNegativeCacheableStatus,
  resetFetchStateForTests,
} from './fetch';

// Pauses between retries are irrelevant to what we assert (call counts, classification, caching)
// and would otherwise make the retry tests wall-clock slow. Everything else stays real.
jest.mock('./abortSignal', () => ({
  ...jest.requireActual('./abortSignal'),
  pauseWithAbortSignal: jest.fn(() => Promise.resolve()),
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

describe('fetch cancellation', () => {
  beforeEach(() => {
    resetFetchStateForTests();
    (global as unknown as { fetch: jest.Mock }).fetch = jest.fn();
    const pauseMock = jest.mocked(pauseWithAbortSignal);
    pauseMock.mockReset();
    pauseMock.mockResolvedValue();
  });

  afterEach(() => {
    const pauseMock = jest.mocked(pauseWithAbortSignal);
    pauseMock.mockReset();
    pauseMock.mockResolvedValue();
  });

  it('preserves the caller abort reason through the timeout signal', async () => {
    const controller = new AbortController();
    const reason = new Error('agent run stopped');
    const fetchMock = global.fetch as jest.Mock;
    let markStarted!: () => void;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    fetchMock.mockImplementation((_url, init: RequestInit) => {
      markStarted();
      return new Promise((_resolve, reject) => {
        init.signal!.addEventListener('abort', () => reject(init.signal!.reason), { once: true });
      });
    });

    const request = fetchWithTimeout('https://example.com', { signal: controller.signal });
    await started;
    controller.abort(reason);

    await expect(request).rejects.toBe(reason);
    expect(fetchMock.mock.calls[0][1].signal.reason).toBe(reason);
  });

  it('stops before transport when the caller signal is already aborted', async () => {
    const controller = new AbortController();
    const reason = new Error('already stopped');
    controller.abort(reason);

    await expect(fetchWithRetry('https://example.com', { signal: controller.signal })).rejects.toBe(reason);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('stops retry backoff without starting another transport attempt', async () => {
    const controller = new AbortController();
    const reason = new Error('stop retrying');
    const fetchMock = global.fetch as jest.Mock;
    fetchMock.mockRejectedValue(new TypeError('network error'));
    jest.mocked(pauseWithAbortSignal).mockImplementation((_milliseconds, signal) => (
      new Promise((_resolve, reject) => {
        signal?.addEventListener('abort', () => reject(signal.reason), { once: true });
      })
    ));

    const request = fetchWithRetry('https://example.com', { signal: controller.signal }, { retries: 3 });
    for (let i = 0; i < 10 && jest.mocked(pauseWithAbortSignal).mock.calls.length === 0; i++) {
      await Promise.resolve();
    }
    expect(pauseWithAbortSignal).toHaveBeenCalledTimes(1);
    controller.abort(reason);

    await expect(request).rejects.toBe(reason);
    expect(fetchMock).toHaveBeenCalledTimes(1);
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

  it('does not replay or populate the shared verdict cache for a signalled request', async () => {
    setNegVerdictCacheFlag(true);
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'untrackable wallet address' }));

    await expect(fetchWithRetry(BURN_URL)).rejects.toMatchObject({ statusCode: 400 });

    const controller = new AbortController();
    await expect(fetchWithRetry(BURN_URL, { signal: controller.signal })).rejects.toMatchObject({ statusCode: 400 });

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

describe('fetchWithRetry breaker classification', () => {
  const VENDOR_URL = 'https://vendor.example/api/data';
  const BREAKER_FAILURE_THRESHOLD = 5;
  let fetchMock: jest.Mock;

  beforeEach(() => {
    resetFetchStateForTests();
    fetchMock = jest.fn();
    (global as unknown as { fetch: jest.Mock }).fetch = fetchMock;
    setNegVerdictCacheFlag(false);
  });

  it('opens the breaker on a sustained 429 storm - a vendor rate limit is a host-health failure', async () => {
    fetchMock.mockResolvedValue(mockResponse(429, { error: 'rate limit: limit for tier' }));

    for (let i = 0; i < BREAKER_FAILURE_THRESHOLD; i++) {
      await expect(fetchWithRetry(VENDOR_URL)).rejects.toMatchObject({ statusCode: 429 });
    }

    const upstreamCalls = fetchMock.mock.calls.length;
    await expect(fetchWithRetry(VENDOR_URL)).rejects.toBeInstanceOf(CircuitOpenError);
    expect(fetchMock).toHaveBeenCalledTimes(upstreamCalls);
  });

  it('never opens the breaker on a deterministic 400 - the host is alive, the request is wrong', async () => {
    fetchMock.mockResolvedValue(mockResponse(400, { error: 'bad request' }));

    for (let i = 0; i < BREAKER_FAILURE_THRESHOLD + 1; i++) {
      await expect(fetchWithRetry(VENDOR_URL)).rejects.toMatchObject({ statusCode: 400 });
    }

    // 400 is terminal (one attempt per call) and healthy - every call reaches upstream.
    expect(fetchMock).toHaveBeenCalledTimes(BREAKER_FAILURE_THRESHOLD + 1);
  });

  it.each([403, 401])('opens the breaker on a sustained %s storm - an upstream refusing everyone is not healthy',
    async (status) => {
      fetchMock.mockResolvedValue(mockResponse(status, {}));

      for (let i = 0; i < BREAKER_FAILURE_THRESHOLD; i++) {
        await expect(fetchWithRetry(VENDOR_URL)).rejects.toMatchObject({ statusCode: status });
      }

      const upstreamCalls = fetchMock.mock.calls.length;
      await expect(fetchWithRetry(VENDOR_URL)).rejects.toBeInstanceOf(CircuitOpenError);
      expect(fetchMock).toHaveBeenCalledTimes(upstreamCalls);
    });
});
