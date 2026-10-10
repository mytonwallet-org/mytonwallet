import type { ZerionPositionsResponse } from './types';

import { fetchWithRetry } from '../../../util/fetch';
import { updateTokens } from '../../common/tokens';
import { fetchAccountAssets, fetchCrosschainAccountAssets } from './wallet';

jest.mock('../../../util/fetch', () => ({
  fetchWithRetry: jest.fn(),
  buildRequestUrl: jest.fn((url: string) => new URL(url)),
}));

jest.mock('../../common/tokens', () => ({
  updateTokens: jest.fn(),
  buildTokenSlug: jest.fn((chain: string, address: string) => `${chain}-${address}`),
  waitForTokenSlugResolver: jest.fn().mockResolvedValue(
    (tokens: { chain: string; address: string }[]) => tokens.map(({ chain, address }) => `${chain}-${address}`),
  ),
}));

const mockedFetch = jest.mocked(fetchWithRetry);

/** The positions fetcher reads the body and the gateway's observation header off one response. */
function positionsResponse(body: ZerionPositionsResponse, snapshotAt?: string, date?: string) {
  const headers: Record<string, string | undefined> = { 'X-Snapshot-At': snapshotAt, Date: date };

  return {
    headers: { get: (name: string) => headers[name] },
    json: () => Promise.resolve(body),
  } as unknown as Response;
}
const mockedUpdateTokens = jest.mocked(updateTokens);

const NETWORK = 'mainnet';
const ADDRESS_A = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';
const ADDRESS_B = '0x1111111111111111111111111111111111111111';

const EMPTY_RESPONSE: ZerionPositionsResponse = {
  links: { self: 'https://example.com' },
  data: [],
};

/** Creates a manually controllable promise so a fetch can be held in-flight while a second call arrives. */
function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe('fetchAccountAssets in-flight coalescing', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedUpdateTokens.mockResolvedValue(undefined);
  });

  it('coalesces two concurrent identical fetches into a single request', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const first = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const second = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));

    const [firstResult, secondResult] = await Promise.all([first, second]);

    expect(mockedFetch).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('coalesces concurrent fetches for the same address in different casing', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const checksummed = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const lowercased = fetchAccountAssets('bnb', NETWORK, ADDRESS_A.toLowerCase(), sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));

    const [firstResult, secondResult] = await Promise.all([checksummed, lowercased]);

    expect(mockedFetch).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('does not coalesce concurrent fetches for different addresses', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const sendUpdateTokens = jest.fn();
    await Promise.all([
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
      fetchAccountAssets('bnb', NETWORK, ADDRESS_B, sendUpdateTokens),
    ]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('does not attach a signalled request to the shared UI in-flight request', async () => {
    const uiRequest = createDeferred<Response>();
    const agentRequest = createDeferred<Response>();
    mockedFetch
      .mockReturnValueOnce(uiRequest.promise as unknown as Promise<Response>)
      .mockReturnValueOnce(agentRequest.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const uiPromise = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const controller = new AbortController();
    const agentPromise = fetchAccountAssets(
      'bnb',
      NETWORK,
      ADDRESS_A,
      sendUpdateTokens,
      { signal: controller.signal },
    );

    uiRequest.resolve(positionsResponse(EMPTY_RESPONSE));
    agentRequest.resolve(positionsResponse(EMPTY_RESPONSE));
    await Promise.all([uiPromise, agentPromise]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
    expect(mockedFetch.mock.calls[0][1]).toBeUndefined();
    expect(mockedFetch.mock.calls[1][1]).toHaveProperty('signal', controller.signal);
  });

  it('re-invokes the request for a new call after the first one settles (not a result cache)', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const sendUpdateTokens = jest.fn();
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(1);

    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('does not coalesce a single-chain ethereum fetch with a cross-chain fetch for the same address', async () => {
    const deferred = createDeferred<Response>();
    mockedFetch.mockReturnValue(deferred.promise as unknown as Promise<Response>);

    const sendUpdateTokens = jest.fn();
    const singleChain = fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, sendUpdateTokens);
    const crossChain = fetchCrosschainAccountAssets(NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(positionsResponse(EMPTY_RESPONSE));
    await Promise.all([singleChain, crossChain]);

    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });

  it('clears the key after a rejection so the next call retries', async () => {
    mockedFetch.mockRejectedValueOnce(new Error('network error'));

    const sendUpdateTokens = jest.fn();
    await expect(
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
    ).rejects.toThrow('network error');
    expect(mockedFetch).toHaveBeenCalledTimes(1);

    mockedFetch.mockResolvedValueOnce(positionsResponse(EMPTY_RESPONSE));
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetch).toHaveBeenCalledTimes(2);
  });
});

describe('fetchAccountAssets provenance', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedUpdateTokens.mockResolvedValue(undefined);
  });

  // A test that fails mid-way must not leave fake timers behind for the next one.
  afterEach(() => {
    jest.useRealTimers();
  });

  it('reports the instant the gateway observed the page', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, '1787738529000'));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBe(1787738529000);
  });

  it('reports no instant when the gateway states none', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBeUndefined();
  });

  it('reports no instant when the stated one sits beyond the tolerated clock skew', async () => {
    const farFuture = String(Date.now() + 60 * 60 * 1000);
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, farFuture));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBeUndefined();
  });

  it('reports no instant when the stated one is not a positive number', async () => {
    mockedFetch.mockResolvedValue(positionsResponse(EMPTY_RESPONSE, '0'));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBeUndefined();
  });

  it('states the instant on this device\'s clock when the gateway clock runs behind it', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-08-26T12:00:00.000Z'));

    // The gateway is ten minutes behind this device and served a page it observed 30s earlier.
    const gatewayNow = Date.now() - 10 * 60_000;
    mockedFetch.mockResolvedValue(positionsResponse(
      EMPTY_RESPONSE,
      String(gatewayNow - 30_000),
      new Date(gatewayNow).toUTCString(),
    ));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, jest.fn());

    expect(result.asOf).toBe(Date.now() - 30_000);
  });

  it('states the instant on this device\'s clock when the gateway clock runs ahead of it', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-08-26T12:00:00.000Z'));

    // The same page, from a gateway whose clock is an hour ahead: uncorrected it would outrank
    // every socket delta, and the far-future guard would throw the instant away entirely.
    const gatewayNow = Date.now() + 60 * 60_000;
    mockedFetch.mockResolvedValue(positionsResponse(
      EMPTY_RESPONSE,
      String(gatewayNow - 30_000),
      new Date(gatewayNow).toUTCString(),
    ));

    const result = await fetchAccountAssets('bnb', NETWORK, ADDRESS_B, jest.fn());

    expect(result.asOf).toBe(Date.now() - 30_000);
  });
});
