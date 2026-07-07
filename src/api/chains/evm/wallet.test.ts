import type { ZerionPositionsResponse } from './types';

import { fetchJson } from '../../../util/fetch';
import { updateTokens } from '../../common/tokens';
import { fetchAccountAssets, fetchCrosschainAccountAssets } from './wallet';

jest.mock('../../../util/fetch', () => ({
  fetchJson: jest.fn(),
}));

jest.mock('../../common/tokens', () => ({
  updateTokens: jest.fn(),
  buildTokenSlug: jest.fn((chain: string, address: string) => `${chain}-${address}`),
}));

const mockedFetchJson = jest.mocked(fetchJson);
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
    const deferred = createDeferred<ZerionPositionsResponse>();
    mockedFetchJson.mockReturnValue(deferred.promise as ReturnType<typeof fetchJson>);

    const sendUpdateTokens = jest.fn();
    const first = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const second = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(EMPTY_RESPONSE);

    const [firstResult, secondResult] = await Promise.all([first, second]);

    expect(mockedFetchJson).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('coalesces concurrent fetches for the same address in different casing', async () => {
    const deferred = createDeferred<ZerionPositionsResponse>();
    mockedFetchJson.mockReturnValue(deferred.promise as ReturnType<typeof fetchJson>);

    const sendUpdateTokens = jest.fn();
    const checksummed = fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    const lowercased = fetchAccountAssets('bnb', NETWORK, ADDRESS_A.toLowerCase(), sendUpdateTokens);

    deferred.resolve(EMPTY_RESPONSE);

    const [firstResult, secondResult] = await Promise.all([checksummed, lowercased]);

    expect(mockedFetchJson).toHaveBeenCalledTimes(1);
    expect(secondResult).toBe(firstResult);
  });

  it('does not coalesce concurrent fetches for different addresses', async () => {
    mockedFetchJson.mockResolvedValue(EMPTY_RESPONSE);

    const sendUpdateTokens = jest.fn();
    await Promise.all([
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
      fetchAccountAssets('bnb', NETWORK, ADDRESS_B, sendUpdateTokens),
    ]);

    expect(mockedFetchJson).toHaveBeenCalledTimes(2);
  });

  it('re-invokes fetchJson for a new call after the first one settles (not a result cache)', async () => {
    mockedFetchJson.mockResolvedValue(EMPTY_RESPONSE);

    const sendUpdateTokens = jest.fn();
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);

    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetchJson).toHaveBeenCalledTimes(2);
  });

  it('does not coalesce a single-chain ethereum fetch with a cross-chain fetch for the same address', async () => {
    const deferred = createDeferred<ZerionPositionsResponse>();
    mockedFetchJson.mockReturnValue(deferred.promise as ReturnType<typeof fetchJson>);

    const sendUpdateTokens = jest.fn();
    const singleChain = fetchAccountAssets('ethereum', NETWORK, ADDRESS_A, sendUpdateTokens);
    const crossChain = fetchCrosschainAccountAssets(NETWORK, ADDRESS_A, sendUpdateTokens);

    deferred.resolve(EMPTY_RESPONSE);
    await Promise.all([singleChain, crossChain]);

    expect(mockedFetchJson).toHaveBeenCalledTimes(2);
  });

  it('clears the key after a rejection so the next call retries', async () => {
    mockedFetchJson.mockRejectedValueOnce(new Error('network error'));

    const sendUpdateTokens = jest.fn();
    await expect(
      fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens),
    ).rejects.toThrow('network error');
    expect(mockedFetchJson).toHaveBeenCalledTimes(1);

    mockedFetchJson.mockResolvedValueOnce(EMPTY_RESPONSE);
    await fetchAccountAssets('bnb', NETWORK, ADDRESS_A, sendUpdateTokens);
    expect(mockedFetchJson).toHaveBeenCalledTimes(2);
  });
});
