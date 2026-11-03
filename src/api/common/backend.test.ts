const mockFetchJson = jest.fn();
const mockFetchWithTimeout = jest.fn();
const mockFetchWithRetry = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  BRILLIANT_API_BASE_URL: 'https://api.example.test',
}));

jest.mock('../../util/fetch', () => ({
  buildRequestUrl: (url: URL, data?: Record<string, string>) => {
    const result = new URL(url);
    for (const [key, value] of Object.entries(data ?? {})) result.searchParams.set(key, value);
    return result;
  },
  fetchJson: (...args: unknown[]) => mockFetchJson(...args),
  fetchWithTimeout: (...args: unknown[]) => mockFetchWithTimeout(...args),
  fetchWithRetry: (...args: unknown[]) => mockFetchWithRetry(...args),
  handleFetchErrors: (response: Response) => Promise.resolve(response),
}));

jest.mock('../environment', () => ({
  getEnvironment: () => ({
    apiHeaders: {},
  }),
}));

jest.mock('./other', () => ({
  getClientId: () => 'test-client-id',
}));

describe('backend API helpers', () => {
  beforeEach(() => {
    mockFetchJson.mockResolvedValue({});
  });

  afterEach(() => {
    mockFetchJson.mockReset();
    mockFetchWithTimeout.mockReset();
    mockFetchWithRetry.mockReset();
  });

  it('uses per-endpoint circuit breaker buckets for backend GET requests', async () => {
    const { callBackendGet } = await import('./backend');

    await callBackendGet('/swap/assets');

    expect(mockFetchJson).toHaveBeenCalledWith(
      expect.any(URL),
      undefined,
      expect.any(Object),
      { bucketKey: 'https://api.example.test/swap' },
    );
  });

  it('returns the raw response status with a single attempt and query parameters for sync', async () => {
    const { callBackendGet } = await import('./backend');
    const response = { status: 202 };
    mockFetchWithRetry.mockResolvedValueOnce(response);
    const controller = new AbortController();

    await expect(callBackendGet('/nfts/ton/mainnet/owner', { since: 'opaque-token' }, undefined,
      controller.signal, { shouldReturnResponse: true, shouldRetry: false, timeout: 25000 })).resolves.toBe(response);

    expect(mockFetchWithRetry).toHaveBeenCalledWith(
      new URL('https://api.example.test/nfts/ton/mainnet/owner?since=opaque-token'),
      expect.objectContaining({ signal: controller.signal }),
      { bucketKey: 'https://api.example.test/nfts', retries: 1, timeouts: 25000 },
    );
  });

  it('forwards text response options with backend headers, query parameters and cancellation', async () => {
    const { callBackendGet } = await import('./backend');
    const body = '{ "assets": [] }';
    const data = { chain: 'ton' };
    const controller = new AbortController();
    mockFetchJson.mockResolvedValue(body);

    await expect(callBackendGet('/swap/assets', data, { 'X-Custom': 'catalog' }, controller.signal, {
      shouldReturnText: true,
    })).resolves.toBe(body);

    expect(mockFetchJson).toHaveBeenCalledWith(
      expect.any(URL),
      data,
      {
        headers: expect.objectContaining({
          'X-Custom': 'catalog',
          'X-App-ClientID': 'test-client-id',
        }),
        signal: controller.signal,
      },
      { bucketKey: 'https://api.example.test/swap', shouldReturnText: true },
    );
    expect(mockFetchJson.mock.calls[0][0].toString()).toBe('https://api.example.test/swap/assets');
  });

  it('reports received headers before a slow response body finishes', async () => {
    const { callBackendPost } = await import('./backend');
    let resolveBody!: (value: unknown) => void;
    let headersReceived!: () => void;
    const headers = new Promise<void>((resolve) => {
      headersReceived = resolve;
    });
    const body = new Promise((resolve) => {
      resolveBody = resolve;
    });
    mockFetchWithTimeout.mockResolvedValue({ status: 200, json: () => body });
    const onHeaders = jest.fn(() => headersReceived());
    let completed = false;

    const request = callBackendPost('/swap/estimate', {}, { onHeaders }).then((value) => {
      completed = true;
      return value;
    });
    await headers;
    expect(onHeaders).toHaveBeenCalledWith(200);
    expect(completed).toBe(false);

    const quote = { route: 'cex', toAmount: '0', fromMin: '30.03' };
    resolveBody(quote);
    expect(await request).toBe(quote);
  });
});
