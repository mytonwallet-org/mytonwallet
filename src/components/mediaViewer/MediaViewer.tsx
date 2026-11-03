import React, {
  beginHeavyAnimation,
  memo,
  useEffect,
  useMemo,
  useRef,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import { type HiddenNftsSection, MediaType, type MediaViewerPictureNews } from '../../global/types';

import { ANIMATION_END_DELAY } from '../../config';
import { getIsNftVisible } from '../../global/helpers/nfts';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { getAdjacentMediaId } from './helpers/getAdjacentMediaId';
import { animateClosing, animateOpening, ANIMATION_DURATION } from './helpers/ghostAnimation';

import useDerivedState from '../../hooks/useDerivedState';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious from '../../hooks/usePrevious';
import useToggleClass from '../../hooks/useToggleClass';
import useControlsSignal from './hooks/useControlsSignal';

import ShowTransition from '../ui/ShowTransition';
import Transition from '../ui/Transition';
import Actions from './Actions';
import MediaInfo from './MediaInfo';
import PictureActions from './PictureActions';
import PictureInfo from './PictureInfo';
import Slides from './Slides';

import styles from './MediaViewer.module.scss';

interface StateProps {
  mediaId?: string;
  txId?: string;
  hiddenNfts?: HiddenNftsSection;
  noGhostAnimation?: boolean;
  mediaIds: string[];
  mediaUrl?: string;
  /** The news of a News picture, which gets Telegram's header and caption */
  news?: MediaViewerPictureNews;
  mediaType: MediaType;
  mediaByIds?: Record<string, ApiNft>;
  blacklistedIds: string[];
  whitelistedIds: string[];
  areUnverifiedNftsHidden?: boolean;
  withAnimation: boolean;
}

function MediaViewer({
  mediaId, mediaIds, mediaType, mediaUrl, news, withAnimation, mediaByIds, blacklistedIds, whitelistedIds,
  areUnverifiedNftsHidden, txId, hiddenNfts, noGhostAnimation,
}: StateProps) {
  const { closeMediaViewer, openMediaViewer } = getActions();

  const isOpen = Boolean(mediaId);
  const lang = useLang();
  const rootRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const { getAreControlsVisible, setAreControlsVisible } = useControlsSignal();
  const areControlsVisible = useDerivedState(getAreControlsVisible);
  // A closing viewer keeps the header of the picture it showed while it fades
  const lastNewsRef = useRef(news);
  if (isOpen) lastNewsRef.current = news;
  const headerNews = lastNewsRef.current;
  const prevMediaId = usePrevious(mediaId);
  const prevTxId = usePrevious(txId);
  const prevHiddenNfts = usePrevious(hiddenNfts);
  const prevNoGhostAnimation = usePrevious(noGhostAnimation);
  const headerAnimation = withAnimation ? 'slideFade' : 'none';
  const shouldAnimateOpening = withAnimation && isOpen && !prevMediaId && !noGhostAnimation;
  const shouldAnimateClosing = withAnimation && !isOpen && !!prevMediaId && !prevNoGhostAnimation;

  const handleClose = useLastCallback(() => closeMediaViewer());

  const renderedMediaIds = useMemo(() => {
    // Pictures given to the viewer are all shown
    if (mediaType !== MediaType.Nft) return mediaIds;

    const blacklistedSet = new Set(blacklistedIds);
    const whitelistedSet = new Set(whitelistedIds);

    return mediaIds.filter((id) => {
      const media = mediaByIds?.[id];
      return media && getIsNftVisible(media, blacklistedSet, whitelistedSet, areUnverifiedNftsHidden);
    });
  }, [areUnverifiedNftsHidden, blacklistedIds, mediaByIds, mediaIds, mediaType, whitelistedIds]);
  const selectedMediaIndex = renderedMediaIds.indexOf(mediaId!);

  // `Slides` passes a direction with every call, but the media it starts from is unset until it shows one
  const getMediaId = useLastCallback((fromId?: string, direction?: number): string | undefined => (
    fromId !== undefined ? getAdjacentMediaId(renderedMediaIds, fromId, direction!) : undefined
  ));

  const selectMedia = useLastCallback((id: string) => {
    if (!isOpen) return;

    openMediaViewer({ mediaType, mediaId: id });
  });

  useToggleClass({ className: 'is-media-viewer-open', isActive: isOpen, element: document.body });

  // The viewer opens with its header and caption shown
  useEffect(() => {
    if (isOpen) setAreControlsVisible(true);
  }, [isOpen, setAreControlsVisible]);

  useEffect(() => (isOpen ? captureEscKeyListener(handleClose) : undefined), [handleClose, isOpen]);

  useEffect(() => {
    if (shouldAnimateOpening) {
      beginHeavyAnimation(ANIMATION_DURATION + ANIMATION_END_DELAY);
      animateOpening(mediaType, mediaId, mediaUrl, txId, hiddenNfts, Boolean(news));
    }
    if (shouldAnimateClosing) {
      beginHeavyAnimation(ANIMATION_DURATION + ANIMATION_END_DELAY);
      animateClosing(mediaType, prevMediaId, prevTxId, prevHiddenNfts);
    }
  }, [
    shouldAnimateOpening,
    shouldAnimateClosing,
    mediaId,
    mediaType,
    mediaUrl,
    prevMediaId,
    txId,
    prevTxId,
    hiddenNfts,
    prevHiddenNfts,
    news,
  ]);

  // Telegram's header over a photo: the close button first on a phone, then who the photo comes from and when, then its
  // actions, all of which a tap on a touch screen hides with the caption
  function renderPictureHeader(pictureNews: MediaViewerPictureNews) {
    return (
      <div
        className={buildClassName(styles.header, styles.header_picture, !areControlsVisible && styles.header_hidden)}
        dir={lang.isRtl ? 'rtl' : undefined}
      >
        {isPortrait && (
          <button
            type="button"
            aria-label={lang('Close')}
            className={buildClassName(styles.pictureButton, styles.pictureClose)}
            onClick={handleClose}
          >
            <i className={buildClassName('icon icon-close', styles.pictureButtonIcon)} aria-hidden />
          </button>
        )}
        <Transition activeKey={selectedMediaIndex} name={headerAnimation} className={styles.pictureInfoTransition}>
          <PictureInfo
            news={pictureNews}
            position={selectedMediaIndex + 1}
            count={renderedMediaIds.length}
            onClick={handleClose}
          />
        </Transition>
        <PictureActions news={pictureNews} isMobile={isPortrait} onClose={handleClose} />
      </div>
    );
  }

  return (
    <ShowTransition
      ref={rootRef}
      className={buildClassName(styles.root, headerNews && styles.root_picture, 'opacity-transition', 'slow')}
      isOpen={isOpen}
      shouldAnimateFirstRender
      isCustom
    >
      {headerNews ? renderPictureHeader(headerNews) : (
        <div className={styles.header} dir={lang.isRtl ? 'rtl' : undefined}>
          <Transition activeKey={selectedMediaIndex} name={headerAnimation} className={styles.headerTransition}>
            <MediaInfo mediaId={mediaId} />
          </Transition>
          <Actions mediaId={mediaId} onClose={handleClose} />
        </div>
      )}
      <Slides
        isOpen={isOpen}
        mediaId={mediaId}
        isPicture={Boolean(headerNews)}
        rootRef={rootRef}
        getMediaId={getMediaId}
        selectMedia={selectMedia}
        withAnimation={withAnimation}
        onClose={handleClose}
      />
    </ShowTransition>
  );
}

export default memo(withGlobal((global): StateProps => {
  const {
    mediaId, mediaType = MediaType.Nft, txId, hiddenNfts, noGhostAnimation, pictures,
  } = global.mediaViewer || {};
  const animationLevel = global.settings?.animationLevel;
  const accountState = selectCurrentAccountState(global);

  let mediaIds: string[] = MEMO_EMPTY_ARRAY;
  let mediaUrl: string | undefined;
  let news: MediaViewerPictureNews | undefined;
  let mediaByIds: Record<string, ApiNft> | undefined;
  let blacklistedIds: string[] = MEMO_EMPTY_ARRAY;
  let whitelistedIds: string[] = MEMO_EMPTY_ARRAY;

  if (mediaType === MediaType.Nft) {
    const { orderedAddresses, byAddress } = accountState?.nfts || {};
    const { blacklistedNftAddresses, whitelistedNftAddresses } = accountState || {};
    const nft = byAddress?.[mediaId!];
    mediaUrl = (!nft?.metadata?.lottie && nft?.image) || nft?.thumbnail;
    mediaIds = orderedAddresses || MEMO_EMPTY_ARRAY;
    mediaByIds = byAddress;
    if (blacklistedNftAddresses?.length) {
      blacklistedIds = blacklistedNftAddresses;
    }
    if (whitelistedNftAddresses?.length) {
      whitelistedIds = whitelistedNftAddresses;
    }
  } else if (pictures) {
    mediaIds = pictures.ids;
    const picture = mediaId ? pictures.byId[mediaId] : undefined;
    mediaUrl = picture?.url;
    news = picture?.news;
  }

  return {
    mediaId,
    txId,
    hiddenNfts,
    noGhostAnimation,
    mediaIds,
    mediaType,
    mediaUrl,
    news,
    mediaByIds,
    blacklistedIds,
    whitelistedIds,
    areUnverifiedNftsHidden: global.settings?.areUnverifiedNftsHidden,
    withAnimation: animationLevel > 0,
  };
})(MediaViewer));
