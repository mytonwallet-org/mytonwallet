import type { JettonMetadata } from './types';
import { ApiTokenImportError } from '../../types';

import { HOUR } from '../../../util/dateFormat';
import Deferred from '../../../util/Deferred';

jest.mock('../../db', () => ({
  tokenRepository: {
    all: jest.fn().mockResolvedValue([]),
    bulkPut: jest.fn().mockResolvedValue(undefined),
  },
}));
jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));
jest.mock('./toncenter/other', () => ({
  callToncenterV3: jest.fn(),
  fetchMetadata: jest.fn().mockResolvedValue({}),
}));
jest.mock('./util/metadata', () => ({
  fetchJettonMetadata: jest.fn(),
  fixBase64ImageData: jest.fn(),
  parsePayloadBase64: jest.fn(),
}));
jest.mock('./priceless', () => ({
  updateTokenHashes: jest.fn().mockResolvedValue(undefined),
}));

const JETTON_ADDRESS = `0:${'a'.repeat(64)}`;
const OWNER_ADDRESS = `0:${'1'.repeat(64)}`;
const OTHER_OWNER_ADDRESS = `0:${'2'.repeat(64)}`;
const JETTON_METADATA: JettonMetadata = { name: 'Fallback Jetton', symbol: 'JET', decimals: '9' };
const UNINDEXED_RESPONSE = {
  jetton_wallets: [{ address: OWNER_ADDRESS, jetton: JETTON_ADDRESS, balance: '1000' }],
  metadata: {},
};
const INDEXED_RESPONSE = {
  ...UNINDEXED_RESPONSE,
  metadata: {
    [JETTON_ADDRESS]: {
      is_indexed: true,
      token_info: [{ type: 'jetton_masters', name: 'Indexed Jetton', symbol: 'IDX', extra: { decimals: '6' } }],
    },
  },
};

describe('TON fallback jetton metadata cache', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.useFakeTimers({ now: 1000 });
  });
  afterEach(() => {
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  it('reuses successful fallback metadata across consecutive balance sweeps and wallets', async () => {
    const { loadTokenBalances, fetchJettonMetadata, tokenAddress } = await prepareTest();

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(Object.values(balances)).toEqual([1000n]);
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);
    await expect(loadTokenBalances('mainnet', OTHER_OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);

    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);
    expect(fetchJettonMetadata).toHaveBeenCalledWith('mainnet', tokenAddress, undefined);
  });

  it('caches a resolved error for one hour, then caches a successful retry', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    fetchJettonMetadata.mockResolvedValueOnce({ error: ApiTokenImportError.AddressDoesNotExist });

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    await expect(loadTokenBalances('mainnet', OTHER_OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    jest.advanceTimersByTime(HOUR - 1);
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(1);
    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('calls get_jetton_data only once per hour when the minter returns exit code 9', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    const { TonClient } = await import('./util/TonClient');
    const { setEnvironment } = await import('../../environment');
    setEnvironment({});
    const actualMetadata = jest.requireActual<typeof import('./util/metadata')>('./util/metadata');
    fetchJettonMetadata.mockImplementation(actualMetadata.fetchJettonMetadata);
    const callRpc = jest.spyOn(TonClient.prototype, 'callRpc').mockResolvedValue({
      exit_code: 9, gas_used: 29709, stack: [['num', '0x0']],
    });

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    jest.advanceTimersByTime(HOUR - 1);
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(1);
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(2);
    expect(callRpc).toHaveBeenLastCalledWith('runGetMethod', expect.objectContaining({ method: 'get_jetton_data' }));
  });

  it.each([new TypeError('Failed to fetch'), new Error('Request timed out'), undefined])(
    'retries a rejected or empty fetch (%s) on the next sweep',
    async (error) => {
      const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
      if (error) {
        fetchJettonMetadata.mockRejectedValueOnce(error);
      } else {
        fetchJettonMetadata.mockResolvedValueOnce(undefined!);
      }

      await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
      expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);

      const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
      await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);

      expect(Object.values(balances)).toEqual([1000n]);
      expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
    },
  );

  it('starts the failure TTL when the fetch finishes', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    fetchJettonMetadata.mockImplementationOnce(() => {
      jest.advanceTimersByTime(HOUR);
      return Promise.resolve({ error: ApiTokenImportError.NotATokenAddress });
    });

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(HOUR);
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('expires fallback metadata one hour after the successful fetch', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();

    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    jest.advanceTimersByTime(HOUR - 1);
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(1);
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('uses indexed metadata without fetching fallback metadata', async () => {
    const {
      loadTokenBalances, callToncenterV3, fetchJettonMetadata, updateTokensFetchedTogether,
    } = await prepareTest();
    callToncenterV3.mockResolvedValue(INDEXED_RESPONSE);

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).not.toHaveBeenCalled();
    expect(updateTokensFetchedTogether).toHaveBeenLastCalledWith([
      expect.objectContaining({ name: 'Indexed Jetton', symbol: 'IDX', decimals: 6 }),
    ], expect.anything());
  });

  it('gives indexed metadata priority over a cached fallback', async () => {
    const {
      loadTokenBalances, callToncenterV3, fetchJettonMetadata, updateTokensFetchedTogether,
    } = await prepareTest();
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    callToncenterV3.mockResolvedValue(INDEXED_RESPONSE);

    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());

    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);
    expect(updateTokensFetchedTogether).toHaveBeenLastCalledWith([
      expect.objectContaining({ name: 'Indexed Jetton', symbol: 'IDX', decimals: 6 }),
    ], expect.anything());
  });

  it('replaces a cached failure with indexed metadata', async () => {
    const { loadTokenBalances, callToncenterV3, fetchJettonMetadata } = await prepareTest();
    fetchJettonMetadata.mockResolvedValueOnce({ error: ApiTokenImportError.NotATokenAddress });
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    callToncenterV3.mockResolvedValueOnce(INDEXED_RESPONSE);

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(1);
  });

  it.each([true, false])('keeps concurrent success over failure (failure first: %s)', async (shouldFailFirst) => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    const failure = new Deferred<{ error: ApiTokenImportError }>();
    const success = new Deferred<JettonMetadata>();
    const bothStarted = new Deferred();
    fetchJettonMetadata.mockImplementationOnce(() => failure.promise).mockImplementationOnce(() => {
      bothStarted.resolve();
      return success.promise;
    });

    const failedSweep = loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    const successfulSweep = loadTokenBalances('mainnet', OTHER_OWNER_ADDRESS, jest.fn());
    await bothStarted.promise;
    if (shouldFailFirst) {
      failure.resolve({ error: ApiTokenImportError.NotATokenAddress });
      await failedSweep;
      success.resolve(JETTON_METADATA);
    } else {
      success.resolve(JETTON_METADATA);
      await successfulSweep;
      failure.resolve({ error: ApiTokenImportError.NotATokenAddress });
    }
    await Promise.all([failedSweep, successfulSweep]);

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('retries a rejected refresh after successful fallback metadata expires', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    jest.advanceTimersByTime(HOUR);
    fetchJettonMetadata.mockRejectedValueOnce(new Error('Failed to refresh metadata'));

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);

    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(balances);
    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(3);
  });

  it('fetches fresh metadata for every manual token fetch even with a cached fallback', async () => {
    const { loadTokenBalances, fetchToken, fetchJettonMetadata, tokenAddress } = await prepareTest();
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    fetchJettonMetadata
      .mockResolvedValueOnce({ name: 'First Import' })
      .mockResolvedValueOnce({ name: 'Second Import' });

    await expect(fetchToken('mainnet', tokenAddress)).resolves.toMatchObject({ name: 'First Import' });
    await expect(fetchToken('mainnet', tokenAddress)).resolves.toMatchObject({ name: 'Second Import' });

    expect(fetchJettonMetadata).toHaveBeenCalledTimes(3);
  });

  it('replaces a cached failure when a manual token fetch succeeds', async () => {
    const { loadTokenBalances, fetchToken, fetchJettonMetadata } = await prepareTest();
    fetchJettonMetadata.mockResolvedValueOnce({ error: ApiTokenImportError.NotATokenAddress });
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});

    await expect(fetchToken('mainnet', JETTON_ADDRESS)).resolves.toMatchObject({ name: JETTON_METADATA.name });
    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('does not share in-flight metadata fetches or cancellation between callers', async () => {
    const { loadTokenBalances, fetchJettonMetadata, tokenAddress } = await prepareTest();
    const firstController = new AbortController();
    const secondController = new AbortController();
    const firstFetch = new Deferred<JettonMetadata>();
    const secondFetch = new Deferred<JettonMetadata>();
    const bothStarted = new Deferred();
    const abortError = new Error('First sweep cancelled');
    fetchJettonMetadata.mockImplementationOnce((_network, _address, signal) => {
      signal!.addEventListener('abort', () => firstFetch.reject(signal!.reason), { once: true });
      return firstFetch.promise;
    }).mockImplementationOnce(() => {
      bothStarted.resolve();
      return secondFetch.promise;
    });

    const sweeps = Promise.allSettled([
      loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn(), firstController.signal),
      loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn(), secondController.signal),
    ]);
    await bothStarted.promise;
    firstController.abort(abortError);
    secondFetch.resolve(JETTON_METADATA);
    const [firstSweep, secondSweep] = await sweeps;

    expect(fetchJettonMetadata).toHaveBeenNthCalledWith(1, 'mainnet', tokenAddress, firstController.signal);
    expect(fetchJettonMetadata).toHaveBeenNthCalledWith(2, 'mainnet', tokenAddress, secondController.signal);
    expect(firstSweep).toEqual({ status: 'rejected', reason: abortError });
    expect(secondSweep).toEqual({ status: 'fulfilled', value: expect.objectContaining({}) });
    if (secondSweep.status === 'fulfilled') expect(Object.values(secondSweep.value)).toEqual([1000n]);
    expect(secondController.signal.aborted).toBe(false);
  });

  it('does not cache metadata returned after the caller aborts', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    const controller = new AbortController();
    const abortError = new Error('Sweep cancelled');
    fetchJettonMetadata.mockImplementationOnce(() => {
      controller.abort(abortError);
      return Promise.resolve(JETTON_METADATA);
    });

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn(), controller.signal)).rejects.toBe(abortError);
    const balances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());

    expect(Object.values(balances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
  });

  it('keeps metadata for mainnet and testnet separate', async () => {
    const { loadTokenBalances, fetchJettonMetadata, tokenAddress, toBase64Address } = await prepareTest();

    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await loadTokenBalances('testnet', OWNER_ADDRESS, jest.fn());
    await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    await loadTokenBalances('testnet', OWNER_ADDRESS, jest.fn());

    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);
    expect(fetchJettonMetadata).toHaveBeenNthCalledWith(1, 'mainnet', tokenAddress, undefined);
    expect(fetchJettonMetadata).toHaveBeenNthCalledWith(
      2, 'testnet', toBase64Address(JETTON_ADDRESS, true, 'testnet'), undefined,
    );
  });

  it('does not let a mainnet failure suppress testnet metadata', async () => {
    const { loadTokenBalances, fetchJettonMetadata } = await prepareTest();
    fetchJettonMetadata.mockResolvedValueOnce({ error: ApiTokenImportError.NotATokenAddress });

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    const testnetBalances = await loadTokenBalances('testnet', OWNER_ADDRESS, jest.fn());
    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual({});
    await expect(loadTokenBalances('testnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(testnetBalances);

    expect(Object.values(testnetBalances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2);

    jest.advanceTimersByTime(HOUR);
    const mainnetBalances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(Object.values(mainnetBalances)).toEqual([1000n]);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(3);
  });

  it('fetches metadata for 2001 unindexed jettons once across two paginated sweeps', async () => {
    const { loadTokenBalances, callToncenterV3, fetchJettonMetadata } = await prepareTest();
    const wallets = Array.from({ length: 2001 }, (_, i) => ({
      address: OWNER_ADDRESS,
      jetton: `0:${i.toString(16).padStart(4, '0').padEnd(64, '0')}`,
      balance: '1000',
    }));
    callToncenterV3.mockImplementation((_network, _path, data) => {
      const { limit, offset } = data as { limit: number; offset: number };
      return Promise.resolve({ jetton_wallets: wallets.slice(offset, offset + limit), metadata: {} });
    });

    const firstBalances = await loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn());
    expect(Object.keys(firstBalances)).toHaveLength(2001);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2001);

    await expect(loadTokenBalances('mainnet', OWNER_ADDRESS, jest.fn())).resolves.toEqual(firstBalances);
    expect(fetchJettonMetadata).toHaveBeenCalledTimes(2001);
    expect(callToncenterV3).toHaveBeenCalledTimes(6);
  });
});

async function prepareTest() {
  const [toncenter, metadata, tokens, commonTokens, tonCore] = await Promise.all([
    import('./toncenter/other'),
    import('./util/metadata'),
    import('./tokens'),
    import('../../common/tokens'),
    import('./util/tonCore'),
  ]);
  await commonTokens.loadTokensCache();
  const callToncenterV3 = jest.mocked(toncenter.callToncenterV3);
  const fetchJettonMetadata = jest.mocked(metadata.fetchJettonMetadata);
  callToncenterV3.mockResolvedValue(UNINDEXED_RESPONSE);
  fetchJettonMetadata.mockResolvedValue(JETTON_METADATA);

  return {
    loadTokenBalances: tokens.loadTokenBalances,
    fetchToken: tokens.fetchToken,
    callToncenterV3,
    fetchJettonMetadata,
    updateTokensFetchedTogether: jest.spyOn(commonTokens, 'updateTokensFetchedTogether'),
    tokenAddress: tonCore.toBase64Address(JETTON_ADDRESS, true, 'mainnet'),
    toBase64Address: tonCore.toBase64Address,
  };
}
