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
import { JettonOpCode, NftOpCode, TeleitemOpCode } from '../constants';
import {
  getIsNftUnverified,
  getIsOnFragment,
  getTelemintCollectionAddress,
  parsePayloadBase64,
  preloadPayloadNfts,
} from './metadata';
import { toBase64Address, toRawAddress } from './tonCore';

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
const BENEFICIARY_ADDRESS = `0:${'6'.repeat(64)}`;
const AUCTION_INITIAL_MIN_BID = 2_000_000_000n;
const AUCTION_MAX_BID = 0n;
const AUCTION_MIN_BID_STEP = 5;
const AUCTION_MIN_EXTEND_TIME = 3600;
const AUCTION_DURATION = 86400;
const AUCTION_BID_AMOUNT = 7_000_000_000n;
const AUCTION_BID_TS = 1757944121;

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

describe('getIsOnFragment', () => {
  it('accepts the Telegram usernames collection regardless of hex case', () => {
    expect(getIsOnFragment({
      rawCollectionAddress: '0:80D78A35F955A14B679FAA887FF4CD5BFC0F43B4A4EEA2A7E6927F3701B273C2',
    })).toBe(true);
  });

  it('accepts the Telegram usernames collection in the user-friendly form', () => {
    expect(getIsOnFragment({
      collectionAddress: 'EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi',
    })).toBe(true);
  });

  it('rejects a hotlinked Fragment metadata URL without the collection', () => {
    expect(getIsOnFragment({})).toBe(false);
  });
});

describe('getTelemintCollectionAddress', () => {
  it('maps a Telegram username domain to the Fragment usernames collection', () => {
    expect(getTelemintCollectionAddress('enenf.t.me')?.toLowerCase())
      .toBe(toRawAddress(NFT_FRAGMENT_COLLECTIONS[1]).toLowerCase());
  });

  it('does not infer a collection from the NFT name', () => {
    expect(getTelemintCollectionAddress('@enenf')).toBeUndefined();
  });
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
    expect(mockResolveTokenWallet).toHaveBeenCalledWith(NETWORK, OUTER_ADDRESS, undefined);
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

  it('keeps a verified Fragment start-auction payload classified as start auction', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft());

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildTeleitemStartAuctionPayload(),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({
      type: 'teleitem:start-auction',
      nftName: 'Test NFT',
      beneficiaryAddress: toBase64Address(BENEFICIARY_ADDRESS, undefined, NETWORK),
      initialMinBid: AUCTION_INITIAL_MIN_BID,
      maxBid: AUCTION_MAX_BID,
      minBidStep: AUCTION_MIN_BID_STEP,
      minExtendTime: AUCTION_MIN_EXTEND_TIME,
      duration: AUCTION_DURATION,
    });
  });

  it('treats a Fragment start-auction payload from an item owned by another address as unknown', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft(RECIPIENT_ADDRESS));

    const base64 = buildTeleitemStartAuctionPayload();
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, base64, { expectedOwnerAddress: OWNER_ADDRESS });

    expect(result).toEqual({ type: 'unknown', base64 });
  });

  it('keeps a verified Fragment cancel-auction payload classified as cancel auction', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft());

    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildTeleitemCancelAuctionPayload(),
      { expectedOwnerAddress: OWNER_ADDRESS },
    );

    expect(result).toMatchObject({
      type: 'teleitem:cancel-auction',
      nftName: 'Test NFT',
    });
  });

  it('parses a Fragment first-bid deploy payload', async () => {
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, buildTeleitemDeployPayload());

    expect(result).toMatchObject({
      type: 'teleitem:deploy',
      tokenName: 'alice',
      beneficiaryAddress: toBase64Address(BENEFICIARY_ADDRESS, undefined, NETWORK),
      initialMinBid: AUCTION_INITIAL_MIN_BID,
    });
  });

  it('parses a Fragment first-bid deploy v2 payload', async () => {
    const result = await parsePayloadBase64(
      NETWORK,
      OUTER_ADDRESS,
      buildTeleitemDeployPayload(TeleitemOpCode.DeployV2),
    );

    expect(result).toMatchObject({
      type: 'teleitem:deploy',
      tokenName: 'alice',
    });
  });

  it('parses a standalone teleitem bid-info payload', async () => {
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, buildTeleitemBidInfoPayload());

    expect(result).toEqual({
      type: 'teleitem:bid-info',
      amount: AUCTION_BID_AMOUNT,
      bidTs: AUCTION_BID_TS,
    });
  });

  it('reads teleitem bid-info from an NFT ownership-assigned forward payload', async () => {
    mockFetchNftByAddress.mockResolvedValue(buildNft());

    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, buildNftOwnershipAssignedBidPayload());

    expect(result).toMatchObject({
      type: 'nft:ownership-assigned',
      bidAmount: AUCTION_BID_AMOUNT,
      bidTs: AUCTION_BID_TS,
    });
  });

  it('parses a teleitem return-bid payload', async () => {
    const result = await parsePayloadBase64(NETWORK, OUTER_ADDRESS, buildTeleitemReturnBidPayload());

    expect(result).toMatchObject({
      type: 'teleitem:return-bid',
      queryId: 1n,
    });
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
    expect(mockFetchNftsByAddresses).toHaveBeenCalledWith(NETWORK, [OUTER_ADDRESS], undefined);
  });

  it('loads the NFTs of Fragment auction payloads with one request', async () => {
    const nftsByRawAddress = { [OUTER_ADDRESS]: buildNft() };
    mockFetchNftsByAddresses.mockResolvedValue(nftsByRawAddress);

    const result = await preloadPayloadNfts(NETWORK, [
      { address: OUTER_ADDRESS, payload: buildTeleitemStartAuctionPayload() },
      { address: TOKEN_ADDRESS, payload: buildTeleitemCancelAuctionPayload() },
    ]);

    expect(result).toBe(nftsByRawAddress);
    expect(mockFetchNftsByAddresses).toHaveBeenCalledWith(NETWORK, [OUTER_ADDRESS, TOKEN_ADDRESS], undefined);
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

function buildTeleitemAuctionConfig() {
  return beginCell()
    .storeAddress(Address.parse(BENEFICIARY_ADDRESS))
    .storeCoins(AUCTION_INITIAL_MIN_BID)
    .storeCoins(AUCTION_MAX_BID)
    .storeUint(AUCTION_MIN_BID_STEP, 8)
    .storeUint(AUCTION_MIN_EXTEND_TIME, 32)
    .storeUint(AUCTION_DURATION, 32)
    .endCell();
}

function buildTeleitemStartAuctionPayload() {
  return beginCell()
    .storeUint(TeleitemOpCode.StartAuction, 32)
    .storeUint(1n, 64)
    .storeRef(buildTeleitemAuctionConfig())
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildTeleitemCancelAuctionPayload() {
  return beginCell()
    .storeUint(TeleitemOpCode.CancelAuction, 32)
    .storeUint(1n, 64)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildTeleitemDeployPayload(opCode: TeleitemOpCode = TeleitemOpCode.Deploy) {
  const tokenName = Buffer.from('alice', 'utf-8');
  const payload = beginCell()
    .storeUint(opCode, 32)
    .storeBuffer(Buffer.alloc(64))
    .storeUint(1, 32)
    .storeUint(0, 32)
    .storeUint(0xffffffff, 32)
    .storeUint(tokenName.length, 8)
    .storeBuffer(tokenName)
    .storeRef(beginCell().endCell())
    .storeRef(buildTeleitemAuctionConfig())
    .storeBit(0);

  if (opCode === TeleitemOpCode.DeployV2) {
    payload.storeBit(0);
  }

  return payload.endCell().toBoc().toString('base64');
}

function buildTeleitemBidInfoPayload() {
  return beginCell()
    .storeUint(TeleitemOpCode.BidInfo, 32)
    .storeCoins(AUCTION_BID_AMOUNT)
    .storeUint(AUCTION_BID_TS, 32)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildNftOwnershipAssignedBidPayload() {
  return beginCell()
    .storeUint(NftOpCode.OwnershipAssigned, 32)
    .storeUint(1n, 64)
    .storeAddress(Address.parse(OWNER_ADDRESS))
    .storeBit(0)
    .storeUint(TeleitemOpCode.BidInfo, 32)
    .storeCoins(AUCTION_BID_AMOUNT)
    .storeUint(AUCTION_BID_TS, 32)
    .endCell()
    .toBoc()
    .toString('base64');
}

function buildTeleitemReturnBidPayload() {
  return beginCell()
    .storeUint(TeleitemOpCode.ReturnBid, 32)
    .storeUint(1n, 64)
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
