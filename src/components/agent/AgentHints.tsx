import React, { memo } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import useShowTransition from '../../hooks/useShowTransition';

import AgentSpinningTop from './AgentSpinningTop';

import followupStyles from '../agentV2/AgentV2Conversation.module.scss';
import styles from './AgentHints.module.scss';

interface OwnProps {
  isOpen: boolean;
  hints?: AgentHint[];
  onHintClick: (hint: AgentHint) => void;
}

const CLOSE_ANIMATION_DURATION_MS = 250;
// The empty chat's top spins at half the speed, as on mobile
const HINTS_TOP_SPEED = 0.5;

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
      <AgentSpinningTop
        className={styles.icon}
        markClassName={styles.iconMark}
        isGradientSoft
        speed={HINTS_TOP_SPEED}
        isTouchInteractive
      />
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
