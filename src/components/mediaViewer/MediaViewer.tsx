import React, {
  beginHeavyAnimation,
  memo,
  useEffect,
  useMemo,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import { type HiddenNftsSection, MediaType } from '../../global/types';

import { ANIMATION_END_DELAY } from '../../config';
import { getIsNftVisible } from '../../global/helpers/nfts';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { animateClosing, animateOpening, ANIMATION_DURATION } from './helpers/ghostAnimation';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious from '../../hooks/usePrevious';
import useToggleClass from '../../hooks/useToggleClass';

import ShowTransition from '../ui/ShowTransition';
import Transition from '../ui/Transition';
import Actions from './Actions';
import MediaInfo from './MediaInfo';
import Slides from './Slides';

import styles from './MediaViewer.module.scss';

interface StateProps {
  mediaId?: string;
  txId?: string;
  hiddenNfts?: HiddenNftsSection;
  noGhostAnimation?: boolean;
  mediaIds: string[];
  mediaUrl?: string;
  mediaType: MediaType;
  mediaByIds?: Record<string, ApiNft>;
  blacklistedIds: string[];
  whitelistedIds: string[];
  areUnverifiedNftsHidden?: boolean;
  withAnimation: boolean;
}

function MediaViewer({
  mediaId, mediaIds, mediaType, mediaUrl, withAnimation, mediaByIds, blacklistedIds, whitelistedIds,
  areUnverifiedNftsHidden, txId, hiddenNfts, noGhostAnimation,
}: StateProps) {
  const { closeMediaViewer, openMediaViewer } = getActions();

  const isOpen = Boolean(mediaId);
  const lang = useLang();
  const prevMediaId = usePrevious(mediaId);
  const prevTxId = usePrevious(txId);
  const prevHiddenNfts = usePrevious(hiddenNfts);
  const prevNoGhostAnimation = usePrevious(noGhostAnimation);
  const headerAnimation = withAnimation ? 'slideFade' : 'none';
  const shouldAnimateOpening = withAnimation && isOpen && !prevMediaId && !noGhostAnimation;
  const shouldAnimateClosing = withAnimation && !isOpen && !!prevMediaId && !prevNoGhostAnimation;

  const handleClose = useLastCallback(() => closeMediaViewer());

  const renderedMediaIds = useMemo(() => {
    const blacklistedSet = new Set(blacklistedIds);
    const whitelistedSet = new Set(whitelistedIds);

    return mediaIds.filter((id) => {
      const media = mediaByIds?.[id];
      return media && getIsNftVisible(media, blacklistedSet, whitelistedSet, areUnverifiedNftsHidden);
    });
  }, [areUnverifiedNftsHidden, blacklistedIds, mediaByIds, mediaIds, whitelistedIds]);
  const selectedMediaIndex = renderedMediaIds.indexOf(mediaId!);

  const getMediaId = useLastCallback((fromId?: string, direction?: number): string | undefined => {
    if (fromId === undefined) return undefined;
    const index = renderedMediaIds.indexOf(fromId);
    if ((direction === -1 && index > 0) || (direction === 1 && index < renderedMediaIds.length - 1)) {
      return renderedMediaIds[index + direction];
    }
    return undefined;
  });

  const selectMedia = useLastCallback((id: string) => {
    openMediaViewer({ mediaType, mediaId: id });
  });

  useToggleClass({ className: 'is-media-viewer-open', isActive: isOpen, element: document.body });

  useEffect(() => (isOpen ? captureEscKeyListener(handleClose) : undefined), [handleClose, isOpen]);

  useEffect(() => {
    if (shouldAnimateOpening) {
      beginHeavyAnimation(ANIMATION_DURATION + ANIMATION_END_DELAY);
      animateOpening(mediaType, mediaId, mediaUrl, txId, hiddenNfts);
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
  ]);

  return (
    <ShowTransition
      className={buildClassName(styles.root, 'opacity-transition', 'slow')}
      isOpen={isOpen}
      shouldAnimateFirstRender
      isCustom
    >
      <div className={styles.header} dir={lang.isRtl ? 'rtl' : undefined}>
        <Transition activeKey={selectedMediaIndex} name={headerAnimation} className={styles.headerTransition}>
          <MediaInfo mediaId={mediaId} />
        </Transition>
        <Actions mediaId={mediaId} onClose={handleClose} />
      </div>
      <Slides
        isOpen={isOpen}
        mediaId={mediaId}
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
    mediaId, mediaType = MediaType.Nft, txId, hiddenNfts, noGhostAnimation,
  } = global.mediaViewer || {};
  const animationLevel = global.settings?.animationLevel;
  const accountState = selectCurrentAccountState(global);

  let mediaIds: string[] = MEMO_EMPTY_ARRAY;
  let mediaUrl: string | undefined;
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
  }

  return {
    mediaId,
    txId,
    hiddenNfts,
    noGhostAnimation,
    mediaIds,
    mediaType,
    mediaUrl,
    mediaByIds,
    blacklistedIds,
    whitelistedIds,
    areUnverifiedNftsHidden: global.settings?.areUnverifiedNftsHidden,
    withAnimation: animationLevel > 0,
  };
})(MediaViewer));
