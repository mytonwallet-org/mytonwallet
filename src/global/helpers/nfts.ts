import type { ApiChain, ApiNft } from '../../api/types';

import { TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../config';

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

export function buildNftCollectionIndex(
  nftsByAddress: Record<string, ApiNft> | undefined,
  blacklistedNftAddresses: string[] | undefined,
  whitelistedNftAddresses: string[] | undefined,
): NftCollectionIndex {
  const byKey = new Map<string, VisibleNftCollection>();
  let totalVisibleCount = 0;

  if (!nftsByAddress) return { byKey, totalVisibleCount };

  const blacklistedSet = new Set(blacklistedNftAddresses);
  const whitelistedSet = new Set(whitelistedNftAddresses);
  let telegramGiftsCount = 0;

  for (const nft of Object.values(nftsByAddress)) {
    const isVisible = (!nft.isHidden || whitelistedSet.has(nft.address))
      && !blacklistedSet.has(nft.address);
    if (!isVisible) continue;

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
