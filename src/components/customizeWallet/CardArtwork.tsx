import React, { memo } from '../../lib/teact/teact';

import type { ApiNft } from '../../api/types';

import { IS_GRAM_WALLET } from '../../config';
import buildClassName from '../../util/buildClassName';
import { getDefaultCardImageUrl } from '../../util/card/defaultArtwork';

import { useCardArtworkUrl } from '../../hooks/useCardArtwork';
import useCardCustomization from '../../hooks/useCardCustomization';
import useFlag from '../../hooks/useFlag';
import useMediaTransition from '../../hooks/useMediaTransition';

import styles from './CardArtwork.module.scss';

interface OwnProps {
  nft?: ApiNft;
}

function CardArtwork({ nft }: OwnProps) {
  const nftImageUrl = useCardArtworkUrl(nft);
  const [isLoaded, markLoaded] = useFlag();
  const ref = useMediaTransition(isLoaded);
  const { classNames, borderShineType } = useCardCustomization(nft);
  const imageUrl = nft ? nftImageUrl : getDefaultCardImageUrl(IS_GRAM_WALLET);

  return (
    <div
      ref={ref}
      className={buildClassName(
        styles.root,
        nft && styles.bordered,
        classNames,
        borderShineType && styles[`borderShine_${borderShineType}`],
      )}
      aria-hidden
    >
      {imageUrl && <img src={imageUrl} alt="" className={styles.image} onLoad={markLoaded} />}
    </div>
  );
}

export default memo(CardArtwork);
