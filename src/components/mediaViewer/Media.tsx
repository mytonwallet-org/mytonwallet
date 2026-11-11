import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { MediaViewerPictureNews } from '../../global/types';
import { MediaType } from '../../global/types';

import { requestMutation } from '../../lib/fasterdom/fasterdom';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import PictureCaption from './PictureCaption';

import styles from './MediaViewer.module.scss';

import noImageSrcDark from '../../assets/nftNoImageDark.svg';
import scamImg from '../../assets/scam.svg';

interface OwnProps {

  mediaId: string;
  /** Whether this is the picture in view, rather than a neighbour waiting at the side */
  isActive?: boolean;
}

interface StateProps {
  alt?: string;
  thumbnail?: string;
  image?: string;
  lottie?: string;
  description?: string;
  isScam?: boolean;
  whitelistedMediaIds?: string[];
  isPicture?: boolean;
  news?: MediaViewerPictureNews;
}

const ANIMATED_ICON_SIZE = 250; // Preview size (500px) / 2

function Media({
  mediaId, isActive, alt, thumbnail, image, lottie, description, isScam, whitelistedMediaIds, isPicture, news,
}: OwnProps & StateProps) {
  const lang = useLang();
  const src = image || thumbnail;
  const ref = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  // A picture that fails to load shows the placeholder of a media without an image
  const [failedSrc, setFailedSrc] = useState<string>();

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const { height } = element.getBoundingClientRect();
    requestMutation(() => {
      // Inner scroll requires max-height to be set
      element.style.setProperty('--max-height', `${height}px`);
    });
  }, [isPortrait]);

  const isNftWhiteListed = useMemo(() => {
    return whitelistedMediaIds?.includes(mediaId);
  }, [mediaId, whitelistedMediaIds]);

  // A picture stands in the middle, as large as Telegram shows a photo, over its caption, as Telegram's
  if (isPicture) {
    return (
      <div className={buildClassName(styles.content, styles.content_picture)}>
        {src && src === failedSrc ? (
          <div className={buildClassName(styles.image, styles.imageNoData)}>
            <img src={noImageSrcDark} alt="" className={styles.noImageIcon} />
          </div>
        ) : src && (
          <img
            src={src}
            alt={alt}
            className={buildClassName(
              styles.image, styles.picture, news && !IS_TOUCH_ENV && styles.picture_withCaption,
            )}
            onError={() => setFailedSrc(src)}
          />
        )}
        {news && <PictureCaption key={mediaId} news={news} isActive={isActive} />}
      </div>
    );
  }

  return (
    <div className={styles.content}>
      {lottie ? (
        <AnimatedIconWithPreview
          // A remount per animation keeps the new preview up if TLottie rejects the animation
          key={lottie}
          size={ANIMATED_ICON_SIZE}
          shouldStretch
          play
          noLoop={false}
          tgsUrl={lottie}
          previewUrl={src}
          className={styles.image}
          noPreviewTransition
        />
      ) : src ? (
        <img src={src} alt={alt} className={styles.image} />
      ) : (
        <div className={buildClassName(styles.image, styles.imageNoData)}>
          <img src={noImageSrcDark} alt="" className={styles.noImageIcon} />
        </div>
      )}
      <div className={buildClassName(styles.contentDescription, 'custom-scroll')} ref={ref}>
        {description && (
          <div className={styles.contentTextWrapper}>
            <div className={buildClassName(styles.contentText, 'custom-scroll')} dir="auto">
              {isScam && !isNftWhiteListed && <img src={scamImg} alt={lang('Scam')} className={styles.scamImage} />}
              {description}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global, { mediaId }): StateProps => {
  const { mediaType = MediaType.Nft, pictures } = global.mediaViewer || {};

  if (mediaType !== MediaType.Nft) {
    const picture = pictures?.byId[mediaId];
    return picture ? {
      image: picture.url, alt: picture.title, isPicture: true, news: picture.news,
    } : { isPicture: true };
  }

  const { byAddress } = selectCurrentAccountState(global)?.nfts || {};
  const nft = byAddress?.[mediaId];
  if (!nft) return {};

  const { whitelistedNftAddresses } = selectCurrentAccountState(global) || {};

  return {
    alt: nft.name,
    thumbnail: nft.thumbnail,
    image: nft.image,
    lottie: nft.metadata?.lottie,
    description: nft.description,
    isScam: nft.isScam,
    whitelistedMediaIds: whitelistedNftAddresses,
  };
})(Media));
