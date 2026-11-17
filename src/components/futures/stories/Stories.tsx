import React, {
  memo, useEffect, useRef, useState,
} from '../../../lib/teact/teact';
import { withGlobal } from '../../../global';

import type { ApiPerpsOnboardingStory } from '../../../api/types';

import { APP_NAME } from '../../../config';
import buildClassName from '../../../util/buildClassName';
import captureEscKeyListener from '../../../util/captureEscKeyListener';
import { captureEvents, SwipeDirection } from '../../../util/captureEvents';
import captureKeyboardListeners from '../../../util/captureKeyboardListeners';
import trapFocus from '../../../util/trapFocus';

import useBackgroundMode from '../../../hooks/useBackgroundMode';
import useFlag from '../../../hooks/useFlag';
import useHistoryBack from '../../../hooks/useHistoryBack';
import useIsMotionDisabled from '../../../hooks/useIsMotionDisabled';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useLongPress from '../../../hooks/useLongPress';
import useTimeout from '../../../hooks/useTimeout';
import useUniqueId from '../../../hooks/useUniqueId';

import Portal from '../../ui/Portal';
import ShowTransition from '../../ui/ShowTransition';
import Transition from '../../ui/Transition';

import styles from './Stories.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  stories?: ApiPerpsOnboardingStory[];
  animationLevel: number;
}

const PAGES = [
  { id: 'intro', titleKey: 'PerpsStoryIntroTitle', bodyKey: 'PerpsStoryIntroBody' },
  { id: 'long', titleKey: 'PerpsStoryLongTitle', bodyKey: 'PerpsStoryLongBody' },
  { id: 'short', titleKey: 'PerpsStoryShortTitle', bodyKey: 'PerpsStoryShortBody' },
  { id: 'leverage', titleKey: 'PerpsStoryLeverageTitle', bodyKey: 'PerpsStoryLeverageBody' },
  { id: 'liquidation', titleKey: 'PerpsStoryLiquidationTitle', bodyKey: 'PerpsStoryLiquidationBody' },
  { id: 'funding', titleKey: 'PerpsStoryFundingTitle', bodyKey: 'PerpsStoryFundingBody' },
  { id: 'finale', titleKey: 'PerpsStoryFinaleTitle', bodyKey: 'PerpsStoryFinaleBody' },
];
const FINALE_INDEX = PAGES.length - 1;
// A page without a clip stays as long as on iOS
const DEFAULT_DURATION_S = 10;
// The progress waits for the clip this long at most, and then runs without it
const MEDIA_WAIT_LIMIT_MS = 2000;
const HOLD_THRESHOLD_MS = 200;

function Stories({
  isOpen, stories, animationLevel, onClose,
}: OwnProps & StateProps) {
  const lang = useLang();
  const cardRef = useRef<HTMLDivElement>();
  const titleIdPrefix = useUniqueId('perps-story-title-');

  const [index, setIndex] = useState(0);
  // Grows with every shown page, so going back on the first page plays it again
  const [pageKey, setPageKey] = useState(0);
  const [isBuffering, setIsBuffering] = useState(false);
  const [isHeld, hold, release] = useFlag();
  const [isInBackground, markInBackground, markInForeground] = useFlag();
  const isMotionDisabled = useIsMotionDisabled(animationLevel);

  const page = PAGES[index];
  const story = findStory(stories, index);
  const isPaused = isHeld || isInBackground || isBuffering;
  // The page that fades out keeps its title, so every shown page gets its own id
  const pageTitleId = `${titleIdPrefix}${pageKey}`;

  const showPage = useLastCallback((nextIndex: number) => {
    if (nextIndex > FINALE_INDEX) {
      onClose();
      return;
    }

    const shownIndex = Math.max(0, nextIndex);
    setIndex(shownIndex);
    setPageKey((key) => key + 1);
    setIsBuffering(Boolean(findStory(stories, shownIndex)) && !isMotionDisabled);
  });

  const showNext = useLastCallback(() => showPage(index + 1));
  const showPrevious = useLastCallback(() => showPage(index - 1));
  const stopBuffering = useLastCallback(() => setIsBuffering(false));
  const startBuffering = useLastCallback(() => setIsBuffering(true));

  // Every opening starts from the first page, and the pauses of the previous viewing are over
  useEffect(() => {
    if (!isOpen) return;

    release();
    markInForeground();
    showPage(0);
  }, [isOpen, markInForeground, release, showPage]);

  useTimeout(stopBuffering, isBuffering ? MEDIA_WAIT_LIMIT_MS : undefined, [pageKey]);
  useBackgroundMode(markInBackground, markInForeground, !isOpen);
  useHistoryBack({ isActive: isOpen, onBack: onClose });

  useEffect(() => (isOpen ? captureEscKeyListener(onClose) : undefined), [isOpen, onClose]);

  // The arrows point at a side of the screen, so in a right-to-left language the left one goes forward
  useEffect(() => (isOpen ? captureKeyboardListeners({
    onLeft: lang.isRtl ? showNext : showPrevious,
    onRight: lang.isRtl ? showPrevious : showNext,
  }) : undefined), [isOpen, lang.isRtl, showNext, showPrevious]);

  const handleSwipe = useLastCallback((e: Event, direction: SwipeDirection) => {
    if (direction === SwipeDirection.Down) {
      onClose();
      return true;
    }
    if (direction === SwipeDirection.Up) return false;

    const isForward = (direction === SwipeDirection.Left) !== lang.isRtl;
    showPage(isForward ? index + 1 : index - 1);
    return true;
  });

  useEffect(() => {
    if (!isOpen || !cardRef.current) return undefined;

    return captureEvents(cardRef.current, { excludedClosestSelector: 'button', onSwipe: handleSwipe });
  }, [isOpen, handleSwipe]);

  // A screen reader announces the dialog once it takes the focus
  useEffect(() => {
    if (!isOpen) return undefined;

    const card = cardRef.current!;
    card.focus();

    return trapFocus(card);
  }, [isOpen]);

  const handleTap = useLastCallback((e: React.MouseEvent) => {
    const { left, width } = e.currentTarget.getBoundingClientRect();
    const isLeftHalf = e.clientX < left + width / 2;

    const isBackward = isLeftHalf !== lang.isRtl;
    showPage(isBackward ? index - 1 : index + 1);
  });

  const longPressHandlers = useLongPress({
    onStart: hold,
    onEnd: release,
    onClick: handleTap,
    threshold: HOLD_THRESHOLD_MS,
  });

  const handleBackdropClick = useLastCallback((e: React.MouseEvent) => {
    if (e.target === e.currentTarget) onClose();
  });

  function renderProgress() {
    const duration = story?.duration ?? DEFAULT_DURATION_S;

    return (
      <div className={styles.progress}>
        {PAGES.map(({ id }, barIndex) => (
          <span key={id} className={styles.progressBar}>
            {barIndex < index && <span className={styles.progressFill} />}
            {barIndex === index && (
              <span
                key={pageKey}
                className={buildClassName(styles.progressFill, styles.progressFillActive, isPaused && styles.paused)}
                style={`--progress-duration: ${duration}s`}
                onAnimationEnd={showNext}
              />
            )}
          </span>
        ))}
      </div>
    );
  }

  function renderPage() {
    return (
      <div className={styles.page}>
        {story && (
          <StoryVideo
            story={story}
            isPlaying={!isHeld && !isInBackground}
            isMotionDisabled={isMotionDisabled}
            onReady={stopBuffering}
            onWaiting={startBuffering}
          />
        )}
        <div className={styles.content}>
          <div className={styles.copy}>
            <h2 id={pageTitleId} className={styles.title}>{lang(page.titleKey)}</h2>
            <p className={styles.body}>{lang(page.bodyKey, { app_name: APP_NAME })}</p>
          </div>
          {index === FINALE_INDEX && (
            <button type="button" className={styles.button} onClick={onClose}>
              {lang('PerpsStoryViewMarkets')}
            </button>
          )}
        </div>
      </div>
    );
  }

  return (
    <Portal>
      <ShowTransition
        className={buildClassName(styles.root, 'opacity-transition')}
        isOpen={isOpen}
        onClick={handleBackdropClick}
      >
        <div
          ref={cardRef}
          className={styles.card}
          tabIndex={-1}
          role="dialog"
          aria-modal="true"
          aria-labelledby={pageTitleId}
        >
          <div className={styles.tapArea} {...longPressHandlers} />
          <Transition activeKey={pageKey} name="semiFade" className={styles.pages}>
            {renderPage()}
          </Transition>
          {renderProgress()}
          <button type="button" className={styles.close} aria-label={lang('Close')} onClick={onClose}>
            <i className="icon-close" aria-hidden />
          </button>
        </div>
      </ShowTransition>
    </Portal>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => ({
  stories: global.perps.market?.onboarding?.stories,
  animationLevel: global.settings.animationLevel,
}))(Stories));

// Each page gets its own player, so the page that fades out keeps its clip while the next one starts
const StoryVideo = memo(({
  story, isPlaying, isMotionDisabled, onReady, onWaiting,
}: {
  story: ApiPerpsOnboardingStory;
  isPlaying: boolean;
  isMotionDisabled: boolean;
  /** The clip shows frames, or it never will, so the progress need not wait for it */
  onReady: NoneToVoidFunction;
  onWaiting: NoneToVoidFunction;
}) => {
  const ref = useRef<HTMLVideoElement>();
  const shouldPlay = isPlaying && !isMotionDisabled;

  useEffect(() => {
    const video = ref.current!;

    if (shouldPlay) {
      video.play().catch(onReady);
    } else {
      video.pause();
    }
  }, [shouldPlay, onReady]);

  // Without motion the clip shows its last frame, where the picture is complete
  const handleLoadedMetadata = useLastCallback(() => {
    const video = ref.current!;
    if (isMotionDisabled) video.currentTime = video.duration;
  });

  return (
    <video
      ref={ref}
      className={styles.video}
      src={story.url}
      poster={story.preview}
      preload="auto"
      muted
      playsInline
      disablePictureInPicture
      onLoadedMetadata={handleLoadedMetadata}
      onPlaying={onReady}
      onWaiting={onWaiting}
      onError={onReady}
    />
  );
});

function findStory(stories: ApiPerpsOnboardingStory[] | undefined, index: number) {
  return stories?.find(({ id }) => id === PAGES[index].id);
}
