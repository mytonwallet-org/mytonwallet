import type { ApiNft } from '../api/types';

import { MW_CARDS_COLLECTION } from '../config';
import { getAccentColorIndexFromNft } from './accentColor';
import { compact, unique } from './iteratees';
import { logDebugError } from './logs';

export default async function getAccentColorsFromNfts(
  nftAddresses?: string[],
  nftsByAddress?: Record<string, ApiNft>,
) {
  try {
    const nftCards = (nftAddresses || []).reduce((result, nftAddress) => {
      const nft = nftsByAddress?.[nftAddress];
      if (nft?.collectionAddress === MW_CARDS_COLLECTION) {
        result.push(nft);
      }
      return result;
    }, [] as ApiNft[]);

    if (!nftCards.length) {
      return undefined;
    }

    const colors = await Promise.all(nftCards.map((nft) => getAccentColorIndexFromNft(nft)));
    const nftsByColorIndex = colors.reduce((result, colorIndex, i) => {
      if (colorIndex !== undefined) {
        result[colorIndex] = nftCards[i];
      }
      return result;
    }, {} as Record<number, ApiNft>);

    const availableAccentColorIds = unique(compact(colors));

    return {
      availableAccentColorIds,
      nftsByColorIndex,
    };
  } catch (err: any) {
    logDebugError('[getAccentColorsFromNfts]: Error fetching accent colors', err);
    return undefined;
  }
}
