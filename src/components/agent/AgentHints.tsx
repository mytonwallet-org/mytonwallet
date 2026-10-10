import React, { memo } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useShowTransition from '../../hooks/useShowTransition';

import followupStyles from '../agentV2/AgentV2Conversation.module.scss';
import styles from './AgentHints.module.scss';

interface OwnProps {
  isOpen: boolean;
  hints?: AgentHint[];
  onHintClick: (hint: AgentHint) => void;
}

const CLOSE_ANIMATION_DURATION_MS = 250;

function AgentHints({ isOpen, hints, onHintClick }: OwnProps) {
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen: isOpen && Boolean(hints?.length),
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_ANIMATION_DURATION_MS,
  });

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={styles.wrapper}>
      <i className={buildClassName(styles.icon, 'icon-agent')} aria-hidden />
      <div className={styles.list}>
        {hints!.map((hint) => (
          <button
            key={hint.id}
            type="button"
            className={followupStyles.followupButton}
            onClick={() => onHintClick(hint)}
          >
            <span className={followupStyles.followupLabel}>{hint.title}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

export default memo(AgentHints);
