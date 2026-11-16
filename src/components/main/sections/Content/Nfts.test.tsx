// Register the action handlers the tests dispatch
import '../../../../global/actions/apiUpdates/initial';
import '../../../../global/actions/ui/nfts';

import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../../../global';

import type { ApiNft } from '../../../../api/types';

import { MAIN_ACCOUNT_ID, TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../../config';
import { requestMutation } from '../../../../lib/fasterdom/fasterdom';
import { INITIAL_STATE } from '../../../../global/initialState';
import { handleError } from '../../../../util/handleError';
import { cloneDeep } from '../../../../util/iteratees';
import { pause } from '../../../../util/schedulers';

import NftCollectionHeader from './NftCollectionHeader';
import Nfts from './Nfts';

jest.mock('../../../../util/handleError', () => ({ handleError: jest.fn() }));

const COLLECTION = { address: 'EQCollectionAddress', chain: 'ton' } as const;
const PROXIED_IMAGE_URL = 'https://imgproxy.toncenter.com/signature/pr:medium/encoded';

const NFT_WITHOUT_IMAGE: ApiNft = {
  chain: 'ton',
  interface: 'default',
  index: 0,
  name: 'Unpreviewed NFT',
  address: 'EQNftWithoutImage',
  collectionAddress: COLLECTION.address,
  isOnSale: false,
  metadata: {},
};

function makeGift(index: number, collectionAddress = 'collection-a', collectionName = 'A'): ApiNft {
  return {
    ...NFT_WITHOUT_IMAGE,
    address: `gift-${index}`,
    index,
    collectionAddress,
    collectionName,
    name: `Gift #${index}`,
    isTelegramGift: true,
  };
}

// The `updateNfts` handler triggers this API-layer action; the tests don't need its effects
addActionHandler('checkCardNftOwnership', () => {});
// Network loading is supplied by emitNfts; collection navigation still renders the real components.
addActionHandler('fetchNftsFromCollection', () => {});

// TeactN flushes container updates on a microtask, Teact re-renders on rAF;
// a generous macrotask pause covers both
const flushUpdates = () => pause(50);

let root: HTMLDivElement;

beforeEach(() => {
  jest.mocked(handleError).mockClear();
  root = document.createElement('div');
  // The widget always lives inside an `OverviewCell` body, and `InfiniteScroll` looks the scroll
  // host up by this class
  root.className = 'overview-cell-body nfts-container app-slide-content';
  document.body.appendChild(root);

  let global = cloneDeep(INITIAL_STATE);
  global = {
    ...global,
    currentAccountId: MAIN_ACCOUNT_ID,
    accounts: {
      byId: {
        [MAIN_ACCOUNT_ID]: {
          title: 'Test Account',
          type: 'mnemonic' as const,
          byChain: { ton: { address: 'UQTestAddress' } },
        },
      },
    },
    byAccountId: { [MAIN_ACCOUNT_ID]: {} },
  };
  setGlobal(global);
});

afterEach(() => {
  TeactDOM.render(undefined, root);
  root.remove();
  expect(handleError).not.toHaveBeenCalled();
});

function renderWidget() {
  TeactDOM.render(<Nfts isActive isWidget />, root);
}

function getIsSpinnerShown() {
  return Boolean(root.querySelector('.icon-spinner'));
}

function getIsEmptyStateShown() {
  return Boolean(root.textContent?.includes('No collectibles yet'));
}

function emitTerminalNftUpdate() {
  getActions().apiUpdate({
    type: 'updateNfts',
    accountId: MAIN_ACCOUNT_ID,
    chain: 'ton',
    nfts: [],
    isFullLoading: false,
  });
}

function emitNfts(nfts: ApiNft[]) {
  getActions().apiUpdate({
    type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts, isFullLoading: true,
  });
  getActions().apiUpdate({
    type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts: [], isFullLoading: false,
    streamedAddresses: nfts.map((nft) => nft.address), inventoryStatus: 'complete',
  });
}

function getRenderedImageUrls() {
  return Array.from(root.querySelectorAll('img')).map((image) => image.getAttribute('src'));
}

describe('Telegram gift catalog', () => {
  function renderCatalog() {
    TeactDOM.render(<Nfts isActive collection={{ chain: 'ton', address: TELEGRAM_GIFTS_SUPER_COLLECTION }} />, root);
  }

  it.each(['cached', 'error'] as const)('does not present %s inventory as an exact total', async (inventoryStatus) => {
    const collection = { chain: 'ton', address: TELEGRAM_GIFTS_SUPER_COLLECTION } as const;
    TeactDOM.render(
      <><NftCollectionHeader collection={collection} /><Nfts isActive collection={collection} /></>,
      root,
    );
    const gifts = [makeGift(1), makeGift(2)];
    getActions().apiUpdate({
      type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts: gifts, isFullLoading: true,
    });
    getActions().apiUpdate({
      type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts: gifts, isFullLoading: false,
      streamedAddresses: inventoryStatus === 'cached' ? gifts.map((nft) => nft.address) : undefined,
      inventoryStatus,
    });
    await flushUpdates();
    expect(root.textContent).not.toContain('Total: 2');
    expect(root.textContent).not.toContain('2 NFTs');
    expect(root.textContent).toContain(inventoryStatus === 'cached' ? 'Saved gifts' : 'Could not update gifts');
    expect(root.querySelector('section button')?.textContent).toBe('A…');
    emitNfts(gifts);
    await flushUpdates();
    expect(root.textContent).toContain('Total: 2');
    expect(root.textContent).toContain('2 NFTs');
  });

  it('shows a failed empty request without claiming zero or leaving a spinner', async () => {
    renderCatalog();
    getActions().apiUpdate({
      type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts: [], inventoryStatus: 'error',
    });
    await flushUpdates();
    expect(root.textContent).toContain('Could not update gifts');
    expect(root.textContent).not.toContain('Total: 0');
    expect(getIsSpinnerShown()).toBe(false);
    emitNfts([]);
    await flushUpdates();
    expect(root.textContent).toContain('Total: 0');
  });

  it('waits for completion before showing exact totals and orders collections by count', async () => {
    renderCatalog();
    const gifts = Array.from({ length: 1001 }, (_, index) => makeGift(index, 'large', 'Z'));
    gifts.push(makeGift(1001, 'small', 'A'));
    getActions().apiUpdate({
      type: 'updateNfts', accountId: MAIN_ACCOUNT_ID, chain: 'ton', nfts: gifts, isFullLoading: true,
    });
    await flushUpdates();
    expect(root.textContent).toContain('Loading');
    expect(root.textContent).not.toContain('1,002');

    emitNfts(gifts);
    await flushUpdates();
    expect(root.textContent).toContain((1002).toLocaleString());
    const buttons = Array.from(root.querySelectorAll('section button'));
    expect(buttons.map((button) => button.textContent)).toEqual([`Z${(1001).toLocaleString()}`, 'A1']);
    (buttons[0] as HTMLButtonElement).click();
    await flushUpdates();
    expect(getGlobal().byAccountId[MAIN_ACCOUNT_ID].nfts?.currentCollection).toEqual({
      address: 'large', chain: 'ton',
    });
  });

  it('includes hidden gifts in total while preserving hidden collection privacy', async () => {
    renderCatalog();
    emitNfts([makeGift(1), { ...makeGift(2, 'hidden', 'Hidden collection name'), isHidden: true }]);
    await flushUpdates();
    expect(root.textContent).toContain('Total: 2');
    expect(root.textContent).toContain('Hidden NFTs: 1');
    expect(root.textContent).not.toContain('Hidden collection name');
    expect(root.querySelectorAll('section button')).toHaveLength(1);
  });

  it.each(['1-mainnet', '1-testnet'])(
    'ignores a catalog row from the outgoing account after switching to %s until its account is current again',
    async (otherAccountId) => {
      renderCatalog();
      emitNfts([makeGift(1, 'only-in-account-a', 'Account A collection')]);
      await flushUpdates();
      const outgoingRow = root.querySelector('section button') as HTMLButtonElement;
      expect(outgoingRow.textContent).toBe('Account A collection1');

      const beforeSwitch = getGlobal();
      setGlobal({
        ...beforeSwitch,
        currentAccountId: otherAccountId,
        accounts: { byId: {
          ...beforeSwitch.accounts!.byId,
          [otherAccountId]: {
            title: 'Other account', type: 'view', byChain: { ton: { address: 'UQOtherAddress' } },
          },
        } },
        byAccountId: { ...beforeSwitch.byAccountId, [otherAccountId]: {} },
      });
      await flushUpdates();
      // Outgoing slides can remain mounted while the account transition finishes.
      outgoingRow.click();
      await flushUpdates();
      expect(getGlobal().byAccountId[otherAccountId].nfts?.currentCollection).toBeUndefined();
      expect(getGlobal().byAccountId[MAIN_ACCOUNT_ID].nfts?.currentCollection).toBeUndefined();

      setGlobal({ ...getGlobal(), currentAccountId: MAIN_ACCOUNT_ID });
      await flushUpdates();
      (root.querySelector('section button') as HTMLButtonElement).click();
      await flushUpdates();
      expect(getGlobal().byAccountId[MAIN_ACCOUNT_ID].nfts?.currentCollection).toEqual({
        chain: 'ton', address: 'only-in-account-a',
      });
    },
  );

  it('shows the full collection count and hidden subtotal without changing visibility', async () => {
    renderCatalog();
    emitNfts([
      { ...makeGift(2, 'large', 'Private label'), isHidden: true },
      makeGift(1, 'large', 'Z'),
      { ...makeGift(3, 'large', 'Private label'), isHidden: true },
      makeGift(4, 'small', 'A'), makeGift(5, 'small', 'A'),
      { ...makeGift(6, 'hidden', 'Private collection'), isHidden: true },
    ]);
    await flushUpdates();
    expect(root.textContent).toContain('Total: 6');
    expect(root.textContent).toContain('Hidden NFTs: 3');
    const buttons = Array.from(root.querySelectorAll('section button'));
    expect(buttons.map((button) => button.textContent)).toEqual(['ZHidden NFTs: 23', 'A2']);
    expect(root.textContent).not.toContain('Private');
    (buttons[0] as HTMLButtonElement).click();
    await flushUpdates();
    const collection = { chain: 'ton', address: 'large' } as const;
    // Mount in the DOM mutation phase, as the app does when opening a collection.
    requestMutation(() => TeactDOM.render(
      <><NftCollectionHeader collection={collection} /><Nfts isActive collection={collection} /></>, root,
    ));
    await flushUpdates();
    expect(root.textContent).toContain('Gift#1');
    expect(root.textContent).not.toContain('Gift#2');
    expect(root.textContent).not.toContain('Gift#3');
    expect(root.textContent).not.toContain('Private');
  });
});

describe('Nfts landscape widget', () => {
  it('renders NFT data arriving after mount when no collection is involved', async () => {
    renderWidget();
    await flushUpdates();
    expect(getIsSpinnerShown()).toBe(true);

    emitTerminalNftUpdate();
    await flushUpdates();

    expect(getIsEmptyStateShown()).toBe(true);
    expect(getIsSpinnerShown()).toBe(false);
  });

  it('keeps receiving NFT updates across a collection open/close cycle', async () => {
    renderWidget();
    await flushUpdates();

    getActions().openNftCollection(COLLECTION);
    await flushUpdates();

    emitTerminalNftUpdate();
    await flushUpdates();

    getActions().closeNftCollection();
    await flushUpdates();

    expect(getIsEmptyStateShown()).toBe(true);
    expect(getIsSpinnerShown()).toBe(false);
  });

  it('renders NFT data when mounted while a collection is open elsewhere', async () => {
    // The widget can mount while the full-screen collection view is on top of it
    // (e.g. the Collectibles cell gets unhidden at that moment); the global
    // `currentCollection` must not detach the widget from future global updates
    getActions().openNftCollection(COLLECTION);
    await flushUpdates();

    renderWidget();
    await flushUpdates();
    expect(getIsSpinnerShown()).toBe(true);

    getActions().closeNftCollection();
    await flushUpdates();

    emitTerminalNftUpdate();
    await flushUpdates();

    expect(getIsEmptyStateShown()).toBe(true);
    expect(getIsSpinnerShown()).toBe(false);
  });

  it('filters by the collection passed as a prop', async () => {
    TeactDOM.render(<Nfts isActive isWidget collection={COLLECTION} />, root);

    getActions().apiUpdate({
      type: 'updateNfts',
      accountId: MAIN_ACCOUNT_ID,
      chain: 'ton',
      nfts: [{
        chain: 'ton',
        index: 0,
        name: 'Foreign NFT',
        address: 'EQNftAddress',
        thumbnail: '',
        image: '',
        collectionAddress: 'EQOtherCollectionAddress',
        isOnSale: false,
        metadata: {},
        interface: 'default',
      }],
      isFullLoading: false,
    });
    await flushUpdates();

    // The account has NFTs, but none from the given collection
    expect(getIsEmptyStateShown()).toBe(true);
  });

  it('is not left on a spinner when NFTs finish loading', async () => {
    // Sanity for the whole account state after the scenarios above
    renderWidget();
    emitTerminalNftUpdate();
    await flushUpdates();

    const { nfts } = getGlobal().byAccountId[MAIN_ACCOUNT_ID];
    expect(nfts?.orderedAddresses).toEqual([]);
    expect(getIsSpinnerShown()).toBe(false);
  });
});

describe('Nfts without a proxied preview', () => {
  it('shows the placeholder instead of an empty image', async () => {
    renderWidget();
    emitNfts([NFT_WITHOUT_IMAGE]);
    await flushUpdates();

    expect(root.textContent).toContain('No Image');
    const imageUrls = getRenderedImageUrls();
    expect(imageUrls.length).toBeGreaterThan(0);
    expect(imageUrls.every(Boolean)).toBe(true);
  });

  it('shows the image once a proxied preview arrives', async () => {
    renderWidget();
    emitNfts([{ ...NFT_WITHOUT_IMAGE, thumbnail: PROXIED_IMAGE_URL, image: PROXIED_IMAGE_URL }]);
    await flushUpdates();

    expect(getRenderedImageUrls()).toContain(PROXIED_IMAGE_URL);
  });
});
