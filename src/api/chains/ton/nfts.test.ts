import type { MetadataMap, NftItemsResponse, NftItemState, NftTransferState } from './toncenter/types';

import { fetchNftItems, fetchNftTransfers } from './toncenter/nfts';
import { calculateNftTransferFee, checkNftOwnership, getAccountNfts, getNftUpdates } from './nfts';
import { isActiveNonWalletContract } from './wallet';

jest.mock('./toncenter/nfts', () => ({
  ...jest.requireActual('./toncenter/nfts'),
  fetchNftItems: jest.fn(),
  fetchNftTransfers: jest.fn(),
}));

jest.mock('./wallet', () => ({ isActiveNonWalletContract: jest.fn() }));

jest.mock('../../common/accounts', () => ({
  fetchStoredWallet: jest.fn(() => Promise.resolve({ address: 'UQB-anbTtZhmf-KztXAQVWyrlUBC04Ah60ao_ar9rthihczy' })),
}));

jest.mock('../../common/addresses', () => ({
  getNftSuperCollectionsByCollectionAddress: jest.fn(() => Promise.resolve({})),
  checkIsTrustedCollection: () => false,
  checkHasScamLink: () => false,
  getHasTrustedCollections: () => true,
}));

// Only the batch size is overridden - the rest of the chain config is needed by the modules under test
jest.mock('../../../util/chain', () => {
  const actual = jest.requireActual('../../../util/chain');
  return {
    ...actual,
    getChainConfig: (chain: string) => ({ ...actual.getChainConfig(chain), nftBatchLimit: 2, nftBatchPauseMs: 0 }),
  };
});

const ACCOUNT_ID = '0-ton-mainnet';
const WALLET_ADDRESS = 'UQB-anbTtZhmf-KztXAQVWyrlUBC04Ah60ao_ar9rthihczy';
const RAW_WALLET_ADDRESS = '0:7E6A76D3B598667FE2B3B57010556CAB954042D38021EB46A8FDAAFDAED86285';
const RAW_STRANGER_ADDRESS = '0:0D11588CDC0290CE2E808F7B047B2A85BBCA57AA1CBD43DC46A0877FD2AA7708';
const RAW_NFT_ADDRESS = '0:6DA90942D3DC56FE838724EACCA1F0E616774EAD8EF30A377B6D810B22869B3B';
const RAW_NFT_ADDRESS_2 = '0:2485DF4016504E8893F093C8D917D275B96DADE7A2D4F2010247817182F9EB91';
const RAW_COLLECTION_ADDRESS = '0:4357CFBB796F7E1CD0FF86111FEA43EAFF16A6184265FAA6A7BBC085CB550F2D';
const RAW_MW_CARDS_COLLECTION = '0:901362FD85FC31D55F2C82617D91EADA1F1D6B34AF559A047572D56F20D046CA';
const PROXIED_MEDIUM = 'https://imgproxy.toncenter.com/signature/pr:medium/encoded';

const mockedFetchNftItems = jest.mocked(fetchNftItems);
const mockedFetchNftTransfers = jest.mocked(fetchNftTransfers);
const mockedIsActiveSmartContract = jest.mocked(isActiveNonWalletContract);

beforeEach(() => {
  jest.clearAllMocks();
  mockedIsActiveSmartContract.mockResolvedValue(false);
});

function makeItem(address: string, overrides?: Partial<NftItemState>): NftItemState {
  return {
    address,
    init: true,
    index: '1',
    collection_address: RAW_COLLECTION_ADDRESS,
    owner_address: RAW_WALLET_ADDRESS,
    real_owner: RAW_WALLET_ADDRESS,
    on_sale: false,
    ...overrides,
  };
}

function makeMetadata(addresses: string[]): MetadataMap {
  return Object.fromEntries(addresses.map((address) => [address, {
    is_indexed: true,
    token_info: [{
      type: 'nft_items' as const,
      name: `NFT ${address.slice(-4)}`,
      nft_index: '1',
      extra: { _image_medium: PROXIED_MEDIUM },
    }],
  }]));
}

function makeResponse(items: NftItemState[], metadataAddresses = items.map((i) => i.address)): NftItemsResponse {
  return { nft_items: items, address_book: {}, metadata: makeMetadata(metadataAddresses) };
}

describe('getAccountNfts', () => {
  it('requests the account NFTs and parses them', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS)]));

    const nfts = await getAccountNfts(ACCOUNT_ID, { limit: 10 });

    expect(mockedFetchNftItems).toHaveBeenCalledWith('mainnet', expect.objectContaining({
      ownerAddress: WALLET_ADDRESS,
      limit: 10,
    }));
    expect(nfts).toHaveLength(1);
    expect(nfts[0]).toMatchObject({ chain: 'ton', thumbnail: PROXIED_MEDIUM, isOnSale: false });
  });

  it('keeps paginating when an NFT of a full batch cannot be parsed', async () => {
    // The batch is full, so pagination must continue even though one entry yields no NFT
    mockedFetchNftItems
      .mockResolvedValueOnce(makeResponse(
        [makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2, { collection_address: RAW_MW_CARDS_COLLECTION })],
        [RAW_NFT_ADDRESS], // The card has no metadata
      ))
      .mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS_2)]));

    const nfts = await getAccountNfts(ACCOUNT_ID);

    expect(mockedFetchNftItems).toHaveBeenCalledTimes(2);
    expect(nfts).toHaveLength(2);
  });

  it('keeps an NFT the indexer has not fetched the metadata of', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, { index: '170' })], []));

    const [nft] = await getAccountNfts(ACCOUNT_ID, { limit: 1 });

    expect(nft).toMatchObject({ index: 170, ownerAddress: WALLET_ADDRESS, isMetadataMissing: true });
    expect(nft.name).toBeUndefined();
  });

  it('stops paginating on a partial batch', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS)]));

    await getAccountNfts(ACCOUNT_ID);

    expect(mockedFetchNftItems).toHaveBeenCalledTimes(1);
  });

  it('skips the request for the Telegram gifts super collection', async () => {
    const nfts = await getAccountNfts(ACCOUNT_ID, { collectionAddress: 'super:telegram-gifts' });

    expect(mockedFetchNftItems).not.toHaveBeenCalled();
    expect(nfts).toEqual([]);
  });

  it('reads `on_sale` from the item', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, { on_sale: true })]));

    const [nft] = await getAccountNfts(ACCOUNT_ID, { limit: 1 });

    expect(nft.isOnSale).toBe(true);
  });
});

describe('checkNftOwnership', () => {
  it('confirms ownership through the sale contract via `real_owner`', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, {
      on_sale: true,
      owner_address: RAW_STRANGER_ADDRESS, // The sale contract holds the NFT
      real_owner: RAW_WALLET_ADDRESS,
    })]));

    expect(await checkNftOwnership(ACCOUNT_ID, RAW_NFT_ADDRESS)).toBe(true);
  });

  it('rejects an NFT owned by somebody else', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, {
      owner_address: RAW_STRANGER_ADDRESS,
      real_owner: RAW_STRANGER_ADDRESS,
    })]));

    expect(await checkNftOwnership(ACCOUNT_ID, RAW_NFT_ADDRESS)).toBe(false);
  });

  it('rejects an unknown NFT', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([]));

    expect(await checkNftOwnership(ACCOUNT_ID, RAW_NFT_ADDRESS)).toBe(false);
  });
});

describe('getNftUpdates', () => {
  function makeTransfer(overrides: Partial<NftTransferState>): NftTransferState {
    return {
      query_id: '0',
      nft_address: RAW_NFT_ADDRESS,
      nft_collection: RAW_COLLECTION_ADDRESS,
      transaction_hash: 'hash',
      transaction_lt: '1',
      transaction_now: 1000,
      transaction_aborted: false,
      old_owner: RAW_STRANGER_ADDRESS,
      new_owner: RAW_WALLET_ADDRESS,
      ...overrides,
    };
  }

  function mockTransfers(transfers: NftTransferState[]) {
    mockedFetchNftTransfers.mockResolvedValueOnce({
      nft_transfers: transfers,
      address_book: {},
      metadata: makeMetadata([RAW_NFT_ADDRESS]),
    });
  }

  it('reports an incoming NFT with its parsed data', async () => {
    mockTransfers([makeTransfer({})]);

    const [, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(updates).toHaveLength(1);
    expect(updates[0]).toMatchObject({ type: 'nftReceived' });
    expect((updates[0] as any).nft).toMatchObject({ thumbnail: PROXIED_MEDIUM });
  });

  it('reports an outgoing NFT as sent', async () => {
    mockTransfers([makeTransfer({ old_owner: RAW_WALLET_ADDRESS, new_owner: RAW_STRANGER_ADDRESS })]);

    const [, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(updates[0]).toMatchObject({ type: 'nftSent', chain: 'ton' });
  });

  it('reports an NFT sent to a smart contract as put up for sale', async () => {
    mockedIsActiveSmartContract.mockResolvedValue(true);
    mockTransfers([makeTransfer({ old_owner: RAW_WALLET_ADDRESS, new_owner: RAW_STRANGER_ADDRESS })]);

    const [, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(updates[0]).toMatchObject({ type: 'nftPutUpForSale' });
  });

  it('returns the newest timestamp and processes transfers oldest first', async () => {
    mockTransfers([
      makeTransfer({ transaction_now: 3000, old_owner: RAW_WALLET_ADDRESS, new_owner: RAW_STRANGER_ADDRESS }),
      makeTransfer({ transaction_now: 2000 }),
    ]);

    const [fromSec, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(fromSec).toBe(3000);
    expect(updates.map((update) => update.type)).toEqual(['nftReceived', 'nftSent']);
  });

  it('keeps the previous timestamp when nothing happened', async () => {
    mockTransfers([]);

    const [fromSec, updates] = await getNftUpdates(ACCOUNT_ID, 1234);

    expect(fromSec).toBe(1234);
    expect(updates).toEqual([]);
  });

  it('asks the indexer only for transfers newer than the cursor', async () => {
    mockTransfers([]);

    await getNftUpdates(ACCOUNT_ID, 555);

    expect(mockedFetchNftTransfers).toHaveBeenCalledWith('mainnet', expect.objectContaining({
      ownerAddress: WALLET_ADDRESS,
      startUtime: 555,
    }));
  });
});

describe('calculateNftTransferFee', () => {
  it('calculates for 1 NFT', () => {
    expect(calculateNftTransferFee(1, 1, 2939195n, 10000000n)).toBe(12939195n);
  });

  it('calculates for batch', () => {
    expect(calculateNftTransferFee(3, 3, 6001837n, 100000000n)).toBe(306001837n);
  });

  it('calculates for multiple complete and 1 incomplete batch', () => {
    expect(calculateNftTransferFee(9, 4, 7533158n, 1000000000n)).toBe(9018832895n);
  });

  it('calculates for multiple complete batchs', () => {
    expect(calculateNftTransferFee(12, 4, 7533158n, 10000000000n)).toBe(120022599474n);
  });
});
