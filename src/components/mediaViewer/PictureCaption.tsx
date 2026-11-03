import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { MediaViewerPictureNews } from '../../global/types';

import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';

import useDerivedState from '../../hooks/useDerivedState';
import useLastCallback from '../../hooks/useLastCallback';
import useWindowSize from '../../hooks/useWindowSize';
import useControlsSignal from './hooks/useControlsSignal';

import AgentNewsBody from '../agent/AgentNewsBody';

import styles from './MediaViewer.module.scss';

interface OwnProps {
  news: MediaViewerPictureNews;
  /** A neighbour's caption waits at the side, out of reach of the keyboard and screen readers */
  isActive?: boolean;
}

/**
 * The news under its picture, as Telegram's caption: its headline and text as its post shows them, cut to Telegram's
 * lines. A caption that is cut expands on a click, and scrolls when it is longer than the room it gets.
 */
function PictureCaption({ news, isActive }: OwnProps) {
  const ref = useRef<HTMLDivElement>();
  const [isExpanded, setIsExpanded] = useState(false);
  const [isClamped, setIsClamped] = useState(false);
  const { getAreControlsVisible, getIsZoomed } = useControlsSignal();
  const isHidden = useDerivedState(
    () => !getAreControlsVisible() || getIsZoomed(),
    [getAreControlsVisible, getIsZoomed],
  );
  const { width: windowWidth, height: windowHeight } = useWindowSize();
  const { headline, body } = news;

  useEffect(() => {
    if (isExpanded) return;

    requestMeasure(() => {
      const element = ref.current;
      if (element) setIsClamped(element.scrollHeight > element.clientHeight + 1);
    });
  }, [body, headline, isExpanded, windowHeight, windowWidth]);

  // A caption that expands is a button, which a hidden or neighbour's caption takes out of the Tab order
  let tabIndex: number | undefined;
  if (isClamped) tabIndex = isHidden || !isActive ? -1 : 0;

  const toggleExpanded = useLastCallback(() => {
    setIsExpanded(!isExpanded);
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    e.preventDefault();
    toggleExpanded();
  });

  return (
    <div
      className={buildClassName(
        styles.caption,
        IS_TOUCH_ENV && styles.caption_touch,
        isExpanded && styles.caption_expanded,
        isHidden && styles.caption_hidden,
      )}
      aria-hidden={!isActive || undefined}
    >
      <div
        ref={ref}
        className={buildClassName(
          styles.captionText,
          IS_TOUCH_ENV && styles.captionText_touch,
          isClamped && styles.captionText_clamped,
          isExpanded && styles.captionText_expanded,
          isHidden && styles.captionText_hidden,
          'custom-scroll',
        )}
        role={isClamped ? 'button' : undefined}
        tabIndex={tabIndex}
        aria-expanded={isClamped ? isExpanded : undefined}
        dir="auto"
        onClick={isClamped ? toggleExpanded : undefined}
        onKeyDown={isClamped ? handleKeyDown : undefined}
      >
        <strong className={styles.captionHeadline}>{headline}</strong>
        {body && '\n'}
        {body && <AgentNewsBody body={body} />}
      </div>
    </div>
  );
}

export default memo(PictureCaption);
