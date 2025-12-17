import { TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../config';
import { addActionHandler, setGlobal } from '../../index';
import {
  addToSelectedAddresses,
  removeFromSelectedAddresses,
  updateAccountState,
  updateCurrentAccountState,
} from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectCurrentAccountState } from '../../selectors';

addActionHandler('openNftCollection', (global, actions, { address }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  global = updateAccountState(global, accountId, {
    nfts: {
      ...accountState!.nfts!,
      currentCollectionAddress: address,
    },
  });
  return global;
});

addActionHandler('closeNftCollection', (global) => {
  const accountState = selectCurrentAccountState(global);
  global = updateCurrentAccountState(global, {
    nfts: {
      ...accountState!.nfts!,
      currentCollectionAddress: undefined,
    },
    selectedNftsToHide: undefined,
  });
  return global;
});

addActionHandler('selectNfts', (global, actions, { addresses }) => {
  const accountId = selectCurrentAccountId(global)!;
  global = addToSelectedAddresses(global, accountId, addresses);
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
      selectedAddresses: nfts.map(({ address }) => address),
    },
  });
  setGlobal(global);
});

addActionHandler('clearNftSelection', (global, actions, { address }) => {
  const accountId = selectCurrentAccountId(global)!;
  global = removeFromSelectedAddresses(global, accountId, address);
  setGlobal(global);
});

addActionHandler('clearNftsSelection', (global) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  global = updateAccountState(global, accountId, {
    nfts: {
      ...accountState!.nfts!,
      selectedAddresses: [],
    },
  });
  setGlobal(global);
});

addActionHandler('addCollectionTab', (global, actions, { collectionAddress, isAuto }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  const currentNfts = accountState?.nfts || { byAddress: {} };

  if (isAuto && collectionAddress === TELEGRAM_GIFTS_SUPER_COLLECTION && currentNfts.wasTelegramGiftsAutoAdded) {
    return global;
  }

  const existingCollectionTabs = currentNfts.collectionTabs || [];

  if (!existingCollectionTabs.includes(collectionAddress)) {
    global = updateAccountState(global, accountId, {
      nfts: {
        ...currentNfts,
        collectionTabs: [...existingCollectionTabs, collectionAddress],
        ...(isAuto && collectionAddress === TELEGRAM_GIFTS_SUPER_COLLECTION && { wasTelegramGiftsAutoAdded: true }),
      },
    });
  }

  return global;
});

addActionHandler('removeCollectionTab', (global, actions, { collectionAddress }) => {
  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, accountId);
  const currentNfts = accountState?.nfts || { byAddress: {} };

  if (!currentNfts.collectionTabs) {
    return global;
  }

  global = updateAccountState(global, accountId, {
    nfts: {
      ...currentNfts,
      collectionTabs: currentNfts.collectionTabs.filter((address) => address !== collectionAddress),
    },
  });

  return global;
});
