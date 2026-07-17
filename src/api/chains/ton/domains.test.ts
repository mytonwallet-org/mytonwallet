import { Address } from '@ton/core';

import type { ApiDomainData, ApiNft } from '../../types';

import { logDebugError } from '../../../util/logs';
import { parseTonapiioNft } from './util/metadata';
import { getDnsItemDomain } from './util/tonCore';
import { fetchStoredWallet } from '../../common/accounts';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { resolveAddressByDomain } from './address';
import { fetchDomains } from './domains';

jest.mock('../../../util/account', () => ({
  parseAccountId: jest.fn(() => ({ network: 'mainnet' })),
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
  beforeEach(() => {
    jest.clearAllMocks();

    mockedFetchStoredWallet.mockResolvedValue(
      { address: WALLET_ADDRESS } as Awaited<ReturnType<typeof fetchStoredWallet>>,
    );
    mockedGetNftSuperCollectionsByCollectionAddress.mockResolvedValue({});
    mockedParseTonapiioNft.mockImplementation((_network, rawNft) => rawNft as unknown as ApiNft);
    mockedGetDnsItemDomain.mockResolvedValue('alice.ton');
    mockedResolveAddressByDomain.mockResolvedValue(LINKED_ADDRESS);
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
