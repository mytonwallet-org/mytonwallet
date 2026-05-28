import type { ApiNft } from '../../api/types';
import type { GlobalState } from '../types';

import { MTW_CARDS_COLLECTION } from '../../config';
import isEmptyObject from '../../util/isEmptyObject';
import { pinMtwCardsFirst } from '../helpers/nfts';
import { selectAccountState } from '../selectors';
import { updateAccountSettings, updateAccountState } from './misc';

export function addNft(global: GlobalState, accountId: string, nft: ApiNft, shouldAppendToEnd?: boolean) {
  const nftAddress = nft.address;
  const nfts = selectAccountState(global, accountId)?.nfts;
  const orderedAddresses = (nfts?.orderedAddresses ?? []).filter((address) => address !== nftAddress);
  const byAddress = { ...nfts?.byAddress, [nftAddress]: nft };

  return updateAccountState(global, accountId, {
    nfts: {
      ...nfts,
      byAddress,
      orderedAddresses: pinMtwCardsFirst(
        shouldAppendToEnd
          ? orderedAddresses.concat(nftAddress)
          : [nftAddress, ...orderedAddresses],
        byAddress,
      ),
    },
  });
}

export function removeNft(global: GlobalState, accountId: string, nftAddress: string) {
  const nfts = selectAccountState(global, accountId)!.nfts;
  const orderedAddresses = (nfts?.orderedAddresses ?? []).filter((address) => address !== nftAddress);
  const selectedNfts = (nfts?.selectedNfts ?? []).filter((nft) => nft.address !== nftAddress);
  const { [nftAddress]: removedNft, ...byAddress } = nfts?.byAddress ?? {};

  return updateAccountState(global, accountId, {
    nfts: {
      ...nfts,
      byAddress,
      orderedAddresses,
      selectedNfts,
    },
  });
}

export function updateNft(global: GlobalState, accountId: string, nftAddress: string, partial: Partial<ApiNft>) {
  const nfts = selectAccountState(global, accountId)!.nfts;
  const nft = nfts?.byAddress?.[nftAddress];
  if (!nfts || !nft) return global;

  return updateAccountState(global, accountId, {
    nfts: {
      ...nfts,
      byAddress: {
        ...nfts.byAddress,
        [nftAddress]: { ...nft, ...partial },
      },
    },
  });
}

export function addToSelectedNfts(
  global: GlobalState,
  accountId: string,
  nftsToAdd: ApiNft[],
) {
  const accountNfts = selectAccountState(global, accountId)!.nfts;
  const selectedNfts = [...(accountNfts?.selectedNfts ?? []), ...nftsToAdd];

  return updateAccountState(global, accountId, {
    nfts: {
      ...accountNfts!,
      selectedNfts,
    },
  });
}

export function removeFromSelectedNfts(global: GlobalState, accountId: string, nftAddress: string) {
  const nfts = selectAccountState(global, accountId)!.nfts;
  const selectedNfts = (nfts?.selectedNfts ?? []).filter((nft) => nft.address !== nftAddress);

  return updateAccountState(global, accountId, {
    nfts: {
      ...nfts!,
      selectedNfts: selectedNfts.length ? selectedNfts : undefined,
    },
  });
}

export function updateAccountOwnedMtwCards(
  global: GlobalState,
  accountId: string,
  ownedMtwCardAddresses: string[],
): GlobalState {
  const accountState = selectAccountState(global, accountId);
  if (!accountState?.nfts) return global;

  return updateAccountState(global, accountId, {
    nfts: {
      ...accountState.nfts,
      ownedMtwCardAddresses,
    },
  });
}

// Mirrors the `nftReceived` socket update from the activities pipeline so a freshly received NFT
// (and the MTW-card ownership snapshot) is applied immediately, without waiting for NFT polling
export function applyIncomingNftFromActivity(
  global: GlobalState,
  accountId: string,
  nft: ApiNft,
): GlobalState {
  global = addNft(global, accountId, nft);

  if (nft.collectionAddress === MTW_CARDS_COLLECTION) {
    const owned = selectAccountState(global, accountId)?.nfts?.ownedMtwCardAddresses ?? [];
    if (!owned.includes(nft.address)) {
      global = updateAccountOwnedMtwCards(global, accountId, [...owned, nft.address]);
    }
  }

  return global;
}

// Mirrors the `nftSent` socket update; `newOwnerAddress` may be `unknown` when applied from an outgoing
// activity - `updateAccountSettingsBackgroundNft` only rewrites the persisted owner field
export function applyOutgoingNftFromActivity(
  global: GlobalState,
  accountId: string,
  nft: ApiNft,
  newOwnerAddress?: string,
): GlobalState {
  global = removeNft(global, accountId, nft.address);

  if (nft.collectionAddress === MTW_CARDS_COLLECTION) {
    // Sync owner snapshot in `settings.cardBackgroundNft`; final clear is done by `checkCardNftOwnership`
    const sentNft = { ...nft, ownerAddress: newOwnerAddress };
    global = updateAccountSettingsBackgroundNft(global, sentNft);

    const owned = selectAccountState(global, accountId)?.nfts?.ownedMtwCardAddresses;
    if (owned?.includes(nft.address)) {
      global = updateAccountOwnedMtwCards(global, accountId, owned.filter((a) => a !== nft.address));
    }
  }

  return global;
}

// Updates the account settings to ensure the specified NFT is up-to-date.
export function updateAccountSettingsBackgroundNft(global: GlobalState, nft: ApiNft) {
  Object.entries(global.settings.byAccountId).forEach(([accountId, settings]) => {
    if (settings.cardBackgroundNft?.address === nft.address) {
      global = updateAccountSettings(global, accountId, {
        ...settings,
        cardBackgroundNft: nft,
      });
    }
  });

  return global;
}

export function addUnorderedNfts(
  global: GlobalState,
  accountId: string,
  updatedNfts?: Record<string, ApiNft>,
): GlobalState {
  if (!updatedNfts || isEmptyObject(updatedNfts)) {
    return global;
  }

  const { byAddress } = selectAccountState(global, accountId)?.nfts || { byAddress: {} };

  Object.values(updatedNfts).forEach((nft) => {
    const existingNft = byAddress?.[nft.address];
    if (existingNft) {
      global = updateNft(global, accountId, nft.address, nft);
    } else {
      global = addNft(global, accountId, nft, true);
    }
  });

  return global;
}
