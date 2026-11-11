import React, { memo } from '../../lib/teact/teact';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { formatAgentListTime } from '../agent/helpers/agentDateFormat';
import { formatAgentNewsUnreadCount } from './agentNewsFeedItems';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentNewsIcon from './AgentNewsIcon';
import AgentThreadThumbnail from './AgentThreadThumbnail';

import styles from './AgentThreadList.module.scss';

interface OwnProps {
  latestItem?: AgentNewsFeedItemV2;
  unreadCount: number;
  onClick: NoneToVoidFunction;
}

/** The permanent News row above the chats */
function AgentNewsRow({ latestItem, unreadCount, onClick }: OwnProps) {
  const lang = useLang();
  const title = lang('News');
  const hasUnread = unreadCount > 0;
  const unreadCountText = hasUnread ? formatAgentNewsUnreadCount(unreadCount) : undefined;
  const preview = latestItem?.headline ?? lang('Crypto Market News');
  const time = latestItem && formatAgentListTime(lang, latestItem.deliveredAt);

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    stopEvent(e);
    onClick();
  });

  return (
    <div className={buildClassName(styles.item, styles.newsItem)}>
      <div
        role="button"
        tabIndex={0}
        aria-label={[
          title,
          preview,
          time,
          hasUnread
            ? lang('$agent_news_unread_count', { count: unreadCount }, undefined, unreadCount) as string
            : undefined,
        ].filter(Boolean).join(', ')}
        className={styles.itemButton}
        data-agent-news-row
        onClick={onClick}
        onKeyDown={handleKeyDown}
      >
        <AgentNewsIcon className={styles.newsAvatar} />
        <div className={styles.itemText} aria-hidden>
          <div className={styles.itemTop}>
            <span className={styles.itemTitle}>{title}</span>
            {time && <span className={styles.itemTime}>{time}</span>}
          </div>
          <div className={styles.itemBottom}>
            <div className={styles.itemStatus}>
              <span className={styles.itemPreview}>
                {latestItem?.imageUrl && <AgentThreadThumbnail url={latestItem.imageUrl} />}
                {preview}
              </span>
            </div>
            {unreadCountText && <span className={styles.unreadCount}>{unreadCountText}</span>}
            {hasUnread && !unreadCountText && <span className={styles.unreadDot} />}
          </div>
        </div>
      </div>
    </div>
  );
}

export default memo(AgentNewsRow);
