import { Address, beginCell, Cell } from '@ton/core';

import type { Storage } from '../../storages/types';
import type { ApiDomainData, ApiNft } from '../../types';

import { TON_DNS_ZONES } from '../../../config';
import { DAY, HOUR, MINUTE } from '../../../util/dateFormat';
import Deferred from '../../../util/Deferred';
import { logDebugError } from '../../../util/logs';
import { withTimeout } from '../../../util/schedulers';
import { parseTonapiioNft } from './util/metadata';
import { TonClient } from './util/TonClient';
import { fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { getCurrentStorage } from '../../storages';
import { DNS_CATEGORY_HASH_MAP, DnsOpCode } from './constants';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from './transfer';

jest.mock('@ton/core', () => jest.requireActual('@ton/core'));
jest.mock('./util/TonClient', () => jest.requireActual('./util/TonClient'));

jest.mock('../../../util/account', () => ({
  parseAccountId: jest.fn((accountId: string) => ({
    network: accountId.includes('testnet') ? 'testnet' : 'mainnet',
  })),
}));

jest.mock('../../../util/logs', () => ({
  logDebugError: jest.fn(),
}));

jest.mock('../../environment', () => ({
  getEnvironment: () => ({ apiHeaders: undefined, byNetwork: { mainnet: {}, testnet: {} } }),
}));

jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
}));

jest.mock('./util/signer', () => ({ getSigner: jest.fn() }));

jest.mock('./util/metadata', () => ({
  parseTonapiioNft: jest.fn(),
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredChainAccount: jest.fn(),
  fetchStoredWallet: jest.fn(),
}));

jest.mock('../../common/addresses', () => ({
  getNftSuperCollectionsByCollectionAddress: jest.fn(),
}));

jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn(),
}));

jest.mock('../../storages', () => ({
  getCurrentStorage: jest.fn(),
}));

const ACCOUNT_ID = 'mainnet-0';
const WALLET_ADDRESS = TON_DNS_ZONES[0].resolver;
const LINKED_ADDRESS = 'EQBWG4EBbPDv4Xj7xlPwzxd7hSyHMzwwLB5O6rY-0BBeaixS';
const OTHER_ADDRESS = 'EQAic3zPce496ukFDhbco28FVsKKl2WUX_iJwaL87CBxSiLQ';
const OP_CODE_BITS = 32;
const QUERY_ID_BITS = 64;
const DNS_CATEGORY_BYTES = 32;

type DomainFixture = {
  address: string;
  name: string;
  collectionAddress: string;
  resolverAddress: string;
  walletAddress: string | undefined;
};

type RpcParams = {
  address: string;
  method: string;
  stack: [string, string][];
};

type StoredEntry = {
  lastSeenAt: number;
  domain?: { name: string; resolverAddress: string };
  verification?: { linkedAddress: string; verifiedLinkedAddress?: string; checkedAt: number };
};

const mockedCallBackendGet = jest.mocked(callBackendGet);
const mockedFetchStoredWallet = jest.mocked(fetchStoredWallet);
const mockedGetNftSuperCollectionsByCollectionAddress = jest.mocked(getNftSuperCollectionsByCollectionAddress);
const mockedParseTonapiioNft = jest.mocked(parseTonapiioNft);
const mockedLogDebugError = jest.mocked(logDebugError);
const mockedGetCurrentStorage = jest.mocked(getCurrentStorage);

describe('fetchDomains', () => {
  let fetchDomains: typeof import('./domains').fetchDomains;
  let clearDnsCache: typeof import('./domains').clearDnsCache;
  let submitDnsChangeWallet: typeof import('./domains').submitDnsChangeWallet;
  let fixtures: DomainFixture[];
  let disk: { tonDnsCache?: Record<string, StoredEntry> };
  let storage: Storage;
  let callRpc: jest.SpiedFunction<TonClient['callRpc']>;

  function restartWorker() {
    jest.isolateModules(() => {
      const domains = jest.requireActual<typeof import('./domains')>('./domains');
      fetchDomains = domains.fetchDomains;
      clearDnsCache = domains.clearDnsCache;
      submitDnsChangeWallet = domains.submitDnsChangeWallet;
    });
  }

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(0);
    fixtures = makeFixtures(1);
    disk = {};
    storage = {
      getItem: jest.fn(() => Promise.resolve(clone(disk.tonDnsCache))),
      setItem: jest.fn((_key, value) => {
        disk.tonDnsCache = clone(value);
        return Promise.resolve();
      }),
      removeItem: jest.fn(() => {
        delete disk.tonDnsCache;
        return Promise.resolve();
      }),
      clear: jest.fn(),
    };
    mockedGetCurrentStorage.mockReturnValue(storage);
    mockedFetchStoredWallet.mockResolvedValue(
      { address: WALLET_ADDRESS } as Awaited<ReturnType<typeof fetchStoredWallet>>,
    );
    mockedGetNftSuperCollectionsByCollectionAddress.mockResolvedValue({});
    mockedParseTonapiioNft.mockImplementation((_network, rawNft) => rawNft as unknown as ApiNft);
    mockedCallBackendGet.mockImplementation(() => Promise.resolve(makeDomainData(fixtures, LINKED_ADDRESS)));
    callRpc = jest.spyOn(TonClient.prototype, 'callRpc').mockImplementation((method, params: RpcParams) => {
      expect(method).toBe('runGetMethod');
      return Promise.resolve(respondToDnsRequest(fixtures, params));
    });
    restartWorker();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('keeps a linked address when it matches the on-chain DNS wallet record', async () => {
    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(result.nfts).toEqual({
      [fixtures[0].address]: expect.objectContaining({ address: fixtures[0].address }),
    });
    expect(callRpc.mock.calls.map(([, params]) => params.method))
      .toEqual(['get_nft_data', 'get_domain', 'dnsresolve', 'dnsresolve']);
  });

  it('omits a backend linked address when it differs from the on-chain DNS wallet record', async () => {
    fixtures[0].walletAddress = OTHER_ADDRESS;

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(mockedLogDebugError).toHaveBeenCalledWith('verifyTonDnsLinkedAddress:mismatch', {
      nftAddress: fixtures[0].address,
      linkedAddress: LINKED_ADDRESS,
      resolvedLinkedAddress: OTHER_ADDRESS,
    });
  });

  it('keeps verified domains when another backend NFT address cannot be parsed', async () => {
    const data = makeDomainData(fixtures, LINKED_ADDRESS);
    data.invalid = data[fixtures[0].address];
    mockedCallBackendGet.mockResolvedValue(data);

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(4);
  });

  it('rejects a zone resolver pointing to another NFT without persisting immutable metadata', async () => {
    fixtures[0].resolverAddress = OTHER_ADDRESS;

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(3);
    expect(Object.values(disk.tonDnsCache!)[0].domain).toBeUndefined();
  });

  it('reads and verifies the complete Telemint domain from its NFT contract', async () => {
    fixtures[0].collectionAddress = TON_DNS_ZONES[1].resolver;
    fixtures[0].name = 'alice.t.me';

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc.mock.calls.map(([, params]) => params.method))
      .toEqual(['get_nft_data', 'get_full_domain', 'dnsresolve', 'dnsresolve']);
    expect(Object.values(disk.tonDnsCache!)[0].domain?.name).toBe('alice.t.me');
  });

  it('reuses verification when the backend changes only the linked address format', async () => {
    const firstResult = await fetchDomains(ACCOUNT_ID);
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures, Address.parse(LINKED_ADDRESS).toRawString()));

    const secondResult = await fetchDomains(ACCOUNT_ID);

    expect(secondResult).toEqual(firstResult);
    expect(callRpc).toHaveBeenCalledTimes(4);
    expect(mockedCallBackendGet).toHaveBeenNthCalledWith(2, '/dns/getDomains', { address: WALLET_ADDRESS });
  });

  it('normalizes a raw backend linked address before comparing it with the chain', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures, Address.parse(LINKED_ADDRESS).toRawString()));

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
  });

  it('omits a backend linked address when the domain has no on-chain wallet record', async () => {
    fixtures[0].walletAddress = undefined;

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(result.nfts[fixtures[0].address]).toBeDefined();
    expect(mockedLogDebugError).not.toHaveBeenCalled();
  });

  it('does not resolve on-chain DNS when the backend does not return a linked address', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures, undefined));

    const result = await fetchDomains(ACCOUNT_ID);

    expect(callRpc).not.toHaveBeenCalled();
    expect(result.linkedAddressByAddress).toEqual({});
    expect(result.nfts[fixtures[0].address]).toBeDefined();
  });

  it('uses 56 get methods initially, zero after restart within an hour, and 14 wallet reads after expiry', async () => {
    fixtures = makeFixtures(14);
    const firstResult = await fetchDomains(ACCOUNT_ID);

    expect(Object.keys(firstResult.linkedAddressByAddress)).toHaveLength(14);
    expect(callRpc).toHaveBeenCalledTimes(56);
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(storage.getItem).toHaveBeenCalledWith('tonDnsCache');

    jest.mocked(Date.now).mockReturnValue(HOUR - 1);
    callRpc.mockClear();
    restartWorker();
    expect(await fetchDomains(ACCOUNT_ID)).toEqual(firstResult);
    expect(callRpc).not.toHaveBeenCalled();

    jest.mocked(Date.now).mockReturnValue(HOUR);
    restartWorker();
    expect(await fetchDomains(ACCOUNT_ID)).toEqual(firstResult);
    expect(callRpc).toHaveBeenCalledTimes(14);
    for (const [, params] of callRpc.mock.calls) {
      expect(params.method).toBe('dnsresolve');
      expect(fixtures.map(({ address }) => address)).toContain(params.address);
      expect(Cell.fromBase64(params.stack[0][1]).beginParse().loadBuffer(1)).toEqual(Buffer.from([0]));
    }
  });

  it('rechecks only the changed backend linked address after restart and rejects it when unconfirmed', async () => {
    fixtures = makeFixtures(14);
    await fetchDomains(ACCOUNT_ID);
    const changedData = makeDomainData(fixtures, LINKED_ADDRESS);
    changedData[fixtures[0].address].linkedAddress = OTHER_ADDRESS;
    mockedCallBackendGet.mockResolvedValue(changedData);
    callRpc.mockClear();
    restartWorker();

    const result = await fetchDomains(ACCOUNT_ID);

    expect(callRpc).toHaveBeenCalledTimes(1);
    expect(result.linkedAddressByAddress[fixtures[0].address]).toBeUndefined();
    expect(Object.keys(result.linkedAddressByAddress)).toHaveLength(13);
  });

  it('shows a newly confirmed wallet record after TTL expiry without retaining the old address', async () => {
    await fetchDomains(ACCOUNT_ID);
    fixtures[0].walletAddress = OTHER_ADDRESS;
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures, OTHER_ADDRESS));
    jest.mocked(Date.now).mockReturnValue(HOUR);
    callRpc.mockClear();
    restartWorker();

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: OTHER_ADDRESS });
    expect(Object.values(result.linkedAddressByAddress)).not.toContain(LINKED_ADDRESS);
    expect(callRpc).toHaveBeenCalledTimes(1);
  });

  it('rechecks a changed backend linked address immediately while reusing immutable metadata', async () => {
    await fetchDomains(ACCOUNT_ID);
    fixtures[0].walletAddress = OTHER_ADDRESS;
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures, OTHER_ADDRESS));
    callRpc.mockClear();

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [fixtures[0].address]: OTHER_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(1);
  });

  it('hides a stale backend linked address when the chain changes after one hour', async () => {
    await fetchDomains(ACCOUNT_ID);
    fixtures[0].walletAddress = OTHER_ADDRESS;
    jest.mocked(Date.now).mockReturnValue(HOUR - 1);
    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(4);

    jest.mocked(Date.now).mockReturnValue(HOUR);
    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(5);
  });

  it('rechecks a persisted verification made before the device clock moved backwards', async () => {
    jest.mocked(Date.now).mockReturnValue(10 * HOUR);
    await fetchDomains(ACCOUNT_ID);
    fixtures[0].walletAddress = OTHER_ADDRESS;
    jest.mocked(Date.now).mockReturnValue(0);
    callRpc.mockClear();
    restartWorker();

    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['mismatching', OTHER_ADDRESS],
    ['unresolved', undefined],
  ])('persists a %s result for one minute and rechecks after expiry', async (_outcome, walletAddress) => {
    fixtures[0].walletAddress = walletAddress;
    await fetchDomains(ACCOUNT_ID);
    fixtures[0].walletAddress = LINKED_ADDRESS;
    jest.mocked(Date.now).mockReturnValue(MINUTE - 1);
    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(4);

    jest.mocked(Date.now).mockReturnValue(MINUTE);
    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(5);
  });

  it.each(['get_nft_data', 'wallet'])('retries a %s network error in the same worker', async (stage) => {
    const error = new Error('DNS unavailable');
    callRpc.mockImplementationOnce((_method, params: RpcParams) => {
      if (stage === 'get_nft_data') return Promise.reject(error);
      return Promise.resolve(respondToDnsRequest(fixtures, params));
    });
    if (stage === 'wallet') {
      callRpc.mockImplementation((_method, params: RpcParams) => {
        if (params.method === 'dnsresolve' && params.address === fixtures[0].address) return Promise.reject(error);
        return Promise.resolve(respondToDnsRequest(fixtures, params));
      });
    }

    const failedResult = await fetchDomains(ACCOUNT_ID);

    expect(failedResult.linkedAddressByAddress).toEqual({});
    expect(failedResult.nfts[fixtures[0].address]).toBeDefined();
    expect(Object.values(disk.tonDnsCache!)[0].domain).toBeUndefined();
    expect(Object.values(disk.tonDnsCache!)[0].verification).toBeUndefined();
    expect(mockedLogDebugError).toHaveBeenCalledWith(
      'verifyTonDnsLinkedAddress', { nftAddress: fixtures[0].address }, error,
    );
    callRpc.mockImplementation((_method, params) => Promise.resolve(respondToDnsRequest(fixtures, params)));
    callRpc.mockClear();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(stage === 'get_nft_data' ? 4 : 2);
  });

  it('keeps a DNS exit code unverified for one minute without persisting immutable metadata', async () => {
    callRpc.mockImplementation((_method, params: RpcParams) => {
      if (params.method === 'dnsresolve' && params.address === fixtures[0].address) {
        return Promise.resolve({ exit_code: 9, gas_used: 0, stack: [] });
      }
      return Promise.resolve(respondToDnsRequest(fixtures, params));
    });

    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(Object.values(disk.tonDnsCache!)[0].domain).toBeUndefined();
    expect(Object.values(disk.tonDnsCache!)[0].verification).toEqual({
      linkedAddress: LINKED_ADDRESS,
      checkedAt: 0,
    });
    expect(callRpc).toHaveBeenCalledTimes(4);

    jest.mocked(Date.now).mockReturnValue(MINUTE - 1);
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(4);

    jest.mocked(Date.now).mockReturnValue(MINUTE);
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(8);
    expect(Object.values(disk.tonDnsCache!)[0].domain).toBeUndefined();
  });

  it.each(['getItem', 'setItem'] as const)('uses the network and logs a storage %s failure', async (operation) => {
    const error = new Error('Storage unavailable');
    const otherNetworkCache = { 'testnet:other-domain': { lastSeenAt: 0 } };
    disk.tonDnsCache = otherNetworkCache;
    jest.mocked(storage[operation]).mockRejectedValue(error);

    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(4);
    expect(mockedLogDebugError.mock.calls.some((args) => args.includes(error))).toBe(true);
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(4);
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(disk.tonDnsCache).toEqual(otherNetworkCache);
    if (operation === 'getItem') expect(storage.setItem).not.toHaveBeenCalled();

    restartWorker();
    expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
      .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(callRpc).toHaveBeenCalledTimes(8);
  });

  it('caches an unknown domain zone in memory across verification expiry', async () => {
    fixtures[0].collectionAddress = Address.parse(`0:${'f'.repeat(64)}`).toString();
    const firstResult = await fetchDomains(ACCOUNT_ID);
    jest.mocked(Date.now).mockReturnValue(MINUTE);

    expect(await fetchDomains(ACCOUNT_ID)).toEqual(firstResult);
    expect(firstResult.linkedAddressByAddress).toEqual({});
    expect(callRpc).toHaveBeenCalledTimes(1);
    expect(Object.values(disk.tonDnsCache!)[0].domain).toBeUndefined();
  });

  it('shares an in-flight NFT domain lookup between concurrent fetches', async () => {
    const rpcStarted = new Deferred();
    const rpc = new Deferred();
    callRpc.mockImplementation(async (_method, params: RpcParams) => {
      if (params.method === 'get_nft_data') {
        rpcStarted.resolve();
        await rpc.promise;
      }
      return respondToDnsRequest(fixtures, params);
    });

    const pending = Promise.all([fetchDomains(ACCOUNT_ID), fetchDomains(ACCOUNT_ID)]);
    await rpcStarted.promise;
    const hasFinished = await withTimeout(pending.then(() => true), 0, false);
    const pendingRpcCount = callRpc.mock.calls.length;
    rpc.resolve();
    const [firstResult, secondResult] = await pending;

    expect(hasFinished).toBe(false);
    expect(pendingRpcCount).toBe(1);
    expect(firstResult.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(secondResult).toEqual(firstResult);
    expect(callRpc.mock.calls.filter(([, params]) => params.method === 'get_nft_data')).toHaveLength(1);
    expect(callRpc.mock.calls.filter(([, params]) => params.method === 'get_domain')).toHaveLength(1);
  });

  it('shares the disk read while checking different accounts concurrently and serializing their writes', async () => {
    fixtures = makeFixtures(2);
    const read = new Deferred();
    const readStarted = new Deferred();
    const rpcStarted = fixtures.map(() => new Deferred());
    const rpc = new Deferred();
    const secondWallet = new Deferred();
    const firstWriteStarted = new Deferred();
    const firstWrite = new Deferred();
    mockedFetchStoredWallet.mockImplementation((accountId) => Promise.resolve({
      address: accountId === ACCOUNT_ID ? WALLET_ADDRESS : OTHER_ADDRESS,
    } as Awaited<ReturnType<typeof fetchStoredWallet>>));
    mockedCallBackendGet.mockImplementation((_path, params) => Promise.resolve(makeDomainData(
      [fixtures[params?.address === WALLET_ADDRESS ? 0 : 1]], LINKED_ADDRESS,
    )));
    jest.mocked(storage.getItem).mockImplementation(async () => {
      readStarted.resolve();
      await read.promise;
      return undefined;
    });
    callRpc.mockImplementation(async (_method, params: RpcParams) => {
      if (params.method === 'get_nft_data') {
        rpcStarted[fixtures.findIndex(({ address }) => address === params.address)].resolve();
        await rpc.promise;
      }
      if (params.method === 'dnsresolve' && params.address === fixtures[1].address) {
        await secondWallet.promise;
      }
      return respondToDnsRequest(fixtures, params);
    });
    jest.mocked(storage.setItem).mockImplementation(async (_key, value) => {
      const snapshot = clone(value);
      if (jest.mocked(storage.setItem).mock.calls.length === 1) {
        firstWriteStarted.resolve();
        await firstWrite.promise;
      }
      disk.tonDnsCache = snapshot;
    });

    const firstFetch = fetchDomains(ACCOUNT_ID);
    const secondFetch = fetchDomains('mainnet-1');
    await readStarted.promise;
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(callRpc).not.toHaveBeenCalled();
    read.resolve();
    await Promise.all(rpcStarted.map(({ promise }) => promise));
    expect(callRpc).toHaveBeenCalledTimes(2);
    rpc.resolve();
    await firstWriteStarted.promise;
    secondWallet.resolve();
    expect(await withTimeout(secondFetch.then(() => true), 0, false)).toBe(false);
    expect(storage.setItem).toHaveBeenCalledTimes(1);
    firstWrite.resolve();
    const [firstResult, secondResult] = await Promise.all([firstFetch, secondFetch]);

    expect(firstResult.linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(secondResult.linkedAddressByAddress).toEqual({ [fixtures[1].address]: LINKED_ADDRESS });
    expect(storage.getItem).toHaveBeenCalledTimes(1);
    expect(storage.setItem).toHaveBeenCalledTimes(2);
    expect(Object.keys(disk.tonDnsCache!).sort()).toEqual(fixtures.map(({ address }) => `mainnet:${address}`).sort());
    expect(Object.values(disk.tonDnsCache!).map(({ verification }) => verification?.verifiedLinkedAddress))
      .toEqual([LINKED_ADDRESS, LINKED_ADDRESS]);
  });

  it('verifies the same NFT separately on different networks after restart', async () => {
    await fetchDomains(ACCOUNT_ID);
    callRpc.mockClear();
    restartWorker();
    await fetchDomains(ACCOUNT_ID);
    expect(callRpc).not.toHaveBeenCalled();

    const result = await fetchDomains('testnet-0');

    expect(callRpc).toHaveBeenCalledTimes(4);
    expect(result.linkedAddressByAddress).toEqual({
      [fixtures[0].address]: Address.parse(LINKED_ADDRESS).toString({ testOnly: true }),
    });
    expect(Object.keys(disk.tonDnsCache!)).toHaveLength(2);
  });

  it('clears disk and memory without allowing a pending backend response to restore old entries', async () => {
    await fetchDomains(ACCOUNT_ID);
    const data = makeDomainData(fixtures, LINKED_ADDRESS);
    const response = new Deferred<Record<string, ApiDomainData>>();
    const requested = new Deferred();
    mockedCallBackendGet.mockImplementationOnce(() => {
      requested.resolve();
      return response.promise;
    });
    const pending = fetchDomains(ACCOUNT_ID);
    await requested.promise;

    await clearDnsCache();

    expect(disk.tonDnsCache).toBeUndefined();
    response.resolve(data);
    expect((await pending).linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(disk.tonDnsCache).toBeUndefined();

    fixtures = makeFixtures(2).slice(1);
    callRpc.mockClear();
    await fetchDomains(ACCOUNT_ID);

    expect(callRpc).toHaveBeenCalledTimes(4);
    expect(Object.keys(disk.tonDnsCache!)).toEqual([`mainnet:${fixtures[0].address}`]);
  });

  it('clears before a stalled RPC finishes while still returning the verified address to its caller', async () => {
    const rpcStarted = new Deferred();
    const rpc = new Deferred();
    callRpc.mockImplementationOnce(async (_method, params: RpcParams) => {
      rpcStarted.resolve();
      await rpc.promise;
      return respondToDnsRequest(fixtures, params);
    });
    const pending = fetchDomains(ACCOUNT_ID);
    await rpcStarted.promise;

    const wasCleared = await withTimeout(clearDnsCache().then(() => true), 100, false);
    rpc.resolve();

    expect(wasCleared).toBe(true);
    expect((await pending).linkedAddressByAddress).toEqual({ [fixtures[0].address]: LINKED_ADDRESS });
    expect(disk.tonDnsCache).toBeUndefined();
    callRpc.mockClear();
    await fetchDomains(ACCOUNT_ID);
    expect(callRpc).toHaveBeenCalledTimes(4);
  });

  it('prunes NFTs unseen for 30 days while retaining returned NFTs without a linked address', async () => {
    fixtures = makeFixtures(3);
    await fetchDomains(ACCOUNT_ID);
    expect(Object.keys(disk.tonDnsCache!)).toHaveLength(3);
    jest.mocked(Date.now).mockReturnValue(31 * DAY);
    mockedCallBackendGet.mockResolvedValue(makeDomainData(fixtures.slice(0, 1), undefined));
    callRpc.mockClear();
    restartWorker();

    await fetchDomains(ACCOUNT_ID);

    expect(callRpc).not.toHaveBeenCalled();
    expect(Object.keys(disk.tonDnsCache!)).toEqual([`mainnet:${fixtures[0].address}`]);
    expect(Object.values(disk.tonDnsCache!)[0].lastSeenAt).toBe(31 * DAY);
  });

  describe('after this app submits a wallet record change while the backend still reports the old one', () => {
    beforeEach(async () => {
      jest.mocked(submitMultiTransferWithMfa).mockResolvedValue(
        { msgHashNormalized: 'msg-hash' } as Awaited<ReturnType<typeof submitMultiTransferWithMfa>>,
      );
      await fetchDomains(ACCOUNT_ID);
    });

    it('shows the domain as unlinked as soon as the chain deletes the record', async () => {
      await submitDnsChangeWallet(ACCOUNT_ID, undefined, fixtures[0].address);
      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
        .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });

      fixtures[0].walletAddress = undefined;

      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    });

    it('keeps the previous wallet until the chain has the new one', async () => {
      await submitDnsChangeWallet(ACCOUNT_ID, undefined, fixtures[0].address, OTHER_ADDRESS);
      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
        .toEqual({ [fixtures[0].address]: LINKED_ADDRESS });

      fixtures[0].walletAddress = OTHER_ADDRESS;

      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
        .toEqual({ [fixtures[0].address]: OTHER_ADDRESS });
    });

    it('keeps checking the chain after a restart', async () => {
      await submitDnsChangeWallet(ACCOUNT_ID, undefined, fixtures[0].address);
      fixtures[0].walletAddress = undefined;
      restartWorker();

      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress).toEqual({});
    });

    it('trusts the cached verification again once the backend reports the submitted record', async () => {
      await submitDnsChangeWallet(ACCOUNT_ID, undefined, fixtures[0].address, OTHER_ADDRESS);
      fixtures[0].walletAddress = OTHER_ADDRESS;
      mockedCallBackendGet.mockImplementation(() => Promise.resolve(makeDomainData(fixtures, OTHER_ADDRESS)));
      await fetchDomains(ACCOUNT_ID);
      callRpc.mockClear();

      expect((await fetchDomains(ACCOUNT_ID)).linkedAddressByAddress)
        .toEqual({ [fixtures[0].address]: OTHER_ADDRESS });
      expect(callRpc).not.toHaveBeenCalled();
    });
  });
});

describe('checkDnsChangeWalletDraft', () => {
  it('deletes the DNS wallet record when no address is given', async () => {
    const { checkDnsChangeWalletDraft } = jest.requireActual<typeof import('./domains')>('./domains');
    const mockedCheckMultiTransactionDraft = jest.mocked(checkMultiTransactionDraft);
    mockedCheckMultiTransactionDraft.mockResolvedValue(
      { emulation: { networkFee: 0n } } as Awaited<ReturnType<typeof checkMultiTransactionDraft>>,
    );

    await checkDnsChangeWalletDraft(ACCOUNT_ID, LINKED_ADDRESS);

    const [[, [{ payload }]]] = mockedCheckMultiTransactionDraft.mock.calls;
    const body = (payload as Cell).beginParse();
    expect(body.loadUint(OP_CODE_BITS)).toBe(DnsOpCode.ChangeRecord);
    body.skip(QUERY_ID_BITS);
    expect(body.loadBuffer(DNS_CATEGORY_BYTES).toString('hex')).toBe(DNS_CATEGORY_HASH_MAP.wallet);
    expect(body.remainingRefs).toBe(0);
  });

  it('rejects an empty address instead of deleting the DNS wallet record', async () => {
    const { checkDnsChangeWalletDraft } = jest.requireActual<typeof import('./domains')>('./domains');
    const mockedCheckMultiTransactionDraft = jest.mocked(checkMultiTransactionDraft);
    mockedCheckMultiTransactionDraft.mockClear();
    mockedCheckMultiTransactionDraft.mockResolvedValue(
      { emulation: { networkFee: 0n } } as Awaited<ReturnType<typeof checkMultiTransactionDraft>>,
    );

    await expect(checkDnsChangeWalletDraft(ACCOUNT_ID, LINKED_ADDRESS, '')).rejects.toThrow();
    expect(mockedCheckMultiTransactionDraft).not.toHaveBeenCalled();
  });
});

function makeFixtures(count: number): DomainFixture[] {
  return Array.from({ length: count }, (_, index) => {
    const address = Address.parse(`0:${(index + 1).toString(16).padStart(64, '0')}`).toString();
    return {
      address,
      name: `alice${index}.ton`,
      collectionAddress: TON_DNS_ZONES[0].resolver,
      resolverAddress: address,
      walletAddress: LINKED_ADDRESS,
    };
  });
}

function makeDomainData(fixtures: DomainFixture[], linkedAddress: string | undefined) {
  return Object.fromEntries(fixtures.map(({ address, name, collectionAddress }) => [address, {
    domain: name,
    linkedAddress,
    lastFillUpTime: '2026-01-01T00:00:00.000Z',
    nft: {
      chain: 'ton', index: 1, address, thumbnail: '', image: '', name, collectionAddress,
      isOnSale: false, metadata: {}, interface: 'default',
    },
  }])) as unknown as Record<string, ApiDomainData>;
}

function respondToDnsRequest(fixtures: DomainFixture[], params: RpcParams) {
  const fixture = fixtures.find(({ address }) => address === params.address);
  let stack: unknown[];
  switch (params.method) {
    case 'get_nft_data':
      stack = [
        ['num', '-1'], ['num', '0'],
        toStackCell(beginCell().storeAddress(Address.parse(fixture!.collectionAddress)).endCell()),
        toStackCell(beginCell().storeAddress(Address.parse(WALLET_ADDRESS)).endCell()),
      ];
      break;
    case 'get_domain':
      stack = [toStackCell(beginCell().storeStringTail(fixture!.name.split('.')[0]).endCell())];
      break;
    case 'get_full_domain':
      stack = [toStackCell(beginCell()
        .storeStringTail(`${fixture!.name.split('.').reverse().join('\0')}\0`)
        .endCell())];
      break;
    case 'dnsresolve': {
      if (fixture) {
        stack = fixture.walletAddress ? [
          ['num', '8'],
          toStackCell(beginCell().storeUint(0x9fd3, 16).storeAddress(Address.parse(fixture.walletAddress)).endCell()),
        ] : [['num', '0'], ['null']];
      } else {
        const domainSlice = Cell.fromBase64(params.stack[0][1]).beginParse();
        const rawDomain = domainSlice.loadBuffer(domainSlice.remainingBits / 8);
        const base = rawDomain.toString().split('\0').filter(Boolean).reverse().join('.');
        const resolved = fixtures.find(({ name, collectionAddress }) => (
          name.split('.')[0] === base && collectionAddress === params.address
        ))!;
        stack = [
          ['num', String((rawDomain.length - 1) * 8)],
          toStackCell(beginCell()
            .storeUint(0xba93, 16)
            .storeAddress(Address.parse(resolved.resolverAddress))
            .endCell()),
        ];
      }
      break;
    }
    default:
      throw new Error(`Unexpected get method: ${params.method}`);
  }
  return { exit_code: 0, gas_used: 0, stack };
}

function toStackCell(cell: Cell) {
  return ['cell', { bytes: cell.toBoc().toString('base64') }];
}

function clone<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}
