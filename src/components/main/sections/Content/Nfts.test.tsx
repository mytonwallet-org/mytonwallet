// Register the action handlers the tests dispatch
import '../../../../global/actions/apiUpdates/initial';
import '../../../../global/actions/ui/nfts';

import React from '../../../../lib/teact/teact';
import TeactDOM from '../../../../lib/teact/teact-dom';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../../../global';

import { MAIN_ACCOUNT_ID } from '../../../../config';
import { INITIAL_STATE } from '../../../../global/initialState';
import { cloneDeep } from '../../../../util/iteratees';
import { pause } from '../../../../util/schedulers';

import Nfts from './Nfts';

const COLLECTION = { address: 'EQCollectionAddress', chain: 'ton' } as const;

// The `updateNfts` handler triggers this API-layer action; the tests don't need its effects
addActionHandler('checkCardNftOwnership', () => {});

// TeactN flushes container updates on a microtask, Teact re-renders on rAF;
// a generous macrotask pause covers both
const flushUpdates = () => pause(50);

let root: HTMLDivElement;

beforeEach(() => {
  root = document.createElement('div');
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
