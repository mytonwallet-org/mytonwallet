import { TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../config';
import { addActionHandler, setGlobal } from '../../index';
import {
  addToSelectedNfts,
  removeFromSelectedNfts,
  updateAccountState,
  updateCurrentAccountState,
} from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectCurrentAccountState } from '../../selectors';

addActionHandler('openNftCollection', (global, actions, { address, chain }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  global = updateAccountState(global, accountId, {
    nfts: {
      ...accountState!.nfts!,
      currentCollection: {
        chain,
        address,
      },
    },
  });
  return global;
});

addActionHandler('closeNftCollection', (global) => {
  const accountState = selectCurrentAccountState(global);
  global = updateCurrentAccountState(global, {
    nfts: {
      ...accountState!.nfts!,
      currentCollection: undefined,
    },
    selectedNftsToHide: undefined,
  });
  return global;
});

addActionHandler('selectNfts', (global, actions, { nfts }) => {
  const accountId = selectCurrentAccountId(global)!;
  global = addToSelectedNfts(global, accountId, nfts);
  setGlobal(global);
});

addActionHandler('selectAllNfts', (global, actions, { collectionAddress }) => {
  const accountId = selectCurrentAccountId(global)!;
  const {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
  } = selectAccountState(global, accountId) || {};

  const whitelistedNftAddressesSet = new Set(whitelistedNftAddresses);
  const blacklistedNftAddressesSet = new Set(blacklistedNftAddresses);
  const { nfts: accountNfts } = selectAccountState(global, accountId)!;

  const nfts = Object.values(accountNfts!.byAddress!).filter((nft) => (
    !nft.isHidden || whitelistedNftAddressesSet.has(nft.address)
  ) && !blacklistedNftAddressesSet.has(nft.address) && (
    collectionAddress === undefined || (nft.collectionAddress === collectionAddress)
  ));

  global = updateAccountState(global, accountId, {
    nfts: {
      ...accountNfts!,
      selectedNfts: nfts,
    },
  });
  setGlobal(global);
});

addActionHandler('clearNftSelection', (global, actions, { address }) => {
  const accountId = selectCurrentAccountId(global)!;
  global = removeFromSelectedNfts(global, accountId, address);
  setGlobal(global);
});

addActionHandler('clearNftsSelection', (global) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  global = updateAccountState(global, accountId, {
    nfts: {
      ...accountState!.nfts!,
      selectedNfts: [],
    },
  });
  setGlobal(global);
});

addActionHandler('addCollectionTab', (global, actions, { collection, isAuto }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  const currentNfts = accountState?.nfts || { byAddress: {} };

  if (isAuto && collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION && currentNfts.wasTelegramGiftsAutoAdded) {
    return global;
  }

  const existingCollectionTabs = currentNfts.collectionTabs || [];

  if (!existingCollectionTabs.some((e) => e.address === collection.address)) {
    global = updateAccountState(global, accountId, {
      nfts: {
        ...currentNfts,
        collectionTabs: [...existingCollectionTabs, collection],
        ...(isAuto && collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION && { wasTelegramGiftsAutoAdded: true }),
      },
    });
  }

  return global;
});

addActionHandler('removeCollectionTab', (global, actions, { collection }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  const currentNfts = accountState?.nfts || { byAddress: {} };

  if (!currentNfts.collectionTabs) {
    return global;
  }

  global = updateAccountState(global, accountId, {
    nfts: {
      ...currentNfts,
      collectionTabs: currentNfts.collectionTabs.filter((tab) => tab.address !== collection.address),
    },
  });

  return global;
});
