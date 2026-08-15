import { TONAPIIO_MAINNET_URL } from '../config';

import {
  fetchWithThrottledProvider,
  getProviderFetchRetryPolicy,
  resetThrottledProviderFetchers,
} from './ThrottledFetcher';

describe('ThrottledFetcher', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    resetThrottledProviderFetchers();
    global.fetch = jest.fn() as any;
  });

  afterEach(() => {
    jest.useRealTimers();
    resetThrottledProviderFetchers();
    jest.restoreAllMocks();
  });

  it('should honor Retry-After delays for subsequent toncenter requests', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock
      .mockResolvedValueOnce({
        status: 429,
        ok: false,
        headers: {
          get: (name: string) => (name === 'Retry-After' ? '1' : undefined),
        },
      } as unknown as Response)
      .mockResolvedValueOnce({
        status: 200,
        ok: true,
        headers: {
          get: () => undefined,
        },
      } as unknown as Response);

    const url = 'https://toncenter-testnet.mytonwallet.org/api/v2/jsonRPC';

    await fetchWithThrottledProvider(url, { method: 'POST' });

    const secondPromise = fetchWithThrottledProvider(url, { method: 'POST' });
    await Promise.resolve();

    expect(fetchMock).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(999);
    await Promise.resolve();
    await Promise.resolve();
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    await secondPromise;
  });

  it('should honor Retry-After delays for subsequent tonapi requests', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock
      .mockResolvedValueOnce({
        status: 429,
        ok: false,
        headers: {
          get: (name: string) => (name === 'Retry-After' ? '1' : undefined),
        },
      } as unknown as Response)
      .mockResolvedValueOnce({
        status: 200,
        ok: true,
        headers: {
          get: () => undefined,
        },
      } as unknown as Response);

    const url = `${TONAPIIO_MAINNET_URL}/v2/accounts/EQDCH6vT0MFLki4LX3yGDLkTe6PJRJfNMwo3isyseTOSNKKC/nfts`;

    await fetchWithThrottledProvider(url);

    const secondPromise = fetchWithThrottledProvider(url);

    // Drains microtasks without moving the clock: an unthrottled second request would fire here.
    await jest.advanceTimersByTimeAsync(0);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(999);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    await secondPromise;
  });

  it('should apply the provider retry policy to tonapi origins', () => {
    expect(getProviderFetchRetryPolicy(`${TONAPIIO_MAINNET_URL}/v2/rates`)).toEqual({
      retries: 6,
      fallbackRetryAfterMs: 5000,
    });
  });
});
