import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import type { AgentPublicFollowUpV2 } from '../../api/agentV2/protocol/types';

import buildClassName from '../../util/buildClassName';

import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentV2Conversation.module.scss';

const FOLLOWUP_CLOSE_DURATION = 200;

interface OwnProps {
  followups?: AgentPublicFollowUpV2[];
  isDisabled: boolean;
  shouldShowFollowups?: boolean;
  onFollowup: (item: AgentPublicFollowUpV2) => void;
  children?: TeactNode;
}

function AgentMessageControls({
  followups,
  isDisabled,
  shouldShowFollowups = false,
  onFollowup,
  children,
}: OwnProps) {
  const hasFollowupRow = Boolean(followups?.length);

  // Once a newer message arrives, the row fades out and leaves the DOM instead of staying under an old answer
  const { ref: followupRowRef, shouldRender: shouldRenderFollowupRow } = useShowTransition<HTMLDivElement>({
    isOpen: hasFollowupRow && shouldShowFollowups,
    withShouldRender: true,
    className: false,
    closeDuration: FOLLOWUP_CLOSE_DURATION,
  });

  if (!shouldRenderFollowupRow && !children) {
    return undefined;
  }

  return (
    <div className={styles.richContent}>
      {children}
      {shouldRenderFollowupRow && (
        <div ref={followupRowRef} className={styles.followupRow}>
          {followups?.map((item) => (
            <button
              key={item.id}
              type="button"
              data-agent-followup-id={item.id}
              className={buildClassName(styles.followupButton, styles.followupArrow)}
              disabled={isDisabled}
              onClick={() => onFollowup(item)}
            >
              <span className={styles.followupLabel}>{item.text}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export default AgentMessageControls;
