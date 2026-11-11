import React, { memo } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useShowTransition from '../../hooks/useShowTransition';

import AgentSpinningTop from './AgentSpinningTop';

import followupStyles from '../agentV2/AgentV2Conversation.module.scss';
import styles from './AgentHints.module.scss';

/** Where the hints stand in the list's content, in px */
export interface AgentHintsFrame {
  top: number;
  left: number;
  width: number;
}

interface OwnProps {
  isOpen: boolean;
  hints?: AgentHint[];
  /** The hints leave from here, out of the list's flow, so that what comes in their place does not move them */
  leavingFrame?: AgentHintsFrame;
  /** The tapped hint's button comes along, for the question to grow out of */
  onHintClick: (hint: AgentHint, button: HTMLElement) => void;
}

const CLOSE_ANIMATION_DURATION_MS = 250;
// The empty chat's top spins at half the speed, as on mobile
const HINTS_TOP_SPEED = 0.5;

function AgentHints({
  isOpen, hints, leavingFrame, onHintClick,
}: OwnProps) {
  const { ref, shouldRender } = useShowTransition<HTMLDivElement>({
    isOpen: isOpen && Boolean(hints?.length),
    withShouldRender: true,
    className: false,
    closeDuration: CLOSE_ANIMATION_DURATION_MS,
  });

  if (!shouldRender) return undefined;

  const frame = isOpen ? undefined : leavingFrame;

  return (
    <div
      ref={ref}
      className={buildClassName(styles.wrapper, frame && styles.wrapperLeaving)}
      style={frame ? `top: ${frame.top}px; left: ${frame.left}px; width: ${frame.width}px` : undefined}
      data-agent-hints
    >
      <AgentSpinningTop
        className={styles.icon}
        markClassName={styles.iconMark}
        isGradientSoft
        speed={HINTS_TOP_SPEED}
        isTouchInteractive
        shouldShowGround
      />
      <div className={styles.list}>
        {hints!.map((hint) => (
          <button
            key={hint.id}
            type="button"
            className={followupStyles.followupButton}
            onClick={(e) => onHintClick(hint, e.currentTarget)}
          >
            <span className={followupStyles.followupLabel}>{hint.title}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

export default memo(AgentHints);
