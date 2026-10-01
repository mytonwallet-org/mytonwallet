import { Address, beginCell } from '@ton/core';

import type { ApiNft } from '../../../types';

import {
  MW_CARDS_COLLECTION,
  NFT_FRAGMENT_COLLECTIONS,
  NOTCOIN_VOUCHERS_ADDRESS,
  STON_PTON_ADDRESS,
  TON_DNS_ZONES,
} from '../../../../config';
import { checkIsTrustedCollection, getHasTrustedCollections } from '../../../common/addresses';
import { JettonOpCode, NftOpCode } from '../constants';
import { getIsNftUnverified, parsePayloadBase64, preloadPayloadNfts } from './metadata';

const mockFetchNftByAddress = jest.fn();
const mockFetchNftsByAddresses = jest.fn();
const mockResolveTokenWallet = jest.fn();

jest.mock('../../../common/addresses', () => ({
  checkHasScamLink: jest.fn(() => false),
  checkIsTrustedCollection: jest.fn(() => false),
  getHasTrustedCollections: jest.fn(() => true),
  getNftSuperCollectionsByCollectionAddress: jest.fn(),
}));

jest.mock('../toncenter/nfts', () => ({
  fetchNftByAddress: (...args: unknown[]) => mockFetchNftByAddress(...args),
  fetchNftsByAddresses: (...args: unknown[]) => mockFetchNftsByAddresses(...args),
}));

jest.mock('./tonCore', () => {
  const actual = jest.requireActual('./tonCore');

  return {
    ...actual,
    resolveTokenWallet: (...args: unknown[]) => mockResolveTokenWallet(...args),
  };
});

const TRUSTED_COLLECTION = 'EQBDMXqg2YcGmMnn5_bXG63y-hh_YNV0dx-ylx-vL3v_WZt4';
const UNKNOWN_COLLECTION = 'EQAglL_g6q2AhMK_BT9jN1F-8jBlv2pOI30vRkPluU9kcXgV';

const NETWORK = 'mainnet';
const OUTER_ADDRESS = `0:${'1'.repeat(64)}`;
const TOKEN_ADDRESS = `0:${'2'.repeat(64)}`;
const RECIPIENT_ADDRESS = `0:${'3'.repeat(64)}`;
const RESPONSE_ADDRESS = `0:${'4'.repeat(64)}`;
const OWNER_ADDRESS = `0:${'5'.repeat(64)}`;

describe('getIsNftUnverified', () => {
  beforeEach(() => {
    jest.mocked(getHasTrustedCollections).mockReturnValue(true);
    jest.mocked(checkIsTrustedCollection).mockImplementation((address) => address === TRUSTED_COLLECTION);
  });

  it('marks an NFT of an unknown collection', () => {
    expect(getIsNftUnverified({ collectionAddress: UNKNOWN_COLLECTION })).toBe(true);
  });

  it('marks an NFT without a collection', () => {
    expect(getIsNftUnverified({})).toBe(true);
  });

  it('keeps every NFT unmarked until the backend list arrives', () => {
    jest.mocked(getHasTrustedCollections).mockReturnValue(false);
    expect(getIsNftUnverified({ collectionAddress: UNKNOWN_COLLECTION })).toBeUndefined();
  });

  it('skips a collection trusted by the backend', () => {
    expect(getIsNftUnverified({ collectionAddress: TRUSTED_COLLECTION })).toBeUndefined();
  });

  it('skips a Fragment NFT, which covers Telegram gifts, numbers and usernames', () => {
    expect(getIsNftUnverified({ collectionAddress: NFT_FRAGMENT_COLLECTIONS[0], isOnFragment: true })).toBeUndefined();
  });

  it('skips MyTonWallet cards', () => {
    expect(getIsNftUnverified({ collectionAddress: MW_CARDS_COLLECTION })).toBeUndefined();
  });

  it('skips Notcoin vouchers', () => {
    expect(getIsNftUnverified({ collectionAddress: NOTCOIN_VOUCHERS_ADDRESS })).toBeUndefined();
  });

  it.each(TON_DNS_ZONES.map(({ collectionName, resolver }) => [collectionName, resolver]))(
    'skips %s domains',
    (_, resolver) => {
      expect(getIsNftUnverified({ collectionAddress: resolver })).toBeUndefined();
    },
  );
});

describe('parsePayloadBase64', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('treats a jetton transfer payload sent to a non-jetton contract as unknown', async () => {
    mockResolveTokenWallet.mockRejectedValue(new Error('Not a jetton wallet'));

    const base64 = buildJettonTransferPayload();

    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('keeps a verified jetton transfer payload classified as token transfer', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: OWNER_ADDRESS });

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildJettonTransferPayload(),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({
      type: 'tokens:transfer',
      amount: 123n,
      tokenAddress: TOKEN_ADDRESS,
    });
    expect(mockResolveTokenWallet).toHaveBeenCalledWith(NETWORK, OUTER_ADDRESS);
  });

  it('treats a jetton transfer from a wallet owned by another address as unknown', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: RECIPIENT_ADDRESS });

    const base64 = buildJettonTransferPayload();
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('keeps a STON.fi v1 proxy TON deposit to the wallet owner classified as token transfer', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: STON_PTON_ADDRESS, ownerAddress: RECIPIENT_ADDRESS });

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildJettonTransferPayload(RECIPIENT_ADDRESS),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({
      type: 'tokens:transfer',
      tokenAddress: STON_PTON_ADDRESS,
    });
  });

  it('treats a STON.fi v1 proxy TON transfer to an address other than the wallet owner as unknown', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: STON_PTON_ADDRESS, ownerAddress: RESPONSE_ADDRESS });

    const base64 = buildJettonTransferPayload(RECIPIENT_ADDRESS);
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('keeps a jetton burn from a wallet of the expected owner classified as token burn', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: OWNER_ADDRESS });

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildJettonBurnPayload(),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({ type: 'tokens:burn', amount: 123n });
  });

  it('treats a jetton burn from a wallet owned by another address as unknown', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: RECIPIENT_ADDRESS });

    const base64 = buildJettonBurnPayload();
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('treats an NFT transfer payload sent to a non-NFT contract as unknown', async () => {
    mockFetchNftByAddress.mockResolvedValue(undefined);

    const base64 = buildNftTransferPayload();

    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('treats an NFT transfer payload as unknown when the item could not be loaded', async () => {
    mockFetchNftByAddress.mockRejectedValue(new Error('Failed to fetch'));

    const base64 = buildNftTransferPayload();

    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('keeps a verified NFT transfer payload classified as NFT transfer', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft());

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildNftTransferPayload(),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({
      type: 'nft:transfer',
      nftName: 'Test NFT',
    });
  });

  it('treats an NFT transfer payload from an item owned by another address as unknown', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft(RECIPIENT_ADDRESS));

    const base64 = buildNftTransferPayload();
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });
});

describe('parsePayloadBase64 with preloaded NFTs', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('uses the preloaded NFT instead of loading it', async () => {
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, buildNftTransferPayload(), {
      expectedOwnerAddress: OWNER_ADDRESS,
      nftsByRawAddress: { [OUTER_ADDRESS]: buildNft() },
    });

    expect(result).toMatchObject({ type: 'nft:transfer', nftName: 'Test NFT' });
    expect(mockFetchNftByAddress).not.toHaveBeenCalled();
  });

  it('treats an NFT missing from the preloaded ones as unknown', async () => {
    const base64 = buildNftTransferPayload();
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, {
      expectedOwnerAddress: OWNER_ADDRESS,
      nftsByRawAddress: {},
    });

    expect(result).toEqual({ type: 'unknown', base64 });
    expect(mockFetchNftByAddress).not.toHaveBeenCalled();
  });
});

describe('preloadPayloadNfts', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('loads the NFTs of the NFT payloads with one request', async () => {
    const nftsByRawAddress = { [OUTER_ADDRESS]: buildNft() };
    mockFetchNftsByAddresses.mockResolvedValue(nftsByRawAddress);

    const result = await preloadPayloadNfts(NETWORK, [
      { address: OUTER_ADDRESS, payload: buildNftTransferPayload() },
      { address: TOKEN_ADDRESS, payload: buildJettonTransferPayload() },
      { address: RECIPIENT_ADDRESS },
    ]);

    expect(result).toBe(nftsByRawAddress);
    expect(mockFetchNftsByAddresses).toHaveBeenCalledTimes(1);
    expect(mockFetchNftsByAddresses).toHaveBeenCalledWith(NETWORK, [OUTER_ADDRESS]);
  });

  it('skips the request when no payload transfers an NFT', async () => {
    const result = await preloadPayloadNfts(NETWORK, [
      { address: TOKEN_ADDRESS, payload: buildJettonTransferPayload() },
    ]);

    expect(result).toBeUndefined();
    expect(mockFetchNftsByAddresses).not.toHaveBeenCalled();
  });

  it('leaves the loading to the payload parsing when the request fails', async () => {
    mockFetchNftsByAddresses.mockRejectedValue(new Error('Failed to fetch'));

    const result = await preloadPayloadNfts(NETWORK, [
      { address: OUTER_ADDRESS, payload: buildNftTransferPayload() },
    ]);

    expect(result).toBeUndefined();
  });
});

function buildJettonTransferPayload(destination = RECIPIENT_ADDRESS) {
  return beginCell()
    .storeUint(JettonOpCode.Transfer, 32)
    .storeUint(1n, 64)
    .storeCoins(123n)
    .storeAddress(Address.parse(destination))
    .storeAddress(Address.parse(RESPONSE_ADDRESS))
    .storeMaybeRef(undefined)
    .storeCoins(0n)
    .storeBit(0)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildJettonBurnPayload() {
  return beginCell()
    .storeUint(JettonOpCode.Burn, 32)
    .storeUint(1n, 64)
    .storeCoins(123n)
    .storeAddress(Address.parse(RESPONSE_ADDRESS))
    .storeMaybeRef(undefined)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildNftTransferPayload() {
  return beginCell()
    .storeUint(NftOpCode.TransferOwnership, 32)
    .storeUint(1n, 64)
    .storeAddress(Address.parse(RECIPIENT_ADDRESS))
    .storeAddress(Address.parse(RESPONSE_ADDRESS))
    .storeMaybeRef(undefined)
    .storeCoins(0n)
    .storeBit(0)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildNft(ownerAddress = OWNER_ADDRESS): ApiNft {
  return {
    chain: 'ton',
    address: OUTER_ADDRESS,
    ownerAddress,
    index: 1,
    name: 'Test NFT',
    image: 'https://example.com/nft.png',
    thumbnail: 'https://example.com/nft-500.png',
    isOnSale: false,
    metadata: {},
    interface: 'default',
  };
}
