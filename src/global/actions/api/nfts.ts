import { DEFAULT_CHAIN } from '../../../config';
import { getChainConfig } from '../../../util/chain';
import { findDifference, omit } from '../../../util/iteratees';
import { callApi } from '../../../api';
import { addActionHandler, setGlobal } from '../../index';
import { updateAccountState, updateCurrentAccountState } from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectCurrentAccountState } from '../../selectors';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';

addActionHandler('fetchNftsFromCollection', (global, actions, { collection }) => {
  actions.clearNftCollectionLoading({ collection });
  void callApi('fetchNftsFromCollection', selectCurrentAccountId(global)!, collection);
});

addActionHandler('clearNftCollectionLoading', (global, actions, { collection }) => {
  const currentAccountId = selectCurrentAccountId(global)!;
  const accountState = selectAccountState(global, currentAccountId);
  global = updateAccountState(global, currentAccountId, {
    nfts: {
      ...accountState!.nfts,
      isLoadedByAddress: omit(accountState!.nfts?.isLoadedByAddress ?? {}, [collection.address]),
    },
  });
  setGlobal(global);
});

addActionHandler('burnNfts', (global, actions, { nfts }) => {
  actions.startTransfer({
    isPortrait: getIsPortrait(),
    nfts,
  });

  const chain = nfts?.[0].chain || DEFAULT_CHAIN;

  const NFT_BURN_PLACEHOLDER_ADDRESS = 'placeholder_address';

  actions.submitTransferInitial({
    tokenSlug: getChainConfig(chain).nativeToken.slug,
    amount: 0n,
    toAddress: NFT_BURN_PLACEHOLDER_ADDRESS, // Define real inside action
    nfts,
    isNftBurn: true,
  });
});

addActionHandler('addNftsToBlacklist', (global, actions, { addresses: nftAddresses }) => {
  // Force hide NFT - remove it from whitelist and add to blacklist
  let { blacklistedNftAddresses = [], whitelistedNftAddresses = [] } = selectCurrentAccountState(global) || {};
  blacklistedNftAddresses = findDifference(blacklistedNftAddresses, nftAddresses);
  whitelistedNftAddresses = findDifference(whitelistedNftAddresses, nftAddresses);

  return updateCurrentAccountState(global, {
    blacklistedNftAddresses: [...blacklistedNftAddresses, ...nftAddresses],
    whitelistedNftAddresses,
  });
});

addActionHandler('addNftsToWhitelist', (global, actions, { addresses: nftAddresses }) => {
  // Force show NFT - remove it from blacklist and add to whitelist
  let { blacklistedNftAddresses = [], whitelistedNftAddresses = [] } = selectCurrentAccountState(global) || {};
  blacklistedNftAddresses = findDifference(blacklistedNftAddresses, nftAddresses);
  whitelistedNftAddresses = findDifference(whitelistedNftAddresses, nftAddresses);

  return updateCurrentAccountState(global, {
    blacklistedNftAddresses,
    whitelistedNftAddresses: [...whitelistedNftAddresses, ...nftAddresses],
  });
});

addActionHandler('removeNftSpecialStatus', (global, actions, { address: nftAddress }) => {
  // Stop forcing to show/hide NFT if it was in whitelist/blacklist
  let { blacklistedNftAddresses = [], whitelistedNftAddresses = [] } = selectCurrentAccountState(global) || {};

  blacklistedNftAddresses = blacklistedNftAddresses.filter((address) => address !== nftAddress);
  whitelistedNftAddresses = whitelistedNftAddresses.filter((address) => address !== nftAddress);

  return updateCurrentAccountState(global, {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
  });
});

addActionHandler('openUnhideNftModal', (global, actions, { address, name }) => {
  return updateCurrentAccountState(global, {
    isUnhideNftModalOpen: true,
    selectedNftToUnhide: { address, name },
  });
});

addActionHandler('closeUnhideNftModal', (global) => {
  return updateCurrentAccountState(global, {
    isUnhideNftModalOpen: undefined,
    selectedNftToUnhide: undefined,
  });
});

addActionHandler('openHideNftModal', (global, actions, { addresses, isCollection }) => {
  return updateCurrentAccountState(global, {
    selectedNftsToHide: { addresses, isCollection },
  });
});

addActionHandler('closeHideNftModal', (global) => {
  return updateCurrentAccountState(global, {
    selectedNftsToHide: undefined,
  });
});

addActionHandler('openNftAttributesModal', (global, actions, { nft, withOwner }) => {
  return updateCurrentAccountState(global, {
    currentNftForAttributes: nft,
    shouldShowOwnerInNftAttributes: withOwner,
  });
});

addActionHandler('closeNftAttributesModal', (global) => {
  return updateCurrentAccountState(global, {
    currentNftForAttributes: undefined,
    shouldShowOwnerInNftAttributes: undefined,
  });
});
