import { Address } from '@ton/core';

import type { ApiDomainData, ApiNft } from '../../types';

import { HOUR, MINUTE } from '../../../util/dateFormat';
import Deferred from '../../../util/Deferred';
import { logDebugError } from '../../../util/logs';
import { parseTonapiioNft } from './util/metadata';
import { getDnsItemDomain } from './util/tonCore';
import { fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { resolveAddressByDomain } from './address';

jest.mock('../../../util/account', () => ({
  parseAccountId: jest.fn((accountId: string) => ({
    network: accountId.includes('testnet') ? 'testnet' : 'mainnet',
  })),
}));

jest.mock('../../../util/logs', () => ({
  logDebugError: jest.fn(),
}));

jest.mock('./address', () => ({
  resolveAddressByDomain: jest.fn(),
}));

jest.mock('./transfer', () => ({
  checkMultiTransactionDraft: jest.fn(),
  submitMultiTransferWithMfa: jest.fn(),
}));

jest.mock('./util/metadata', () => ({
  parseTonapiioNft: jest.fn(),
}));

jest.mock('./util/tonCore', () => {
  const actual = jest.requireActual('./util/tonCore');

  return {
    ...actual,
    getDnsItemDomain: jest.fn(),
  };
});

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

const ACCOUNT_ID = 'mainnet-0';
const WALLET_ADDRESS = 'EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz';
const NFT_ADDRESS = 'EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi';
const LINKED_ADDRESS = 'EQBWG4EBbPDv4Xj7xlPwzxd7hSyHMzwwLB5O6rY-0BBeaixS';
const OTHER_ADDRESS = 'EQAic3zPce496ukFDhbco28FVsKKl2WUX_iJwaL87CBxSiLQ';

const mockedCallBackendGet = jest.mocked(callBackendGet);
const mockedFetchStoredWallet = jest.mocked(fetchStoredWallet);
const mockedGetNftSuperCollectionsByCollectionAddress = jest.mocked(getNftSuperCollectionsByCollectionAddress);
const mockedGetDnsItemDomain = jest.mocked(getDnsItemDomain);
const mockedResolveAddressByDomain = jest.mocked(resolveAddressByDomain);
const mockedParseTonapiioNft = jest.mocked(parseTonapiioNft);
const mockedLogDebugError = jest.mocked(logDebugError);

describe('fetchDomains', () => {
  let fetchDomains: typeof import('./domains').fetchDomains;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, 'now').mockReturnValue(0);

    jest.isolateModules(() => {
      fetchDomains = jest.requireActual<typeof import('./domains')>('./domains').fetchDomains;
    });

    mockedFetchStoredWallet.mockResolvedValue(
      { address: WALLET_ADDRESS } as Awaited<ReturnType<typeof fetchStoredWallet>>,
    );
    mockedGetNftSuperCollectionsByCollectionAddress.mockResolvedValue({});
    mockedParseTonapiioNft.mockImplementation((_network, rawNft) => rawNft as unknown as ApiNft);
    mockedGetDnsItemDomain.mockResolvedValue('alice.ton');
    mockedResolveAddressByDomain.mockResolvedValue(LINKED_ADDRESS);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('keeps a linked address when it matches the on-chain DNS wallet record', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));

    const result = await fetchDomains(ACCOUNT_ID);

    expect(mockedGetDnsItemDomain).toHaveBeenCalledWith('mainnet', NFT_ADDRESS);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledWith('mainnet', 'alice.ton');
    expect(result.linkedAddressByAddress).toEqual({
      [NFT_ADDRESS]: LINKED_ADDRESS,
    });
    expect(result.nfts).toEqual({
      [NFT_ADDRESS]: expect.objectContaining({ address: NFT_ADDRESS }),
    });
  });

  it('omits a backend linked address when it differs from the on-chain DNS wallet record', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedResolveAddressByDomain.mockResolvedValue(OTHER_ADDRESS);

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(mockedLogDebugError).toHaveBeenCalledWith('verifyTonDnsLinkedAddress:mismatch', {
      nftAddress: NFT_ADDRESS,
      linkedAddress: LINKED_ADDRESS,
      resolvedLinkedAddress: OTHER_ADDRESS,
    });
  });

  it('keeps a linked address when backend and on-chain formats differ but normalize to the same address', async () => {
    const rawLinkedAddress = Address.parse(LINKED_ADDRESS).toRawString();
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: rawLinkedAddress }));
    mockedResolveAddressByDomain.mockResolvedValue(LINKED_ADDRESS);

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({
      [NFT_ADDRESS]: LINKED_ADDRESS,
    });
  });

  it('omits the linked address but keeps the domain NFT when on-chain resolving fails', async () => {
    const error = new Error('Resolver unavailable');
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedGetDnsItemDomain.mockRejectedValue(error);

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(result.nfts).toEqual({
      [NFT_ADDRESS]: expect.objectContaining({ address: NFT_ADDRESS }),
    });
    expect(mockedLogDebugError).toHaveBeenCalledWith('verifyTonDnsLinkedAddress', { nftAddress: NFT_ADDRESS }, error);
  });

  it('omits a backend linked address when the domain has no on-chain wallet record', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedResolveAddressByDomain.mockResolvedValue(undefined);

    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(result.nfts).toEqual({
      [NFT_ADDRESS]: expect.objectContaining({ address: NFT_ADDRESS }),
    });
    expect(mockedLogDebugError).not.toHaveBeenCalled();
  });

  it('does not resolve on-chain DNS when the backend does not return a linked address', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData());

    const result = await fetchDomains(ACCOUNT_ID);

    expect(mockedGetDnsItemDomain).not.toHaveBeenCalled();
    expect(mockedResolveAddressByDomain).not.toHaveBeenCalled();
    expect(result.linkedAddressByAddress).toEqual({});
    expect(result.nfts).toEqual({
      [NFT_ADDRESS]: expect.objectContaining({ address: NFT_ADDRESS }),
    });
  });

  it('returns the same domains without additional on-chain calls when backend data is unchanged', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));

    const firstResult = await fetchDomains(ACCOUNT_ID);
    const secondResult = await fetchDomains(ACCOUNT_ID);

    expect(secondResult).toEqual(firstResult);
    expect(mockedCallBackendGet).toHaveBeenCalledTimes(2);
    expect(mockedCallBackendGet).toHaveBeenNthCalledWith(2, '/dns/getDomains', { address: WALLET_ADDRESS });
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(1);
  });

  it('reuses verification when the backend changes only the linked address format', async () => {
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({
      linkedAddress: Address.parse(LINKED_ADDRESS).toRawString(),
    }));

    const firstResult = await fetchDomains(ACCOUNT_ID);
    const secondResult = await fetchDomains(ACCOUNT_ID);

    expect(secondResult).toEqual(firstResult);
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(1);
  });

  it('verifies a changed backend linked address immediately while reusing the domain name', async () => {
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({ linkedAddress: OTHER_ADDRESS }));
    mockedResolveAddressByDomain.mockResolvedValueOnce(LINKED_ADDRESS).mockResolvedValueOnce(OTHER_ADDRESS);

    await fetchDomains(ACCOUNT_ID);
    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({ [NFT_ADDRESS]: OTHER_ADDRESS });
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(2);
  });

  it('omits a changed backend linked address when the chain still holds the previous address', async () => {
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedCallBackendGet.mockResolvedValueOnce(makeDomainData({ linkedAddress: OTHER_ADDRESS }));

    await fetchDomains(ACCOUNT_ID);
    const result = await fetchDomains(ACCOUNT_ID);

    expect(result.linkedAddressByAddress).toEqual({});
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(2);
  });

  it('re-verifies a matching linked address after one hour', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));

    await fetchDomains(ACCOUNT_ID);
    mockedResolveAddressByDomain.mockResolvedValue(OTHER_ADDRESS);
    jest.mocked(Date.now).mockReturnValue(HOUR - 1);

    const cachedResult = await fetchDomains(ACCOUNT_ID);

    expect(cachedResult.linkedAddressByAddress).toEqual({ [NFT_ADDRESS]: LINKED_ADDRESS });
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(1);

    jest.mocked(Date.now).mockReturnValue(HOUR);
    const refreshedResult = await fetchDomains(ACCOUNT_ID);

    expect(refreshedResult.linkedAddressByAddress).toEqual({});
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(2);
  });

  it.each([
    ['mismatching', OTHER_ADDRESS],
    ['unresolved', undefined],
  ])('re-verifies a %s linked address after one minute', async (_outcome, resolvedAddress) => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedResolveAddressByDomain.mockResolvedValueOnce(resolvedAddress);

    await fetchDomains(ACCOUNT_ID);
    jest.mocked(Date.now).mockReturnValue(MINUTE - 1);

    const cachedResult = await fetchDomains(ACCOUNT_ID);

    expect(cachedResult.linkedAddressByAddress).toEqual({});
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(1);

    jest.mocked(Date.now).mockReturnValue(MINUTE);
    const refreshedResult = await fetchDomains(ACCOUNT_ID);

    expect(refreshedResult.linkedAddressByAddress).toEqual({ [NFT_ADDRESS]: LINKED_ADDRESS });
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(2);
  });

  it.each(['domain lookup', 'address resolution'])('retries a thrown %s error on the next fetch', async (operation) => {
    const error = new Error('DNS unavailable');
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    if (operation === 'domain lookup') {
      mockedGetDnsItemDomain.mockRejectedValueOnce(error);
    } else {
      mockedResolveAddressByDomain.mockRejectedValueOnce(error);
    }

    const failedResult = await fetchDomains(ACCOUNT_ID);
    const retriedResult = await fetchDomains(ACCOUNT_ID);

    expect(failedResult.linkedAddressByAddress).toEqual({});
    expect(retriedResult.linkedAddressByAddress).toEqual({ [NFT_ADDRESS]: LINKED_ADDRESS });
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(operation === 'domain lookup' ? 2 : 1);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(operation === 'domain lookup' ? 1 : 2);
    expect(mockedLogDebugError).toHaveBeenCalledWith('verifyTonDnsLinkedAddress', { nftAddress: NFT_ADDRESS }, error);
  });

  it('caches an unknown domain zone across verification expiry', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedGetDnsItemDomain.mockResolvedValue(undefined);

    const firstResult = await fetchDomains(ACCOUNT_ID);
    jest.mocked(Date.now).mockReturnValue(MINUTE);
    const refreshedResult = await fetchDomains(ACCOUNT_ID);

    expect(firstResult.linkedAddressByAddress).toEqual({});
    expect(refreshedResult).toEqual(firstResult);
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    expect(mockedResolveAddressByDomain).not.toHaveBeenCalled();
  });

  it('shares an in-flight domain lookup between concurrent fetches', async () => {
    const domainLookup = new Deferred<string | undefined>();
    const lookupStarted = new Deferred();
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));
    mockedGetDnsItemDomain.mockImplementation(() => {
      lookupStarted.resolve();
      return domainLookup.promise;
    });

    const pendingResults = Promise.all([fetchDomains(ACCOUNT_ID), fetchDomains(ACCOUNT_ID)]);
    await lookupStarted.promise;

    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
    domainLookup.resolve('alice.ton');
    const [firstResult, secondResult] = await pendingResults;

    expect(firstResult.linkedAddressByAddress).toEqual({ [NFT_ADDRESS]: LINKED_ADDRESS });
    expect(secondResult).toEqual(firstResult);
    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(1);
  });

  it('verifies the same NFT separately on different networks', async () => {
    mockedCallBackendGet.mockResolvedValue(makeDomainData({ linkedAddress: LINKED_ADDRESS }));

    await fetchDomains(ACCOUNT_ID);
    await fetchDomains('testnet-0');

    expect(mockedGetDnsItemDomain).toHaveBeenCalledTimes(2);
    expect(mockedGetDnsItemDomain).toHaveBeenNthCalledWith(2, 'testnet', NFT_ADDRESS);
    expect(mockedResolveAddressByDomain).toHaveBeenCalledTimes(2);
    expect(mockedResolveAddressByDomain).toHaveBeenNthCalledWith(2, 'testnet', 'alice.ton');
  });
});

function makeDomainData(options: { linkedAddress?: string } = {}) {
  return {
    [NFT_ADDRESS]: {
      domain: 'alice.ton',
      linkedAddress: options.linkedAddress,
      lastFillUpTime: '2026-01-01T00:00:00.000Z',
      nft: makeNft(),
    },
  } as unknown as Record<string, ApiDomainData>;
}

function makeNft(): ApiNft {
  return {
    chain: 'ton',
    index: 1,
    address: NFT_ADDRESS,
    thumbnail: '',
    image: '',
    name: 'alice.ton',
    collectionAddress: WALLET_ADDRESS,
    isOnSale: false,
    metadata: {},
    interface: 'default',
  };
}
