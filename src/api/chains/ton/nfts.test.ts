import '../../../global/actions/apiUpdates/initial';

import * as idb from 'idb-keyval';

import type { GlobalState } from '../../../global/types';
import type { NftSyncSnapshot } from '../../common/nftSync';
import type { ApiNft, ApiUpdate, ApiUpdateNftPutUpForSale } from '../../types';
import type { MetadataMap, NftItemsResponse, NftItemState, NftTransferState } from './toncenter/types';

import { TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../config';
import { buildTelegramGiftCatalog } from '../../../global/helpers/telegramGiftCatalog';
import { addActionHandler, getGlobal, setGlobal } from '../../../global/index';
import { getChainConfig } from '../../../util/chain';
import { toBase64Address } from './util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { callBackendGet } from '../../common/backend';
import { createNftSync } from '../../common/nftSync';
import { getCurrentStorage } from '../../storages';
import { fetchNftItems, fetchNftTransfers, parseNftItem } from './toncenter/nfts';
import { checkNftOwnership, createTonNftSync, getAccountNfts, getNftUpdates, streamAllAccountNfts } from './nfts';
import { setupNftPolling } from './polling';
import { isActiveNonWalletContract } from './wallet';

jest.mock('../../../api', () => ({ callApi: jest.fn(), callApiWithThrow: jest.fn() }));
jest.mock('../../../global/cache', () => ({ persistCache: jest.fn(() => true) }));
jest.mock('../../../global/index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(),
}));
jest.mock('../../../config', () => ({ ...jest.requireActual('../../../config'), IS_AIR_APP: false }));

jest.mock('./toncenter/nfts', () => ({
  ...jest.requireActual('./toncenter/nfts'),
  fetchNftItems: jest.fn(),
  fetchNftTransfers: jest.fn(),
  parseNftItem: jest.fn(jest.requireActual('./toncenter/nfts').parseNftItem),
}));

jest.mock('./wallet', () => ({ isActiveNonWalletContract: jest.fn() }));

jest.mock('../../common/nftSync', () => ({ createNftSync: jest.fn() }));
jest.mock('../../common/backend', () => ({ callBackendGet: jest.fn() }));
jest.mock('../../storages', () => ({ getCurrentStorage: jest.fn() }));
jest.mock('idb-keyval', () => ({
  createStore: jest.fn(() => jest.fn()),
  get: jest.fn(), set: jest.fn(), del: jest.fn(), delMany: jest.fn(), keys: jest.fn(),
}));

jest.mock('./toncenter/socket', () => ({
  getToncenterSocket: () => ({ watchWallets: () => ({ isConnected: true, destroy: jest.fn() }) }),
}));

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
    getChainConfig: jest.fn((chain: string) => ({
      ...actual.getChainConfig(chain), nftBatchLimit: 2, nftBatchPauseMs: 0,
    })),
  };
});

const ACCOUNT_ID = '0-ton-mainnet';
const WALLET_ADDRESS = 'UQB-anbTtZhmf-KztXAQVWyrlUBC04Ah60ao_ar9rthihczy';
const RAW_WALLET_ADDRESS = '0:7E6A76D3B598667FE2B3B57010556CAB954042D38021EB46A8FDAAFDAED86285';
const RAW_STRANGER_ADDRESS = '0:0D11588CDC0290CE2E808F7B047B2A85BBCA57AA1CBD43DC46A0877FD2AA7708';
const RAW_NFT_ADDRESS = '0:6DA90942D3DC56FE838724EACCA1F0E616774EAD8EF30A377B6D810B22869B3B';
const RAW_NFT_ADDRESS_2 = '0:2485DF4016504E8893F093C8D917D275B96DADE7A2D4F2010247817182F9EB91';
const RAW_NFT_ADDRESS_3 = `0:${'A'.repeat(64)}`;
const RAW_NFT_ADDRESS_4 = `0:${'B'.repeat(64)}`;
const RAW_COLLECTION_ADDRESS = '0:4357CFBB796F7E1CD0FF86111FEA43EAFF16A6184265FAA6A7BBC085CB550F2D';
const RAW_MW_CARDS_COLLECTION = '0:901362FD85FC31D55F2C82617D91EADA1F1D6B34AF559A047572D56F20D046CA';
const PROXIED_MEDIUM = 'https://imgproxy.toncenter.com/signature/pr:medium/encoded';

const mockedFetchNftItems = jest.mocked(fetchNftItems);
const mockedFetchNftTransfers = jest.mocked(fetchNftTransfers);
const mockedParseNftItem = jest.mocked(parseNftItem);
const mockedIsActiveSmartContract = jest.mocked(isActiveNonWalletContract);
const apiUpdateHandler = jest.mocked(addActionHandler).mock.calls.find(([name]) => name === 'apiUpdate')![1] as (
  global: GlobalState, actions: AnyLiteral, update: ApiUpdate,
) => void;

beforeEach(() => {
  jest.clearAllMocks();
  mockedFetchNftItems.mockReset();
  jest.mocked(getNftSuperCollectionsByCollectionAddress).mockReset().mockResolvedValue({});
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
  it('rejects a repeated full inventory page instead of treating it as progress', async () => {
    const page = makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]);
    mockedFetchNftItems.mockResolvedValueOnce(page).mockResolvedValueOnce(page)
      .mockResolvedValueOnce(makeResponse([]));

    await expect(getAccountNfts(ACCOUNT_ID)).rejects.toThrow('Non-progressing TON NFT page');
    expect(mockedFetchNftItems).toHaveBeenCalledTimes(2);
  });

  it('deduplicates overlapping pages while advancing by raw page length', async () => {
    mockedFetchNftItems
      .mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]))
      .mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS_2.toLowerCase()), makeItem(RAW_NFT_ADDRESS_3)]))
      .mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS_4)]));
    const nfts = await getAccountNfts(ACCOUNT_ID);
    expect(nfts).toHaveLength(4);
    expect(new Set(nfts.map((nft) => nft.address)).size).toBe(4);
    expect(mockedFetchNftItems.mock.calls.map(([, options]) => options.offset)).toEqual([0, 2, 4]);
  });

  it.each([0, 2])(
    'terminates an inventory at an empty page after %s items', async (count) => {
      const items = [makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)].slice(0, count);
      mockedFetchNftItems.mockResolvedValueOnce(makeResponse(items)).mockResolvedValueOnce(makeResponse([]));
      expect(await getAccountNfts(ACCOUNT_ID)).toHaveLength(items.length);
      expect(mockedFetchNftItems).toHaveBeenCalledTimes(items.length ? 2 : 1);
    },
  );

  it('does not certify a complete inventory with an invalid raw identity', async () => {
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem('invalid-address')]));
    await expect(getAccountNfts(ACCOUNT_ID)).rejects.toThrow('Invalid raw TON NFT address');
  });

  it('rejects repeated full pages even when every item was filtered during parsing', async () => {
    const page = makeResponse([
      makeItem(RAW_NFT_ADDRESS, { collection_address: RAW_MW_CARDS_COLLECTION }),
      makeItem(RAW_NFT_ADDRESS_2, { collection_address: RAW_MW_CARDS_COLLECTION }),
    ], []);
    mockedFetchNftItems.mockResolvedValueOnce(page).mockResolvedValueOnce(page);
    await expect(getAccountNfts(ACCOUNT_ID)).rejects.toThrow('Non-progressing TON NFT page');
    expect(mockedFetchNftItems).toHaveBeenCalledTimes(2);
  });

  it('allows a fresh retry after a repeated page failure', async () => {
    const page = makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]);
    mockedFetchNftItems.mockResolvedValueOnce(page).mockResolvedValueOnce(page);
    await expect(getAccountNfts(ACCOUNT_ID)).rejects.toThrow('Non-progressing TON NFT page');
    mockedFetchNftItems.mockResolvedValueOnce(page).mockResolvedValueOnce(makeResponse([]));
    expect(await getAccountNfts(ACCOUNT_ID)).toHaveLength(2);
  });

  it('does not stream a response delivered after cancellation', async () => {
    const controller = new AbortController();
    mockedFetchNftItems.mockImplementationOnce(() => {
      controller.abort();
      return Promise.resolve(makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]));
    });
    const onBatch = jest.fn();
    await streamAllAccountNfts(ACCOUNT_ID, { signal: controller.signal, onBatch });
    expect(onBatch).not.toHaveBeenCalled();
    expect(mockedFetchNftItems).toHaveBeenCalledTimes(1);
  });

  it('does not request inventory when cancelled while waiting for classification', async () => {
    const controller = new AbortController();
    jest.mocked(getNftSuperCollectionsByCollectionAddress).mockImplementationOnce(() => {
      controller.abort();
      return Promise.resolve({});
    });
    const onBatch = jest.fn();
    await streamAllAccountNfts(ACCOUNT_ID, { signal: controller.signal, onBatch });
    expect(mockedFetchNftItems).not.toHaveBeenCalled();
    expect(onBatch).not.toHaveBeenCalled();
  });

  it('rejects a repeated streaming page without emitting it again', async () => {
    const page = makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]);
    mockedFetchNftItems.mockResolvedValueOnce(page).mockResolvedValueOnce(page);
    const onBatch = jest.fn();
    await expect(streamAllAccountNfts(ACCOUNT_ID, { onBatch })).rejects.toThrow('Non-progressing TON NFT page');
    expect(onBatch).toHaveBeenCalledTimes(1);
  });

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

  it('reports an NFT sent to a smart contract as put up for sale, with its current state', async () => {
    mockedIsActiveSmartContract.mockResolvedValue(true);
    mockTransfers([makeTransfer({ old_owner: RAW_WALLET_ADDRESS, new_owner: RAW_STRANGER_ADDRESS })]);
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, {
      on_sale: true,
      owner_address: RAW_STRANGER_ADDRESS, // The sale contract holds the NFT
      real_owner: RAW_WALLET_ADDRESS,
    })]));

    const [, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(updates[0]).toMatchObject({
      type: 'nftPutUpForSale',
      nft: { isOnSale: true, ownerAddress: WALLET_ADDRESS },
    });
  });

  it('leaves out the NFT of a repeated listing once the NFT has been sold', async () => {
    mockedIsActiveSmartContract.mockResolvedValue(true);
    mockTransfers([makeTransfer({ old_owner: RAW_WALLET_ADDRESS, new_owner: RAW_STRANGER_ADDRESS })]);
    mockedFetchNftItems.mockResolvedValueOnce(makeResponse([makeItem(RAW_NFT_ADDRESS, {
      owner_address: RAW_STRANGER_ADDRESS, // The buyer
      real_owner: RAW_STRANGER_ADDRESS,
    })]));

    const [, updates] = await getNftUpdates(ACCOUNT_ID, 0);

    expect(updates[0]).toMatchObject({ type: 'nftPutUpForSale' });
    expect((updates[0] as ApiUpdateNftPutUpForSale).nft).toBeUndefined();
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

describe('NFT sync parsing and updates', () => {
  const syncClient = {
    load: jest.fn<ReturnType<ReturnType<typeof createNftSync>['load']>, []>(),
    sync: jest.fn<ReturnType<ReturnType<typeof createNftSync>['sync']>, [AbortSignal?]>(),
    getRetryAt: jest.fn<number | undefined, []>(),
  };

  beforeEach(() => {
    jest.mocked(getChainConfig).mockImplementation((chain) => ({
      ...jest.requireActual('../../../util/chain').getChainConfig(chain), nftBatchPauseMs: 0,
    }));
    syncClient.load.mockReset().mockResolvedValue(undefined);
    syncClient.sync.mockReset().mockResolvedValue(undefined);
    syncClient.getRetryAt.mockReset().mockReturnValue(undefined);
    jest.mocked(createNftSync).mockReturnValue(syncClient);
  });

  function makeSnapshot(
    items: NftItemState[], metadata = makeMetadata(items.map((item) => item.address)),
  ): NftSyncSnapshot {
    return {
      schemaVersion: 1,
      syncToken: 'token',
      items: Object.fromEntries(items.map((item) => [item.address, item])),
      metadata,
    };
  }

  it('rejects unavailable classification and reclassifies an unchanged snapshot after recovery', async () => {
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS)]);
    syncClient.sync.mockResolvedValue({ previous: snapshot, snapshot, reset: false, changedAddresses: [] });
    jest.mocked(getNftSuperCollectionsByCollectionAddress).mockRejectedValueOnce(new Error('Unavailable'));
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);

    await expect(sync.poll()).rejects.toThrow('Unavailable');
    expect(onUpdate).not.toHaveBeenCalled();
    expect(getNftSuperCollectionsByCollectionAddress).toHaveBeenCalledWith(true);
    expect(await sync.poll()).toBe(true);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'updateNfts', isFullLoading: false, streamedAddresses: [expect.any(String)],
    }));
    onUpdate.mockClear();
    expect(await sync.poll()).toBe(true);
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('reparses restored NFTs when collection classification changes without NFT changes', async () => {
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS)]);
    syncClient.load.mockResolvedValue(snapshot);
    syncClient.sync.mockResolvedValue({ previous: snapshot, snapshot, reset: false, changedAddresses: [] });
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);
    await sync.restore();
    onUpdate.mockClear();
    mockedParseNftItem.mockClear();
    const refreshedRegistry = {
      [toBase64Address(RAW_COLLECTION_ADDRESS, true, 'mainnet')]: {
        id: TELEGRAM_GIFTS_SUPER_COLLECTION, name: 'Telegram Gifts',
      },
    };
    jest.mocked(getNftSuperCollectionsByCollectionAddress).mockResolvedValue(refreshedRegistry);

    expect(await sync.poll()).toBe(true);
    expect(mockedParseNftItem).toHaveBeenCalledWith('mainnet', expect.anything(), snapshot.metadata, refreshedRegistry);
    expect(onUpdate).toHaveBeenCalledTimes(2);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      isFullLoading: false, nfts: [expect.objectContaining({ isTelegramGift: true })],
    }));
    onUpdate.mockClear();
    expect(await sync.poll()).toBe(true);
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('does not fetch or stream a supposedly complete inventory without classification', async () => {
    jest.mocked(getNftSuperCollectionsByCollectionAddress).mockRejectedValueOnce(new Error('Unavailable'));
    const onBatch = jest.fn();
    await expect(streamAllAccountNfts(ACCOUNT_ID, { onBatch })).rejects.toThrow('Unavailable');
    expect(getNftSuperCollectionsByCollectionAddress).toHaveBeenCalledWith(true);
    expect(mockedFetchNftItems).not.toHaveBeenCalled();
    expect(onBatch).not.toHaveBeenCalled();
  });

  it('leaves Classic with identical NFT addresses and fields after direct polling or a sync snapshot', async () => {
    jest.useFakeTimers();
    let directPolling: ReturnType<typeof setupNftPolling> | undefined;
    try {
      const chainConfig = getChainConfig('ton');
      jest.mocked(getChainConfig).mockReturnValue({ ...chainConfig, nftBatchLimit: 2 });
      const pages = [
        makeResponse([makeItem(RAW_NFT_ADDRESS, { on_sale: true }), makeItem(RAW_NFT_ADDRESS_2, { index: '2' })]),
        makeResponse([makeItem(RAW_NFT_ADDRESS_3, { index: '3' })]),
      ];
      mockedFetchNftItems.mockResolvedValueOnce(pages[0]).mockResolvedValueOnce(pages[1]);
      syncClient.sync.mockResolvedValueOnce(undefined);
      const directUpdates: ApiUpdate[] = [];
      directPolling = setupNftPolling(ACCOUNT_ID, WALLET_ADDRESS, (update) => directUpdates.push(update));
      await jest.advanceTimersByTimeAsync(10);
      await directPolling.firstFullLoadPromise;
      directPolling.stop();
      expect(mockedFetchNftItems).toHaveBeenCalledTimes(2);
      expect(mockedFetchNftItems.mock.calls.map(([, options]) => options.offset)).toEqual([0, 2]);
      jest.mocked(getChainConfig).mockReturnValue(chainConfig);

      const items = pages.flatMap((page) => page.nft_items);
      syncClient.sync.mockResolvedValueOnce({
        previous: undefined, snapshot: makeSnapshot(items, { ...pages[0].metadata, ...pages[1].metadata }),
        reset: true, changedAddresses: items.map((item) => item.address),
      });
      const syncUpdates: ApiUpdate[] = [];
      const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, (update) => syncUpdates.push(update));
      expect(await sync.poll()).toBe(true);

      // Direct polling emits each Toncenter page; sync batches its snapshot by the configured limit.
      // Both sequences are applied by Classic's real update handler before their final state is compared.
      expect(directUpdates.filter((update) => (
        update.type === 'updateNfts' && update.isFullLoading !== undefined
      ))).toHaveLength(3);
      expect(syncUpdates).toHaveLength(2);
      function applyInClassic(updates: ApiUpdate[]) {
        let global = {
          accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'mnemonic', byChain: {} } } },
          byAccountId: { [ACCOUNT_ID]: {} },
          settings: { byAccountId: { [ACCOUNT_ID]: {} } },
        } as unknown as GlobalState;
        jest.mocked(setGlobal).mockImplementation((next) => {
          global = next;
          jest.mocked(getGlobal).mockReturnValue(next);
        });
        const actions = { checkCardNftOwnership: jest.fn() };
        updates.forEach((update) => apiUpdateHandler(global, actions, update));
        const nfts = global.byAccountId[ACCOUNT_ID].nfts!;
        return { addresses: nfts.orderedAddresses, byAddress: nfts.byAddress };
      }
      const directState = applyInClassic(directUpdates);
      expect(directState.addresses).toHaveLength(3);
      expect(applyInClassic(syncUpdates)).toEqual(directState);
    } finally {
      directPolling?.stop();
      jest.clearAllTimers();
      jest.useRealTimers();
    }
  });

  it.each([false, true])('restores the wire snapshot with Air=%s and skips an unchanged delta', async (isAirApp) => {
    const response = makeResponse([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)], [RAW_NFT_ADDRESS]);
    const snapshot = makeSnapshot(response.nft_items, response.metadata);
    mockedFetchNftItems.mockResolvedValueOnce(response);
    const directNfts = await getAccountNfts(ACCOUNT_ID, { limit: 2 });
    syncClient.load.mockResolvedValueOnce(snapshot);
    syncClient.sync.mockResolvedValueOnce({ previous: snapshot, snapshot, reset: false, changedAddresses: [] });
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);

    const airFlag = jest.replaceProperty(jest.requireMock('../../../config'), 'IS_AIR_APP', isAirApp);
    try {
      await sync.restore();
    } finally {
      airFlag.restore();
    }
    expect(onUpdate.mock.calls.map(([update]) => update)).toEqual([
      { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: directNfts, isFullLoading: true },
      {
        type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: isAirApp ? [] : directNfts, isFullLoading: false,
        streamedAddresses: directNfts.map((nft) => nft.address),
      },
    ]);
    expect(mockedParseNftItem).toHaveBeenCalledTimes(2);
    mockedParseNftItem.mockClear();
    onUpdate.mockClear();
    expect(await sync.poll()).toBe(true);
    expect(mockedParseNftItem).not.toHaveBeenCalled();
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it.each([
    ['restore', false, 500],
    ['restore', true, undefined],
    ['reset', false, 500],
    ['reset', true, 500],
    ['delta', false, 500],
    ['delta', true, 500],
  ] as const)('streams a 1201-item %s in chunks with Air=%s and limit=%s', async (source, isAirApp, nftBatchLimit) => {
    const items = Array.from({ length: 1201 }, (_, index) => makeItem(
      `0:${(index + 1).toString(16).padStart(64, '0')}`, { index: String(index) },
    ));
    const snapshot = makeSnapshot(items);
    syncClient.load.mockResolvedValueOnce(snapshot);
    syncClient.sync.mockResolvedValueOnce({
      previous: snapshot, snapshot, reset: source === 'reset', changedAddresses: items.map((item) => item.address),
    });
    jest.mocked(getChainConfig).mockReturnValue({ ...getChainConfig('ton'), nftBatchLimit });
    const airFlag = jest.replaceProperty(jest.requireMock('../../../config'), 'IS_AIR_APP', isAirApp);
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);

    try {
      if (source === 'restore') await sync.restore();
      else expect(await sync.poll()).toBe(true);
    } finally {
      airFlag.restore();
    }

    const updates = onUpdate.mock.calls.map(([update]) => update);
    expect(updates).toHaveLength(4);
    const nfts: ApiNft[] = updates.slice(0, 3).flatMap((update) => update.nfts);
    expect(nfts.map((nft) => nft.address)).toEqual(items.map((item) => toBase64Address(item.address, true, 'mainnet')));
    expect(updates).toEqual([
      { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: nfts.slice(0, 500), isFullLoading: true },
      { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: nfts.slice(500, 1000), isFullLoading: true },
      { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: nfts.slice(1000), isFullLoading: true },
      {
        type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: isAirApp ? [] : nfts, isFullLoading: false,
        streamedAddresses: nfts.map((nft) => nft.address),
      },
    ]);
  });

  it('emits an empty loading batch before completing an empty snapshot', async () => {
    syncClient.load.mockResolvedValueOnce(makeSnapshot([]));
    const onUpdate = jest.fn();

    await createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate).restore();

    expect(onUpdate.mock.calls.map(([update]) => update)).toEqual([
      { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: [], isFullLoading: true },
      {
        type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: [], isFullLoading: false, streamedAddresses: [],
      },
    ]);
  });

  it.each([
    ['a poll is aborted after its cache write', true],
    ['another runtime has already published its delta', false],
  ] as const)('restores fresh snapshot fields in stale Classic state after %s', async (_scenario, shouldAbort) => {
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]);
    const key = `${ACCOUNT_ID}:ton`;
    const cache = new Map<IDBValidKey, NftSyncSnapshot>([[key, snapshot]]);
    jest.mocked(idb.get).mockImplementation((name) => Promise.resolve(cache.get(name)));
    const runtimeStorage = {
      getItem: jest.fn().mockResolvedValue({ [ACCOUNT_ID]: { byChain: { ton: { address: WALLET_ADDRESS } } } }),
      setItem: jest.fn(), removeItem: jest.fn(), clear: jest.fn(),
    };
    jest.mocked(getCurrentStorage).mockReturnValue(runtimeStorage);
    jest.mocked(createNftSync).mockImplementation(jest.requireActual('../../common/nftSync').createNftSync);
    let global = {
      accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'view', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: {} },
      settings: { byAccountId: { [ACCOUNT_ID]: {} } },
    } as unknown as GlobalState;
    jest.mocked(setGlobal).mockImplementation((next) => {
      global = next;
      jest.mocked(getGlobal).mockReturnValue(next);
    });
    const actions = { checkCardNftOwnership: jest.fn() };
    const onUpdate = jest.fn((update: ApiUpdate) => apiUpdateHandler(global, actions, update));
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);
    await sync.restore();
    const staleGlobal = global;
    const positions = [...global.byAccountId[ACCOUNT_ID].nfts!.orderedAddresses!];
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![positions[0]].isOnSale).toBe(false);
    onUpdate.mockClear();
    const controller = new AbortController();
    jest.mocked(idb.set).mockImplementation((name, value) => {
      cache.set(name, value);
      if (shouldAbort) controller.abort();
      return Promise.resolve();
    });
    const metadata = makeMetadata([RAW_NFT_ADDRESS]);
    metadata[RAW_NFT_ADDRESS].token_info[0].name = 'Fresh metadata';
    jest.mocked(callBackendGet).mockResolvedValueOnce({
      status: 200,
      json: () => Promise.resolve({
        syncToken: 'committed-token', reset: false, hasMore: false,
        items: [makeItem(RAW_NFT_ADDRESS, { on_sale: true })], removed: [], metadata,
      }),
    } as Response);

    expect(await sync.poll(controller.signal)).toBe(!shouldAbort);
    if (shouldAbort) expect(onUpdate).not.toHaveBeenCalled();
    else expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({ type: 'nftChanged' }));
    expect(cache.get(key)?.syncToken).toBe('committed-token');
    global = staleGlobal;
    jest.mocked(getGlobal).mockReturnValue(global);
    jest.mocked(getCurrentStorage).mockReturnValue({ ...runtimeStorage });
    mockedParseNftItem.mockClear();
    onUpdate.mockClear();
    const otherRuntime = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);

    await otherRuntime.restore();
    jest.mocked(callBackendGet).mockResolvedValueOnce({
      status: 200,
      json: () => Promise.resolve({
        syncToken: 'committed-token', reset: false, hasMore: false, items: [], removed: [], metadata: {},
      }),
    } as Response);
    expect(await otherRuntime.poll()).toBe(true);

    expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual(['updateNfts', 'updateNfts']);
    expect(mockedParseNftItem).toHaveBeenCalledTimes(2);
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![positions[0]]).toMatchObject({
      isOnSale: true, name: 'Fresh metadata',
    });
    expect(global.byAccountId[ACCOUNT_ID].nfts!.orderedAddresses).toEqual(positions);
  });

  it.each([false, true])('silently delivers a hidden Telegram gift (existing=%s)', async (existing) => {
    const previous = makeSnapshot(existing ? [makeItem(RAW_NFT_ADDRESS)] : []);
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS)]);
    (snapshot.metadata as MetadataMap)[RAW_NFT_ADDRESS].token_info = [{ type: 'nft_items', is_scam: true }];
    jest.mocked(getNftSuperCollectionsByCollectionAddress).mockResolvedValue({
      [toBase64Address(RAW_COLLECTION_ADDRESS, true, 'mainnet')]: {
        id: TELEGRAM_GIFTS_SUPER_COLLECTION, name: 'Telegram Gifts',
      },
    });
    syncClient.sync.mockResolvedValueOnce({ previous, snapshot, reset: false, changedAddresses: [RAW_NFT_ADDRESS] });
    const onUpdate = jest.fn();
    expect(await createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate).poll()).toBe(true);
    expect(onUpdate).toHaveBeenCalledTimes(1);
    const hiddenGift = expect.objectContaining({ isHidden: true, isTelegramGift: true });
    expect(onUpdate).toHaveBeenCalledWith(existing ? {
      type: 'nftChanged', accountId: ACCOUNT_ID, chain: 'ton', nft: hiddenGift,
    } : {
      type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: [hiddenGift],
    });
    let global = {
      accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'view', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: { nfts: {
        byAddress: {}, orderedAddresses: [], inventoryStatusByChain: { ton: 'complete' },
        isFullLoadCompleteByChain: { ton: true },
      } } },
      settings: { byAccountId: { [ACCOUNT_ID]: {} } },
    } as unknown as GlobalState;
    jest.mocked(setGlobal).mockImplementation((next) => {
      global = next;
      jest.mocked(getGlobal).mockReturnValue(next);
    });
    const actions = { checkCardNftOwnership: jest.fn(), addCollectionTab: jest.fn() };
    apiUpdateHandler(global, actions, onUpdate.mock.calls[0][0]);
    const state = global.byAccountId[ACCOUNT_ID].nfts!;
    const catalog = buildTelegramGiftCatalog(Object.values(state.byAddress!), new Set());
    expect(catalog).toMatchObject({ count: 1, hiddenCount: 1 });
    expect(state.inventoryStatusByChain?.ton).toBe('complete');
    expect(state.isFullLoadCompleteByChain?.ton).toBe(true);
  });

  it('emits received, sent and changed NFTs while suppressing a hidden incoming NFT', async () => {
    const previous = makeSnapshot([makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)]);
    const snapshot = makeSnapshot([
      makeItem(RAW_NFT_ADDRESS, { on_sale: true }),
      makeItem(RAW_NFT_ADDRESS_3),
      makeItem(RAW_NFT_ADDRESS_4),
    ]);
    const metadata = makeMetadata([RAW_NFT_ADDRESS, RAW_NFT_ADDRESS_3, RAW_NFT_ADDRESS_4]);
    metadata[RAW_NFT_ADDRESS].token_info[0].name = 'Updated NFT';
    metadata[RAW_NFT_ADDRESS_4].token_info = [{ type: 'nft_items', is_scam: true }];
    snapshot.metadata = metadata;
    syncClient.sync.mockResolvedValueOnce({
      previous, snapshot, reset: false,
      changedAddresses: [RAW_NFT_ADDRESS, RAW_NFT_ADDRESS_2, RAW_NFT_ADDRESS_3, RAW_NFT_ADDRESS_4],
    });
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);

    expect(await sync.poll()).toBe(true);

    expect(onUpdate).toHaveBeenCalledTimes(3);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'nftChanged', accountId: ACCOUNT_ID, chain: 'ton',
      nft: expect.objectContaining({ name: 'Updated NFT', isOnSale: true }),
    }));
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'nftSent', accountId: ACCOUNT_ID, chain: 'ton',
    }));
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'nftReceived', accountId: ACCOUNT_ID, nft: expect.objectContaining({ isOnSale: false }),
    }));
  });

  it('parses only the changed NFT and its previous version for a one-item delta', async () => {
    const previous = makeSnapshot([
      makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2), makeItem(RAW_NFT_ADDRESS_3),
    ]);
    const snapshot = {
      ...previous,
      syncToken: 'next-token',
      items: { ...previous.items, [RAW_NFT_ADDRESS_2]: makeItem(RAW_NFT_ADDRESS_2, { on_sale: true }) },
    };
    syncClient.sync.mockResolvedValueOnce({
      previous, snapshot, reset: false, changedAddresses: [RAW_NFT_ADDRESS_2],
    });
    const onUpdate = jest.fn();
    expect(await createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate).poll()).toBe(true);

    expect(mockedParseNftItem).toHaveBeenCalledTimes(2);
    expect(mockedParseNftItem.mock.calls.map(([, item]) => item.address)).toEqual([
      RAW_NFT_ADDRESS_2, RAW_NFT_ADDRESS_2,
    ]);
    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'nftChanged', nft: expect.objectContaining({ isOnSale: true }),
    }));
  });

  it.each([100, 101])('applies a delta of %s addresses with bounded UI updates', async (count) => {
    const items = Array.from({ length: count }, (_, index) => makeItem(
      `0:${(index + 1).toString(16).padStart(64, '0')}`,
    ));
    const unchangedItem = makeItem(RAW_NFT_ADDRESS);
    const previous = makeSnapshot([...items, unchangedItem]);
    const snapshot = makeSnapshot([...items.map((item) => ({ ...item, on_sale: true })), unchangedItem]);
    syncClient.sync.mockResolvedValueOnce({
      previous, snapshot, reset: false, changedAddresses: items.map((item) => item.address),
    });
    const onUpdate = jest.fn();

    expect(await createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate).poll()).toBe(true);

    if (count === 100) {
      expect(onUpdate).toHaveBeenCalledTimes(100);
      expect(onUpdate.mock.calls.every(([update]) => update.type === 'nftChanged')).toBe(true);
      expect(mockedParseNftItem).toHaveBeenCalledTimes(200);
    } else {
      expect(onUpdate).toHaveBeenCalledTimes(2);
      expect(mockedParseNftItem).toHaveBeenCalledTimes(102);
      const nfts = onUpdate.mock.calls[0][0].nfts as ApiNft[];
      expect(nfts).toHaveLength(102);
      expect(nfts.at(-1)).toMatchObject({ isOnSale: false });
      expect(onUpdate.mock.calls.map(([update]) => update)).toEqual([
        { type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts, isFullLoading: true },
        {
          type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts, isFullLoading: false,
          streamedAddresses: nfts.map((nft) => nft.address),
        },
      ]);
    }
  });

  it('applies each upsert after another NFT has advanced their shared collection metadata', async () => {
    const items = [makeItem(RAW_NFT_ADDRESS), makeItem(RAW_NFT_ADDRESS_2)];
    const metadata = {
      ...makeMetadata(items.map((item) => item.address)),
      [RAW_COLLECTION_ADDRESS]: {
        is_indexed: true,
        token_info: [{ type: 'nft_collections' as const, is_scam: false }],
      },
    };
    const previous = makeSnapshot(items, metadata);
    const first = makeSnapshot(items, {
      ...metadata,
      [RAW_COLLECTION_ADDRESS]: {
        is_indexed: true,
        token_info: [{ type: 'nft_collections', is_scam: true }],
      },
    });
    const second = { ...first, syncToken: 'next-token' };
    syncClient.load.mockResolvedValueOnce(previous);
    syncClient.sync
      .mockResolvedValueOnce({ previous, snapshot: first, reset: false, changedAddresses: [RAW_NFT_ADDRESS] })
      .mockResolvedValueOnce({
        previous: first, snapshot: second, reset: false, changedAddresses: [RAW_NFT_ADDRESS_2],
      });
    let global = {
      accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'mnemonic', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: {} },
      settings: { byAccountId: { [ACCOUNT_ID]: {} } },
    } as unknown as GlobalState;
    jest.mocked(setGlobal).mockImplementation((next) => {
      global = next;
      jest.mocked(getGlobal).mockReturnValue(next);
    });
    const actions = { checkCardNftOwnership: jest.fn() };
    const onUpdate = jest.fn((update: ApiUpdate) => apiUpdateHandler(global, actions, update));
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);
    await sync.restore();
    const [firstAddress, secondAddress] = global.byAccountId[ACCOUNT_ID].nfts!.orderedAddresses!;
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![secondAddress].isScam).toBe(false);
    onUpdate.mockClear();

    await sync.poll();
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![firstAddress].isScam).toBe(true);
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![secondAddress].isScam).toBe(false);

    await sync.poll();
    expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual(['nftChanged', 'nftChanged']);
    expect(global.byAccountId[ACCOUNT_ID].nfts!.byAddress![secondAddress].isScam).toBe(true);
  });

  it.each([true, false])('refreshes reset fields with a saved SDK snapshot: %s', async (hasSnapshot) => {
    const previous = hasSnapshot ? makeSnapshot([makeItem(RAW_NFT_ADDRESS)]) : undefined;
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS, { on_sale: true })]);
    syncClient.load.mockResolvedValueOnce(previous);
    syncClient.sync.mockResolvedValueOnce({ previous, snapshot, reset: true, changedAddresses: [RAW_NFT_ADDRESS] });
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);
    await sync.restore();
    onUpdate.mockClear();
    mockedParseNftItem.mockClear();

    expect(await sync.poll()).toBe(true);

    expect(mockedParseNftItem).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'updateNfts', isFullLoading: true, nfts: [expect.objectContaining({ isOnSale: true })],
    }));
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'updateNfts', isFullLoading: false, streamedAddresses: [expect.any(String)],
    }));
    expect(onUpdate).toHaveBeenCalledTimes(2);
    expect(onUpdate).toHaveBeenLastCalledWith(expect.objectContaining({
      type: 'updateNfts', nfts: [expect.objectContaining({ isOnSale: true })],
    }));
  });

  it('applies a 5000-item reset in Classic with batched UI updates', async () => {
    const items = Array.from({ length: 5000 }, (_, index) => makeItem(
      `0:${index.toString(16).padStart(64, '0')}`, { index: String(index), on_sale: true },
    ));
    const oldNfts: ApiNft[] = items.map((item, index) => ({
      chain: 'ton', interface: 'default', index,
      address: toBase64Address(item.address, true, 'mainnet'),
      isOnSale: false, name: 'Stale metadata', metadata: {},
    }));
    const positions = oldNfts.map((nft) => nft.address).reverse();
    let global = {
      accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'view', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: { nfts: {
        byAddress: Object.fromEntries(oldNfts.map((nft) => [nft.address, nft])), orderedAddresses: positions,
      } } },
      settings: { byAccountId: { [ACCOUNT_ID]: {} } },
    } as unknown as GlobalState;
    jest.mocked(setGlobal).mockImplementation((next) => {
      global = next;
      jest.mocked(getGlobal).mockReturnValue(next);
    });
    const actions = { checkCardNftOwnership: jest.fn() };
    const onUpdate = jest.fn((update: ApiUpdate) => apiUpdateHandler(global, actions, update));
    syncClient.sync.mockResolvedValueOnce({
      previous: undefined, snapshot: makeSnapshot(items), reset: true,
      changedAddresses: items.map((item) => item.address),
    });

    expect(await createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate).poll()).toBe(true);

    expect(onUpdate).toHaveBeenCalledTimes(11);
    expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual(Array(11).fill('updateNfts'));
    expect(onUpdate.mock.calls.slice(0, 10).map(([update]) => (
      update.type === 'updateNfts' ? update.nfts.length : undefined
    ))).toEqual(Array(10).fill(500));
    expect(jest.mocked(setGlobal).mock.calls.length).toBeLessThanOrEqual(12);
    expect(Object.values(global.byAccountId[ACCOUNT_ID].nfts!.byAddress!)).toHaveLength(5000);
    expect(Object.values(global.byAccountId[ACCOUNT_ID].nfts!.byAddress!).every((nft) => nft.isOnSale)).toBe(true);
    expect(global.byAccountId[ACCOUNT_ID].nfts!.orderedAddresses).toEqual(positions);
  });

  it('leaves the restored UI intact when the protocol selects the direct fallback', async () => {
    syncClient.load.mockResolvedValueOnce(makeSnapshot([makeItem(RAW_NFT_ADDRESS)]));
    const onUpdate = jest.fn();
    const sync = createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, onUpdate);
    await sync.restore();

    expect(await sync.poll()).toBe(false);
    expect(onUpdate).toHaveBeenCalledTimes(2);
  });

  it('accepts third-party metadata of any shape and rejects items of another owner', () => {
    createTonNftSync(ACCOUNT_ID, WALLET_ADDRESS, jest.fn());
    const validate = jest.mocked(createNftSync).mock.calls.at(-1)![4]!;
    const snapshot = makeSnapshot([makeItem(RAW_NFT_ADDRESS)], {
      [RAW_NFT_ADDRESS]: {
        is_indexed: true,
        // eslint-disable-next-line no-null/no-null
        token_info: [{ type: 'nft_items', name: 'Spam', extra: { lottie: null, render_type: false, uri: {} } }],
      },
    } as unknown as MetadataMap);

    expect(() => validate(snapshot)).not.toThrow();
    expect(() => validate(snapshot, [RAW_NFT_ADDRESS])).not.toThrow();
    expect(parseNftItem('mainnet', snapshot.items[RAW_NFT_ADDRESS], snapshot.metadata as MetadataMap, {}))
      .toEqual(expect.objectContaining({ address: toBase64Address(RAW_NFT_ADDRESS, true, 'mainnet'), name: 'Spam' }));

    const foreign = makeSnapshot([
      makeItem(RAW_NFT_ADDRESS, { owner_address: RAW_STRANGER_ADDRESS, real_owner: RAW_STRANGER_ADDRESS }),
    ]);
    expect(() => validate(foreign)).toThrow('NFT sync item belongs to another owner');
  });
});
