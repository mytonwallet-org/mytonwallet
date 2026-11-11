import React, { memo } from '../../lib/teact/teact';

import type { AgentNewsFeedItemV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { getAvatarGradientColors } from '../ui/helpers/getAvatarGradientColor';

import useLastCallback from '../../hooks/useLastCallback';

import AgentMark from '../agent/AgentMark';
import AgentSearchGlyph from '../agent/AgentSearchGlyph';

import styles from './AgentNews.module.scss';

interface OwnProps {
  label: string;
  ariaLabel: string;
  /** The chat the discussion goes on in, whose avatar takes the place of the Agent mark */
  discussion?: AgentNewsFeedItemV2['discussion'];
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void;
}

/** The "Discuss" strip at the foot of a feed's card, as a channel post's comments, which opens the card's discussion */
function AgentNewsDiscussStrip({
  label, ariaLabel, discussion, onClick,
}: OwnProps) {
  // The strip is a button of its own: pressing it does not open the card's menu
  const handlePointer = useLastCallback((e: React.MouseEvent) => {
    e.stopPropagation();
  });

  return (
    <button
      type="button"
      className={styles.cardDiscussion}
      data-agent-news-discuss
      aria-label={ariaLabel}
      onMouseDown={handlePointer}
      onContextMenu={handlePointer}
      onClick={onClick}
    >
      <span className={styles.cardDiscussionContent}>
        {renderDiscussionIcon(discussion)}
        <span className={styles.cardDiscussionLabel}>{label}</span>
        <svg className={styles.cardDiscussionChevron} viewBox="0 0 24 24" aria-hidden>
          <path d="M9.5 6.5L15 12l-5.5 5.5" />
        </svg>
      </span>
    </button>
  );
}

export default memo(AgentNewsDiscussStrip);

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
