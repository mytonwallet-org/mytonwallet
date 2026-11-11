import React, { memo, useState } from '../../lib/teact/teact';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';
import type { AgentFeedbackBadgeMotion } from './useAgentFeedbackBadge';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { AGENT_FEEDBACK_ANIMATIONS } from './agentFeedback';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedSticker from '../ui/AnimatedSticker';

import styles from './AgentFeedbackBadge.module.scss';

interface OwnProps {
  feedback: AgentAnswerFeedbackV2;
  /** The reaction this one replaces, whose emoji stays until this one shows and then goes */
  replacedFeedback?: AgentAnswerFeedbackV2;
  motion?: AgentFeedbackBadgeMotion;
  /**
   * The reaction flies to the corner: its emoji waits out of sight, at the first frame of `center`, until the flight
   * shows it in the frame it lands
   */
  isAwaitingFlight?: boolean;
  /** Changes as a reaction lands at the corner, which plays its emoji then */
  landingKey?: number;
  /** The reaction in words, in the app's language, which a screen reader reads with the bubble */
  label: string;
  /** Opens the answer's menu, as a long press on the bubble does */
  onClick: (e: React.MouseEvent) => void;
}

/**
 * The reaction chosen for an answer, as Telegram's on a message: its emoji alone on the bubble's bottom trailing
 * corner, taking no room, which scrolls with the bubble. It is not an element of its own for screen readers, which read
 * the reaction with the bubble.
 */
function AgentFeedbackBadge({
  feedback, replacedFeedback, motion, isAwaitingFlight = false, landingKey, label, onClick,
}: OwnProps) {
  const {
    center, rest, start, centerSize,
  } = AGENT_FEEDBACK_ANIMATIONS[feedback];
  // A reaction that lands plays Telegram's `center` animation once, from the frame the flight landed on, and the
  // emoji rests on its last frame
  const [playedLandingKey, setPlayedLandingKey] = useState(landingKey);
  const isCenterPlaying = landingKey !== playedLandingKey;
  const [isCenterLoaded, markCenterLoaded, unmarkCenterLoaded] = useFlag(false);
  const isAtCenterStart = isAwaitingFlight || (isCenterPlaying && !isCenterLoaded);
  const iconStyle = getIconStyle(centerSize);

  const handleCenterEnded = useLastCallback(() => {
    setPlayedLandingKey(landingKey);
    unmarkCenterLoaded();
  });

  return (
    <>
      <span
        className={buildClassName(styles.root, motion === 'leaving' && styles.leaving)}
        data-agent-feedback-badge={feedback}
        aria-hidden
        onClick={onClick}
      >
        {replacedFeedback && (
          <img
            key={replacedFeedback}
            className={styles.replacedIcon}
            style={getIconStyle(AGENT_FEEDBACK_ANIMATIONS[replacedFeedback].centerSize)}
            src={AGENT_FEEDBACK_ANIMATIONS[replacedFeedback].rest}
            data-agent-feedback-awaiting={isAwaitingFlight || undefined}
            alt=""
            draggable={false}
          />
        )}
        <img
          key={feedback}
          className={buildClassName(
            styles.icon,
            motion === 'appearing' && styles.iconAppearing,
            isCenterPlaying && isCenterLoaded && styles.iconHidden,
          )}
          style={iconStyle}
          src={isAtCenterStart ? start : rest}
          data-agent-feedback-awaiting={isAwaitingFlight || undefined}
          alt=""
          draggable={false}
        />
        {isCenterPlaying && (
          <AnimatedSticker
            key={feedback}
            className={styles.icon}
            style={iconStyle}
            renderId={`agent-reaction-${feedback}-center-${centerSize}`}
            tgsUrl={center}
            size={centerSize}
            play
            noLoop
            forceOnHeavyAnimation
            onLoad={markCenterLoaded}
            onEnded={handleCenterEnded}
          />
        )}
      </span>
      <span className={buildClassName('visually-hidden', styles.label)}>{label}</span>
    </>
  );
}

// The emoji is drawn in its frame at the size `AGENT_FEEDBACK_ANIMATIONS` gives it, centred on the corner
function getIconStyle(size: number) {
  return buildStyle(`width: ${size}px`, `height: ${size}px`, `margin: ${-size / 2}px`);
}

export default memo(AgentFeedbackBadge);
