import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentMessagesSkeleton.module.scss';

/** What a chat is known to hold before its history loads, as its row in the chat list tells */
export interface AgentMessagesSkeletonLayout {
  messageCount: number;
  /** A news discussion, whose first message is the news post */
  isNews?: boolean;
}

interface OwnProps {
  isOpen: boolean;
  /** The news feed's cards in place of a chat's bubbles */
  isNewsFeed?: boolean;
  /** The chat's own rows, each on its sender's side, in place of the alternating bubbles */
  layout?: AgentMessagesSkeletonLayout;
  onClosed?: NoneToVoidFunction;
}

interface SkeletonRow {
  isOutgoing: boolean;
  isNewsCard?: boolean;
  style: string;
}

// Loaded messages grow out of the placeholders over this time. Placeholders left without a message fade out over the
// same time.
export const PLACEHOLDER_MORPH_DURATION = 360;
// Telegram's loading chat, from the composer up: the lowest bubble is the Agent's, then they alternate. The widths are
// shares of the chat's width and the heights are in rem. The Agent's answers run several paragraphs and the user's
// questions a line or two, so the Agent's bubbles are tall and wide and the user's short and narrow.
const BUBBLES: SkeletonRow[] = [
  [0.86, 15.5], [0.56, 3.5], [0.92, 13.5], [0.44, 2.5],
  [0.80, 16.5], [0.60, 3.5], [0.86, 14.5], [0.48, 2.5],
].map(([widthShare, height], index) => ({
  isOutgoing: index % 2 === 1,
  style: buildBubbleStyle(widthShare, height),
}));
const INCOMING_BUBBLES = BUBBLES.filter(({ isOutgoing }) => !isOutgoing);
const OUTGOING_BUBBLES = BUBBLES.filter(({ isOutgoing }) => isOutgoing);
// The news feed's cards from the bottom up, tall and short in turn, as on mobile
const NEWS_CARD_HEIGHTS = [23.75, 12.75, 23.75, 12.75];
// A news discussion's post, as tall as the feed's tall card
const NEWS_POST_ROW: SkeletonRow = { isOutgoing: false, isNewsCard: true, style: `height: ${NEWS_CARD_HEIGHTS[0]}rem` };

/**
 * The outlines of a chat's bubbles with a shimmer, shown until its history loads, as on mobile. A chat whose list row
 * tells what it holds shows its own rows: the user's on the user's side and a news discussion's post as a card.
 */
function AgentMessagesSkeleton({
  isOpen, isNewsFeed, layout, onClosed,
}: OwnProps) {
  const lang = useLang();
  // The outlines show at once, as on iOS
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
      )) : buildRows(layout).map(({ isOutgoing, isNewsCard, style }, index) => (
        <div
          key={index}
          data-agent-skeleton-role={isOutgoing ? 'user' : 'assistant'}
          className={buildClassName(
            styles.bubble, isOutgoing ? styles.outgoing : styles.incoming, isNewsCard && styles.newsCard,
          )}
          style={style}
        />
      ))}
    </div>
  );
}

// From the composer up: the chat's last messages, as many as fill the screen at most. A chat alternates from its
// first message: the user's question, or a news discussion's post followed by questions.
function buildRows(layout?: AgentMessagesSkeletonLayout) {
  if (!layout || layout.messageCount <= 0) return BUBBLES;

  const counts = { incoming: 0, outgoing: 0 };
  return Array.from({ length: Math.min(layout.messageCount, BUBBLES.length) }, (_, index): SkeletonRow => {
    const position = layout.messageCount - 1 - index;
    if (layout.isNews && position === 0) return NEWS_POST_ROW;
    const isOutgoing = layout.isNews ? position % 2 === 1 : position % 2 === 0;
    const bubbles = isOutgoing ? OUTGOING_BUBBLES : INCOMING_BUBBLES;
    const count = isOutgoing ? counts.outgoing++ : counts.incoming++;
    return bubbles[count % bubbles.length];
  });
}

function buildBubbleStyle(widthShare: number, height: number) {
  return `--skeleton-bubble-width-share: ${widthShare}; height: ${height}rem`;
}

export default memo(AgentMessagesSkeleton);
