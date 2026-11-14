import React, { memo, useRef } from '../../lib/teact/teact';

import type { AgentNewsFeedItemV2, AgentNewsFeedLocaleV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import { formatAgentTime } from '../agent/helpers/agentDateFormat';
import { getAgentNewsPictureId } from './agentNewsPictures';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentNewsBubble from './AgentNewsBubble';
import AgentNewsDiscussStrip from './AgentNewsDiscussStrip';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  item: AgentNewsFeedItemV2;
  /** The feed page's language, which the card's shared link names */
  locale?: AgentNewsFeedLocaleV2;
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
  item, locale, isJustAdded = false, isDiscussionContinued, onOpenDiscussion, onOpenPicture,
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

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-id={String(eventId)}
      data-agent-v2-message-role="assistant"
    >
      <div className={styles.cardColumn}>
        <AgentNewsBubble
          news={item}
          locale={locale}
          time={formatAgentTime(lang.code ?? 'en', deliveredAt)}
          timeDateTime={item.deliveredAt}
          menuTimestamp={deliveredAt}
          pictureId={getAgentNewsPictureId('feed', eventId)}
          isPictureLazy
          feedEventId={eventId}
          className={shouldAnimateAppearance ? bubbleStyles.appearing : undefined}
          footer={(
            <AgentNewsDiscussStrip
              label={discussionLabel}
              ariaLabel={isDiscussionContinued
                ? lang('$agent_news_continue_discussion_accessibility', { headline }) as string
                : `${discussionLabel}, ${headline}`}
              discussion={isDiscussionContinued ? discussion : undefined}
              onClick={handleDiscussionClick}
            />
          )}
          onOpenPicture={handleImageClick}
        />
      </div>
    </div>
  );
}

export default memo(AgentNewsCard);
