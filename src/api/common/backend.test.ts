const mockFetchJson = jest.fn();
const mockFetchWithTimeout = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  BRILLIANT_API_BASE_URL: 'https://api.example.test',
}));

jest.mock('../../util/fetch', () => ({
  fetchJson: (...args: unknown[]) => mockFetchJson(...args),
  fetchWithTimeout: (...args: unknown[]) => mockFetchWithTimeout(...args),
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
