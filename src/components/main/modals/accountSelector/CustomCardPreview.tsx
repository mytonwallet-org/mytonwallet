import React, { memo } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';

import { getCardNftImageUrl } from '../../../../util/url';

import useFlag from '../../../../hooks/useFlag';

import styles from './CustomCardPreview.module.scss';

import cardDefaultImg from '../../../../assets/cards/card.jpg';
import cardSkeletonBlack from '../../../../assets/cards/card_skeleton_black.svg';
import cardSkeletonDark from '../../../../assets/cards/card_skeleton_dark.svg';
import cardSkeletonGold from '../../../../assets/cards/card_skeleton_gold.svg';
import cardSkeletonLight from '../../../../assets/cards/card_skeleton_light.svg';
import cardSkeletonSilver from '../../../../assets/cards/card_skeleton_silver.svg';

interface OwnProps {
  nft?: ApiNft;
  className?: string;
}

function CustomCardPreview({ nft, className }: OwnProps) {
  const imageUrl = nft ? getCardNftImageUrl(nft) : cardDefaultImg;
  const skeletonUrl = getSkeletonUrl(nft);

  const [isImageLoaded, markImageLoaded] = useFlag(false);

  function handleImageLoad() {
    markImageLoaded();
  }

  return (
    <div className={className}>
      <div className={styles.container}>
        <img
          src={imageUrl}
          alt=""
          className={styles.image}
          onLoad={handleImageLoad}
        />
        {skeletonUrl && isImageLoaded && (
          <img
            src={skeletonUrl}
            alt=""
            className={styles.skeleton}
          />
        )}
      </div>
    </div>
  );
}

export default memo(CustomCardPreview);

function getSkeletonUrl(nft?: ApiNft): string | undefined {
  if (!nft) return cardSkeletonLight;
  const { mtwCardType, mtwCardTextType } = nft.metadata;

  if (!mtwCardType) return undefined;

  switch (mtwCardType) {
    case 'gold':
      return cardSkeletonGold;
    case 'silver':
      return cardSkeletonSilver;
    case 'black':
    case 'platinum':
      return cardSkeletonBlack;
    case 'standard':
      return mtwCardTextType === 'dark' ? cardSkeletonDark : cardSkeletonLight;
    default:
      return undefined;
  }
}
