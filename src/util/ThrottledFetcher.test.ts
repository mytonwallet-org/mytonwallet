import { TONAPIIO_MAINNET_URL } from '../config';
import { createUrgentFetchDemand, FetchDemand } from './fetchDemand';
import { withFetchDemandCacheAsync } from './withCacheAsync';

import {
  fetchWithThrottledProvider,
  getProviderFetchRetryPolicy,
  resetThrottledProviderFetchers,
  ThrottledFetcher,
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

  it('caps a provider Retry-After pause so one 429 cannot park the origin', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock
      .mockResolvedValueOnce({
        status: 429,
        ok: false,
        headers: {
          get: (name: string) => (name === 'Retry-After' ? '3600' : undefined),
        },
      } as unknown as Response)
      .mockResolvedValueOnce({
        status: 200,
        ok: true,
        headers: {
          get: () => undefined,
        },
      } as unknown as Response);

    const url = `${TONAPIIO_MAINNET_URL}/v2/rates`;
    // A timeout above the cap: this test is about the pause itself, not about the caller deadline.
    await fetchWithThrottledProvider(url, undefined, 60000);

    const second = fetchWithThrottledProvider(url, undefined, 60000);

    await jest.advanceTimersByTimeAsync(29999);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    await second;
  });

  it('counts the queue wait against the caller timeout', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock.mockResolvedValue({ ok: true } as Response);
    const fetcher = new ThrottledFetcher(30000, 1000);

    await fetcher.fetch('https://example.com');

    // Queued behind a 30-second spacing, with a 1-second deadline of its own.
    const queued = fetcher.fetch('https://example.com');
    const expectation = expect(queued).rejects.toMatchObject({ name: 'TimeoutError' });

    await jest.advanceTimersByTimeAsync(1000);

    await expectation;
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('should apply the provider retry policy to tonapi origins', () => {
    expect(getProviderFetchRetryPolicy(`${TONAPIIO_MAINNET_URL}/v2/rates`)).toEqual({
      retries: 6,
      fallbackRetryAfterMs: 5000,
    });
  });

  it('removes a cancelled request from the queue without poisoning later requests', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock.mockResolvedValue({ ok: true } as Response);
    const fetcher = new ThrottledFetcher(1000);

    await fetcher.fetch('https://example.com');

    const controller = new AbortController();
    const reason = new Error('cancel queued request');
    const cancelled = fetcher.fetch('https://example.com', { signal: controller.signal });
    await Promise.resolve();
    controller.abort(reason);
    await expect(cancelled).rejects.toBe(reason);

    const next = fetcher.fetch('https://example.com');
    await jest.advanceTimersByTimeAsync(1000);
    await next;

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('rejects a cancelled request while it is queued behind another request', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock.mockResolvedValue({ ok: true } as Response);
    const fetcher = new ThrottledFetcher(1000);

    await fetcher.fetch('https://example.com');

    const preceding = fetcher.fetch('https://example.com');
    const controller = new AbortController();
    const reason = new Error('cancel request behind pending');
    const cancelled = fetcher.fetch('https://example.com', { signal: controller.signal });
    await Promise.resolve();

    controller.abort(reason);
    await expect(cancelled).rejects.toBe(reason);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1000);
    await preceding;
    await Promise.resolve();

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('distinguishes caller abort reasons from request timeouts', async () => {
    const fetchMock = global.fetch as jest.Mock;
    fetchMock.mockImplementation((_input, init: RequestInit) => new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(init.signal?.reason), { once: true });
    }));
    const fetcher = new ThrottledFetcher(0, 1000);
    const controller = new AbortController();
    const callerReason = new Error('caller stopped');
    const callerRequest = fetcher.fetch('https://example.com', { signal: controller.signal });
    const callerExpectation = expect(callerRequest).rejects.toBe(callerReason);
    controller.abort(callerReason);
    await callerExpectation;

    const timedOut = fetcher.fetch('https://example.com');
    const timeoutExpectation = expect(timedOut).rejects.toMatchObject({ name: 'TimeoutError' });
    await jest.advanceTimersByTimeAsync(1000);
    await timeoutExpectation;
  });

  describe('demands', () => {
    const URL = 'https://example.com';

    function getRequestedUrls() {
      return (global.fetch as jest.Mock).mock.calls.map(([input]) => String(input));
    }

    beforeEach(() => {
      (global.fetch as jest.Mock).mockResolvedValue({ ok: true } as Response);
    });

    it('dispatches the requests of an urgent demand ahead of the queued background ones', async () => {
      const fetcher = new ThrottledFetcher(100);
      const urgent = createUrgentFetchDemand();

      await fetcher.fetch(`${URL}/first`);
      const requests = [
        fetcher.fetch(`${URL}/background-1`),
        fetcher.fetch(`${URL}/background-2`),
        fetcher.fetch(`${URL}/urgent-1`, undefined, undefined, urgent),
        fetcher.fetch(`${URL}/urgent-2`, undefined, undefined, urgent),
      ];

      await jest.advanceTimersByTimeAsync(400);
      await Promise.all(requests);

      expect(getRequestedUrls()).toEqual([
        `${URL}/first`,
        `${URL}/urgent-1`,
        `${URL}/urgent-2`,
        `${URL}/background-1`,
        `${URL}/background-2`,
      ]);
    });

    it('keeps the spacing between the requests of an urgent demand', async () => {
      const fetcher = new ThrottledFetcher(100);
      const urgent = createUrgentFetchDemand();

      await fetcher.fetch(`${URL}/first`);
      const request = fetcher.fetch(`${URL}/urgent`, undefined, undefined, urgent);

      await jest.advanceTimersByTimeAsync(99);
      expect(getRequestedUrls()).toEqual([`${URL}/first`]);

      await jest.advanceTimersByTimeAsync(1);
      await request;
      expect(getRequestedUrls()).toEqual([`${URL}/first`, `${URL}/urgent`]);
    });

    it('moves a queued request ahead once an urgent demand starts waiting for it', async () => {
      const fetcher = new ThrottledFetcher(100);
      const shared = new FetchDemand();
      const urgent = createUrgentFetchDemand();

      await fetcher.fetch(`${URL}/first`);
      const background = fetcher.fetch(`${URL}/background`);
      const sharedRequest = fetcher.fetch(`${URL}/shared`, undefined, undefined, shared);
      const waiting = urgent.waitFor(shared, sharedRequest);

      await jest.advanceTimersByTimeAsync(200);
      await Promise.all([background, waiting]);

      expect(getRequestedUrls()).toEqual([`${URL}/first`, `${URL}/shared`, `${URL}/background`]);
    });

    it('moves the requests of a cached call ahead when an urgent caller waits for it', async () => {
      const fetcher = new ThrottledFetcher(100);
      const urgent = createUrgentFetchDemand();
      // Two requests in a row, like a get method that is followed by another one on the minter
      const resolveTokenWallet = withFetchDemandCacheAsync(async (demand, address: string) => {
        await fetcher.fetch(`${URL}/${address}/wallet-data`, undefined, undefined, demand);
        await fetcher.fetch(`${URL}/${address}/minter`, undefined, undefined, demand);
        return address;
      });

      await fetcher.fetch(`${URL}/first`);
      // Background polling has requests queued, starts the shared work behind them, then queues more of its own
      const polling = [
        fetcher.fetch(`${URL}/polling-1`),
        fetcher.fetch(`${URL}/polling-2`),
      ];
      const fromPolling = resolveTokenWallet('jetton');
      polling.push(fetcher.fetch(`${URL}/polling-3`));
      const fromDapp = resolveTokenWallet('jetton', urgent);

      await jest.advanceTimersByTimeAsync(600);
      await Promise.all([fromPolling, fromDapp, ...polling]);

      expect(getRequestedUrls()).toEqual([
        `${URL}/first`,
        `${URL}/jetton/wallet-data`,
        `${URL}/jetton/minter`,
        `${URL}/polling-1`,
        `${URL}/polling-2`,
        `${URL}/polling-3`,
      ]);
    });

    it('lets a request fall back in line once the urgent caller stops waiting', async () => {
      const fetcher = new ThrottledFetcher(100);
      const shared = new FetchDemand();
      const urgent = createUrgentFetchDemand();
      let stopWaiting!: NoneToVoidFunction;

      await fetcher.fetch(`${URL}/first`);
      const background = fetcher.fetch(`${URL}/background`);
      const sharedRequest = fetcher.fetch(`${URL}/shared`, undefined, undefined, shared);
      void urgent.waitFor(shared, new Promise<void>((resolve) => {
        stopWaiting = resolve;
      }));
      stopWaiting();
      await Promise.resolve();

      await jest.advanceTimersByTimeAsync(200);
      await Promise.all([background, sharedRequest]);

      expect(getRequestedUrls()).toEqual([`${URL}/first`, `${URL}/background`, `${URL}/shared`]);
    });
  });
});
