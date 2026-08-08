import type { ApiChain, ApiNft } from '../../api/types';

import { IS_MY_WALLET_BRAND, MW_CARDS_COLLECTION, TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../config';

export interface VisibleNftCollection {
  chain: ApiChain;
  address: string;
  name?: string;
  count: number;
}

export interface NftCollectionIndex {
  byKey: Map<string, VisibleNftCollection>;
  totalVisibleCount: number;
}

export function getCollectionKey(chain: ApiChain, address: string) {
  return `${chain}_${address}`;
}

export function pinMwCardsFirst(
  orderedAddresses: string[],
  byAddress: Record<string, ApiNft>,
): string[] {
  if (!IS_MY_WALLET_BRAND) return orderedAddresses;

  const cards: string[] = [];
  const rest: string[] = [];
  for (const address of orderedAddresses) {
    if (byAddress[address]?.collectionAddress === MW_CARDS_COLLECTION) {
      cards.push(address);
    } else {
      rest.push(address);
    }
  }
  return cards.length ? cards.concat(rest) : orderedAddresses;
}

/** The caller builds the sets, so this function creates nothing when it runs over a list */
export function getIsNftVisible(
  nft: ApiNft,
  blacklistedSet: ReadonlySet<string>,
  whitelistedSet: ReadonlySet<string>,
  areUnverifiedNftsHidden?: boolean,
) {
  if (blacklistedSet.has(nft.address)) return false;
  if (whitelistedSet.has(nft.address)) return true;

  return !nft.isHidden && !(areUnverifiedNftsHidden && nft.isUnverified);
}

export function buildNftCollectionIndex(
  nftsByAddress: Record<string, ApiNft> | undefined,
  blacklistedNftAddresses: string[] | undefined,
  whitelistedNftAddresses: string[] | undefined,
  areUnverifiedNftsHidden?: boolean,
): NftCollectionIndex {
  const byKey = new Map<string, VisibleNftCollection>();
  let totalVisibleCount = 0;

  if (!nftsByAddress) return { byKey, totalVisibleCount };

  const blacklistedSet = new Set(blacklistedNftAddresses);
  const whitelistedSet = new Set(whitelistedNftAddresses);
  let telegramGiftsCount = 0;

  for (const nft of Object.values(nftsByAddress)) {
    if (!getIsNftVisible(nft, blacklistedSet, whitelistedSet, areUnverifiedNftsHidden)) continue;

    totalVisibleCount += 1;

    if (nft.isTelegramGift) telegramGiftsCount += 1;

    if (!nft.collectionAddress) continue;

    const key = getCollectionKey(nft.chain, nft.collectionAddress);
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, {
        chain: nft.chain,
        address: nft.collectionAddress,
        name: nft.collectionName,
        count: 1,
      });
    } else {
      existing.count += 1;
      if (!existing.name && nft.collectionName) {
        existing.name = nft.collectionName;
      }
    }
  }

  if (telegramGiftsCount > 0) {
    byKey.set(getCollectionKey('ton', TELEGRAM_GIFTS_SUPER_COLLECTION), {
      chain: 'ton',
      address: TELEGRAM_GIFTS_SUPER_COLLECTION,
      count: telegramGiftsCount,
    });
  }

  return { byKey, totalVisibleCount };
}
