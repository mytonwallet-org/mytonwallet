import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentMessagesSkeleton.module.scss';

interface OwnProps {
  isOpen: boolean;
  /** The news feed's cards in place of a chat's bubbles */
  isNewsFeed?: boolean;
  onClosed?: NoneToVoidFunction;
}

// Loaded messages grow out of the placeholders over this time. Placeholders left without a message fade out over the
// same time.
export const PLACEHOLDER_MORPH_DURATION = 360;
// Telegram's loading chat, from the composer up: the lowest bubble is the Agent's, then they alternate. The widths are
// shares of the chat's width and the heights are in rem.
const BUBBLES = [
  [0.86, 11.5], [0.70, 7.5], [0.92, 11.5], [0.64, 7.5],
  [0.80, 11.5], [0.72, 7.5], [0.86, 11.5], [0.64, 7.5],
].map(([widthShare, height], index) => ({
  isOutgoing: index % 2 === 1,
  style: `--skeleton-bubble-width-share: ${widthShare}; height: ${height}rem`,
}));
// The news feed's cards from the bottom up, tall and short in turn, as on mobile
const NEWS_CARD_HEIGHTS = [23.75, 12.75, 23.75, 12.75];

/** The outlines of a chat's bubbles with a shimmer, shown until its history loads, as on mobile */
function AgentMessagesSkeleton({ isOpen, isNewsFeed, onClosed }: OwnProps) {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition({
    isOpen,
    withShouldRender: true,
    noMountTransition: true,
    closeDuration: PLACEHOLDER_MORPH_DURATION,
    className: false,
    onCloseAnimationEnd: onClosed,
  });

  if (!shouldRender) return undefined;

  return (
    <div
      ref={ref}
      className={buildClassName(styles.root, isNewsFeed && styles.rootNewsFeed)}
      role="status"
      data-agent-skeleton
      aria-label={lang('Loading...')}
    >
      {isNewsFeed ? NEWS_CARD_HEIGHTS.map((height, index) => (
        <div
          key={index}
          data-agent-skeleton-role="assistant"
          className={buildClassName(styles.bubble, styles.incoming, styles.newsCard)}
          style={`height: ${height}rem`}
        />
      )) : BUBBLES.map(({ isOutgoing, style }, index) => (
        <div
          key={index}
          data-agent-skeleton-role={isOutgoing ? 'user' : 'assistant'}
          className={buildClassName(styles.bubble, isOutgoing ? styles.outgoing : styles.incoming)}
          style={style}
        />
      ))}
    </div>
  );
}

export default memo(AgentMessagesSkeleton);
