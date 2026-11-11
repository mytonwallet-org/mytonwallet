import React, { memo, useRef } from '../../lib/teact/teact';

import type { AgentNewsFeedDigestV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import { formatTime } from '../../util/dateFormat';
import { toNativeDigits } from '../../util/nativeDigits';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentNewsDiscussStrip from './AgentNewsDiscussStrip';

import bubbleStyles from '../agent/MessageBubble.module.scss';
import styles from './AgentNews.module.scss';

interface OwnProps {
  digest: AgentNewsFeedDigestV2;
  /** The digest's place among the feed's messages */
  messageId: number;
  /** The digest came after the feed was shown, and fades in as a chat's new message does */
  isJustAdded?: boolean;
  onOpenNewsDiscussion: (eventId: number) => void;
  onOpenDigestDiscussion: (id: string) => void;
}

/**
 * A daily digest in the feed, in the bubble the news cards have, as on mobile: its title, how many news it covers and
 * when it came, its top headlines, each opening its news item's discussion, the news it leaves out, and the "Discuss"
 * strip, which opens the digest's own discussion
 */
function AgentNewsDigestCard({
  digest, messageId, isJustAdded = false, onOpenNewsDiscussion, onOpenDigestDiscussion,
}: OwnProps) {
  const lang = useLang();
  const shouldAnimateAppearance = useRef(isJustAdded).current;
  const {
    id, deliveredAt, total, top,
  } = digest;
  const title = lang('$agent_digest_title');
  const discussionLabel = lang('$agent_news_discuss');
  const remainder = total - top.length;

  const handleDiscussionClick = useLastCallback(() => {
    onOpenDigestDiscussion(id);
  });

  return (
    <div
      className={buildClassName(bubbleStyles.message, bubbleStyles.messageIncoming)}
      data-agent-v2-message-id={String(messageId)}
      data-agent-v2-message-role="assistant"
    >
      <div className={styles.cardColumn}>
        <div
          className={buildClassName(
            bubbleStyles.bubble,
            bubbleStyles.incoming,
            styles.news,
            shouldAnimateAppearance && bubbleStyles.appearing,
          )}
          data-agent-news-digest-id={id}
        >
          <div className={styles.digestHeader}>
            <h3 className={styles.newsHeadline}>{title}</h3>
            <div className={styles.digestMeta}>
              {lang(
                '$agent_digest_meta',
                { count: toNativeDigits(String(total)), time: formatTime(deliveredAt) },
                undefined,
                total,
              )}
            </div>
          </div>
          <div className={styles.digestHeadlines} role="list">
            {top.map(({ eventId, headline }) => (
              <div key={eventId} className={styles.digestHeadlineItem} role="listitem">
                <button
                  type="button"
                  className={styles.digestHeadline}
                  data-agent-news-digest-headline={eventId}
                  onClick={() => onOpenNewsDiscussion(eventId)}
                >
                  <span className={styles.digestBullet} aria-hidden />
                  <span className={styles.digestHeadlineText}>{headline}</span>
                  <svg className={styles.digestHeadlineChevron} viewBox="0 0 24 24" aria-hidden>
                    <path d="M9.5 6.5L15 12l-5.5 5.5" />
                  </svg>
                </button>
              </div>
            ))}
          </div>
          {remainder > 0 && (
            <div className={styles.digestRemainder}>
              {lang('$agent_digest_more', { count: toNativeDigits(String(remainder)) }, undefined, remainder)}
            </div>
          )}
          <AgentNewsDiscussStrip
            label={discussionLabel}
            ariaLabel={`${discussionLabel}, ${title}`}
            onClick={handleDiscussionClick}
          />
        </div>
      </div>
    </div>
  );
}

export default memo(AgentNewsDigestCard);
