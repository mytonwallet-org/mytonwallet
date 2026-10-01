import { fetchNftByAddress, fetchNftItems, fetchNftsByAddresses, fetchNftTransfers } from './nfts';
import { callToncenterV3 } from './other';

// Toncenter answers 200 and silently ignores unknown query params, so a typo in a param name
// would never surface at runtime - these tests pin the wire format down instead
jest.mock('./other', () => ({ callToncenterV3: jest.fn(() => Promise.resolve({})) }));

jest.mock('../../../common/addresses', () => ({
  getNftSuperCollectionsByCollectionAddress: jest.fn(() => Promise.resolve({})),
  checkIsTrustedCollection: () => false,
  checkHasScamLink: () => false,
  getHasTrustedCollections: () => true,
}));

const NFT_ADDRESS = 'EQBtqQlC09xW_oOHJOrMofDmFndOrY7zCjd7bYELIoabO9JC';
const RAW_NFT_ADDRESS = '0:6da90942d3dc56fe838724eacca1f0e616774ead8ef30a377b6d810b22869b3b';
const WALLET_ADDRESS = 'UQB-anbTtZhmf-KztXAQVWyrlUBC04Ah60ao_ar9rthihczy';
const RAW_WALLET_ADDRESS = '0:7e6a76d3b598667fe2b3b57010556cab954042d38021eb46a8fdaafdaed86285';
const COLLECTION_ADDRESS = 'EQAkhd9AFlBOiJPwk8jZF9J1uW2t56LU8gECR4FxgvnrkbfZ';
const RAW_COLLECTION_ADDRESS = '0:2485df4016504e8893f093c8d917d275b96dade7a2d4f2010247817182f9eb91';
// The same addresses as above, in the testnet form: bounceable for the NFT and its collection,
// non-bounceable for the wallet
const TESTNET_NFT_ADDRESS = 'kQBtqQlC09xW_oOHJOrMofDmFndOrY7zCjd7bYELIoabO2nI';
const TESTNET_COLLECTION_ADDRESS = 'kQAkhd9AFlBOiJPwk8jZF9J1uW2t56LU8gECR4FxgvnrkQxT';
const TESTNET_WALLET_ADDRESS = '0QB-anbTtZhmf-KztXAQVWyrlUBC04Ah60ao_ar9rthihXd4';

const mockedCall = jest.mocked(callToncenterV3);

beforeEach(() => jest.clearAllMocks());

function getRequest() {
  const [network, path, params] = mockedCall.mock.calls[0];
  return { network, path, params };
}

describe('fetchNftItems', () => {
  it('queries the account NFTs by the raw owner address', async () => {
    await fetchNftItems('mainnet', { ownerAddress: WALLET_ADDRESS, limit: 50, offset: 100 });

    expect(getRequest()).toEqual({
      network: 'mainnet',
      path: '/nft/items',
      params: { owner_address: RAW_WALLET_ADDRESS, limit: 50, offset: 100, include_on_sale: true },
    });
  });

  it('queries NFTs by address', async () => {
    await fetchNftItems('mainnet', { addresses: [NFT_ADDRESS] });

    expect(getRequest().params).toEqual({ address: [RAW_NFT_ADDRESS], include_on_sale: true });
  });

  it('queries NFTs by collection', async () => {
    await fetchNftItems('mainnet', { collectionAddress: COLLECTION_ADDRESS });

    expect(getRequest().params).toEqual({ collection_address: RAW_COLLECTION_ADDRESS, include_on_sale: true });
  });

  it('omits the filters that were not asked for', async () => {
    await fetchNftItems('mainnet', {});

    expect(getRequest().params).toEqual({ include_on_sale: true });
  });

  it('always asks for the NFTs held by a sale contract', async () => {
    // The parameter defaults to `false`, which would silently hide every listed NFT from the gallery
    await fetchNftItems('mainnet', { ownerAddress: WALLET_ADDRESS });

    expect(getRequest().params).toMatchObject({ include_on_sale: true });
  });
});

describe('fetchNftByAddress', () => {
  it('parses the single requested NFT with the metadata of the same response', async () => {
    mockedCall.mockResolvedValueOnce({
      nft_items: [{ address: RAW_NFT_ADDRESS, index: '7', on_sale: false }],
      metadata: {
        [RAW_NFT_ADDRESS]: {
          is_indexed: true,
          token_info: [{ type: 'nft_items', name: 'Requested NFT' }],
        },
      },
    });

    const nft = await fetchNftByAddress('mainnet', NFT_ADDRESS);

    expect(getRequest()).toMatchObject({ path: '/nft/items', params: { address: [RAW_NFT_ADDRESS] } });
    expect(nft).toMatchObject({ address: NFT_ADDRESS, name: 'Requested NFT', index: 7 });
  });

  it('formats every address for testnet', async () => {
    mockedCall.mockResolvedValueOnce({
      nft_items: [{
        address: RAW_NFT_ADDRESS,
        collection_address: RAW_COLLECTION_ADDRESS,
        owner_address: RAW_WALLET_ADDRESS,
        index: '7',
        on_sale: false,
      }],
      metadata: {
        [RAW_NFT_ADDRESS]: {
          is_indexed: true,
          token_info: [{ type: 'nft_items', name: 'Requested NFT' }],
        },
      },
    });

    const nft = await fetchNftByAddress('testnet', NFT_ADDRESS);

    expect(nft).toMatchObject({
      name: 'Requested NFT',
      address: TESTNET_NFT_ADDRESS,
      collectionAddress: TESTNET_COLLECTION_ADDRESS,
      ownerAddress: TESTNET_WALLET_ADDRESS,
    });
  });

  it('returns nothing when the indexer does not know the NFT', async () => {
    mockedCall.mockResolvedValueOnce({ nft_items: [], metadata: {} });

    expect(await fetchNftByAddress('mainnet', NFT_ADDRESS)).toBeFalsy();
  });
});

describe('fetchNftsByAddresses', () => {
  it('requests every NFT at once and indexes the found ones by the raw address', async () => {
    mockedCall.mockResolvedValueOnce({
      nft_items: [{ address: RAW_NFT_ADDRESS, index: '7', on_sale: false }],
      metadata: {
        [RAW_NFT_ADDRESS]: {
          is_indexed: true,
          token_info: [{ type: 'nft_items', name: 'Requested NFT' }],
        },
      },
    });

    const nftsByRawAddress = await fetchNftsByAddresses('mainnet', [NFT_ADDRESS, WALLET_ADDRESS]);

    expect(mockedCall).toHaveBeenCalledTimes(1);
    expect(getRequest().params).toMatchObject({ address: [RAW_NFT_ADDRESS, RAW_WALLET_ADDRESS], limit: 2 });
    expect(Object.keys(nftsByRawAddress)).toEqual([RAW_NFT_ADDRESS]);
    expect(nftsByRawAddress[RAW_NFT_ADDRESS]).toMatchObject({ address: NFT_ADDRESS, name: 'Requested NFT' });
  });

  it('splits a long list into several requests', async () => {
    mockedCall
      .mockResolvedValueOnce({ nft_items: [], metadata: {} })
      .mockResolvedValueOnce({ nft_items: [], metadata: {} });
    const addresses = Array.from({ length: 150 }, (_, i) => `0:${i.toString(16).padStart(64, '0')}`);

    await fetchNftsByAddresses('mainnet', addresses);

    expect(mockedCall.mock.calls.map(([, , params]) => params!.limit)).toEqual([100, 50]);
  });
});

describe('fetchNftTransfers', () => {
  it('queries the transfers newer than the given moment, newest first', async () => {
    await fetchNftTransfers('mainnet', { ownerAddress: WALLET_ADDRESS, startUtime: 1700000000, limit: 100 });

    expect(getRequest()).toEqual({
      network: 'mainnet',
      path: '/nft/transfers',
      params: {
        owner_address: RAW_WALLET_ADDRESS,
        start_utime: 1700000000,
        limit: 100,
        sort: 'desc',
      },
    });
  });

  it('passes the direction through', async () => {
    await fetchNftTransfers('mainnet', { ownerAddress: WALLET_ADDRESS, direction: 'in' });

    expect(getRequest().params).toMatchObject({ direction: 'in' });
  });

  it('keeps `start_utime` out when there is no cursor', async () => {
    await fetchNftTransfers('mainnet', { ownerAddress: WALLET_ADDRESS });

    // `fetchJson` omits the params that are `undefined`, so the whole history is requested
    expect(getRequest().params!.start_utime).toBeUndefined();
  });
});
