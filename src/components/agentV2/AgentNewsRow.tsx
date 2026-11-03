import React, { memo } from '../../lib/teact/teact';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { formatAgentNewsUnreadCount } from './agentNewsFeedItems';
import { formatAgentThreadTime } from './agentThreadListSections';

import useLang from '../../hooks/useLang';

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
  const hasUnread = unreadCount > 0;
  const preview = latestItem?.headline ?? lang('Crypto Market News');
  const time = latestItem && formatAgentThreadTime(lang, latestItem.deliveredAt);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    stopEvent(e);
    onClick();
  };

  return (
    <div className={buildClassName(styles.item, styles.newsItem)}>
      <div
        role="button"
        tabIndex={0}
        aria-label={[
          lang('News'),
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
            <span className={styles.itemTitle}>{lang('News')}</span>
            {time && <span className={styles.itemTime}>{time}</span>}
          </div>
          <div className={styles.itemBottom}>
            <div className={styles.itemStatus}>
              <span className={styles.itemPreview}>
                {latestItem?.imageUrl && <AgentThreadThumbnail url={latestItem.imageUrl} />}
                {preview}
              </span>
            </div>
            {hasUnread && <span className={styles.unreadCount}>{formatAgentNewsUnreadCount(unreadCount)}</span>}
          </div>
        </div>
      </div>
    </div>
  );
}

export default memo(AgentNewsRow);
