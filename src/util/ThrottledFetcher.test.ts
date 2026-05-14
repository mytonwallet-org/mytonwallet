import { fetchWithThrottledProvider, resetThrottledProviderFetchers } from './ThrottledFetcher';

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
});
