import React, { memo, useRef, useState } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';

import buildClassName from '../../../../util/buildClassName';
import { getCardNftImageUrl } from '../../../../util/url';

import { useCachedImage } from '../../../../hooks/useCachedImage';
import useCardCustomization from '../../../../hooks/useCardCustomization';
import useFlag from '../../../../hooks/useFlag';
import useMediaTransition from '../../../../hooks/useMediaTransition';

import CardBackgroundMotion from '../../../ui/CardBackgroundMotion';

import styles from './CustomCardBackground.module.scss';

interface OwnProps {
  isSticky?: boolean;
  /**
   * Animates the NFT image. Enable it only for the main wallet card or the selected card preview,
   * so cards in lists do not keep running animations.
   */
  withMotion?: boolean;
  nft: ApiNft;
  noShowAnimation?: boolean;
  shouldHide?: boolean;
  className?: string;
  shadowClassName?: string;
  onLoad?: (hasGradient: boolean, className?: string) => void;
  onTransitionEnd: NoneToVoidFunction;
}

function CustomCardBackground({
  isSticky,
  withMotion,
  nft,
  noShowAnimation,
  shouldHide,
  className,
  shadowClassName,
  onLoad,
  onTransitionEnd,
}: OwnProps) {
  const { imageUrl } = useCachedImage(nft ? getCardNftImageUrl(nft) : undefined);
  const imageRef = useRef<HTMLImageElement>();
  const [loadedImage, setLoadedImage] = useState<{ url: string; element: HTMLImageElement }>();
  const [isLoaded, markLoaded] = useFlag();
  // The card stays hidden until its artwork is decoded, so its border shine, background and the image's
  // alt text (Firefox draws it while loading) do not show up over the plain container.
  // The initial card skips only the fade
  const ref = useMediaTransition(isLoaded && !shouldHide, { noOpenTransition: noShowAnimation });

  const {
    borderShineType,
    withTextGradient,
    classNames: cardClassName,
  } = useCardCustomization(nft);

  function handleLoad() {
    setLoadedImage({ url: imageUrl!, element: imageRef.current! });
    markLoaded();

    onLoad?.(withTextGradient, cardClassName);
  }

  const rootClassName = buildClassName(
    styles.root,
    isSticky && styles.sticky,
    cardClassName,
    borderShineType && styles[`borderShine_${borderShineType}`],
    isLoaded && !shouldHide && styles.loaded,
    shouldHide && styles.hide,
  );

  return (
    <div ref={ref} className={buildClassName(rootClassName, className)} onTransitionEnd={onTransitionEnd}>
      {imageUrl && (
        <img
          key={imageUrl}
          ref={imageRef}
          src={imageUrl}
          alt={nft.name}
          className={styles.image}
          onLoad={handleLoad}
        />
      )}
      {imageUrl && loadedImage?.url === imageUrl && loadedImage.element === imageRef.current && (
        <CardBackgroundMotion
          imageRef={imageRef}
          imageUrl={imageUrl}
          motionKey={nft.address}
          isDisabled={!withMotion}
          className={styles.image}
        />
      )}
    </div>
  );
}

export default memo(CustomCardBackground);
