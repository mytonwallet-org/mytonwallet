import React, { memo, useRef } from '../../lib/teact/teact';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { formatTime } from '../../util/dateFormat';
import { getAvatarGradientColors } from '../ui/helpers/getAvatarGradientColor';
import { getAgentNewsPictureId } from './agentNewsPictures';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentMark from '../agent/AgentMark';
import AgentSearchGlyph from '../agent/AgentSearchGlyph';
import AgentNewsBubble from './AgentNewsBubble';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  item: AgentNewsFeedItemV2;
  /** The news came after the feed was shown, and fades in as a chat's new message does */
  isJustAdded?: boolean;
  /** The user has written in the news' discussion, which the card then offers to continue */
  isDiscussionContinued: boolean;
  onOpenDiscussion: (item: AgentNewsFeedItemV2, cardElement?: HTMLElement) => void;
  /** Opens the news picture in the media viewer */
  onOpenPicture: (eventId: number) => void;
}

const CARD_SELECTOR = '[data-agent-news-event-id]';

/**
 * A news item as the Agent's message in the feed's list, as the post of its discussion, with a "Discuss" strip at its
 * foot, as a channel post's comments, on mobile. The day line above it dates it, so its foot tells the time alone.
 */
function AgentNewsCard({
  item, isJustAdded = false, isDiscussionContinued, onOpenDiscussion, onOpenPicture,
}: OwnProps) {
  const lang = useLang();
  const shouldAnimateAppearance = useRef(isJustAdded).current;
  const { eventId, headline, discussion } = item;
  const deliveredAt = Date.parse(item.deliveredAt);
  const discussionLabel = lang(isDiscussionContinued ? '$agent_news_continue_discussion' : '$agent_news_discuss');

  const handleImageClick = useLastCallback(() => {
    onOpenPicture(eventId);
  });

  // The card flies into the discussion from where it is
  const handleDiscussionClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    onOpenDiscussion(item, e.currentTarget.closest<HTMLElement>(CARD_SELECTOR) ?? undefined);
  });

  // The strip is a button of its own: pressing it does not open the card's menu
  const handleDiscussionPointer = useLastCallback((e: React.MouseEvent) => {
    e.stopPropagation();
  });

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-id={String(eventId)}
      data-agent-v2-message-role="assistant"
    >
      <div className={styles.cardColumn}>
        <AgentNewsBubble
          news={item}
          time={formatTime(deliveredAt)}
          timeDateTime={item.deliveredAt}
          menuTimestamp={deliveredAt}
          pictureId={getAgentNewsPictureId('feed', eventId)}
          isPictureLazy
          isFeedCard
          className={shouldAnimateAppearance ? bubbleStyles.appearing : undefined}
          footer={(
            <button
              type="button"
              className={styles.cardDiscussion}
              data-agent-news-discuss
              aria-label={isDiscussionContinued
                ? lang('$agent_news_continue_discussion_accessibility', { headline }) as string
                : `${discussionLabel}, ${headline}`}
              onMouseDown={handleDiscussionPointer}
              onContextMenu={handleDiscussionPointer}
              onClick={handleDiscussionClick}
            >
              <span className={styles.cardDiscussionContent}>
                {renderDiscussionIcon(isDiscussionContinued ? discussion : undefined)}
                <span className={styles.cardDiscussionLabel}>{discussionLabel}</span>
                <svg className={styles.cardDiscussionChevron} viewBox="0 0 24 24" aria-hidden>
                  <path d="M9.5 6.5L15 12l-5.5 5.5" />
                </svg>
              </span>
            </button>
          )}
          onOpenPicture={handleImageClick}
        />
      </div>
    </div>
  );
}

export default memo(AgentNewsCard);

/** The Agent mark for a new discussion, or the avatar of the chat the discussion continues in */
function renderDiscussionIcon(discussion: AgentNewsFeedItemV2['discussion']) {
  if (!discussion) {
    return (
      <span className={styles.cardDiscussionIcon} aria-hidden>
        <AgentMark className={styles.cardDiscussionMark} />
      </span>
    );
  }

  const [startColor, endColor] = getAvatarGradientColors(discussion.threadId);
  return (
    <span
      className={buildClassName(styles.cardDiscussionIcon, styles.cardDiscussionAvatar)}
      style={buildStyle(`--start-color: ${startColor}; --end-color: ${endColor}`)}
      aria-hidden
    >
      {discussion.icon || <AgentSearchGlyph className={styles.cardDiscussionAvatarMark} />}
    </span>
  );
}
