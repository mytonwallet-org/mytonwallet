import React, {
  memo, useEffect, useRef,
} from '../../lib/teact/teact';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';

import { AGENT_FEEDBACK_ANIMATIONS, AGENT_FEEDBACK_CLOUD_ICON_SIZE } from './agentFeedback';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';
import { useStateRef } from '../../hooks/useStateRef';

import AnimatedSticker from '../ui/AnimatedSticker';

import styles from './AgentFeedbackPill.module.scss';

interface OwnProps {
  reaction: AgentAnswerFeedbackV2;
  /** Where motion is off, the icon is the still alone */
  noAnimation?: boolean;
  /** `appear` plays this long after the cloud opens, as the capsule reaches the icon's place */
  appearDelay: number;
  /** A new value plays `select` once, as the icon is hovered or pressed */
  selectKey?: string;
}

/**
 * A reaction's icon in the cloud, as Telegram's: its `appear` animation plays once as the capsule reaches it, and it
 * then rests on the first frame of `select`, which plays on hover or press. `select` loads as `appear` ends, which
 * stays on its last frame, the same picture, until then.
 */
function AgentFeedbackCloudIcon({
  reaction, noAnimation = false, appearDelay, selectKey,
}: OwnProps) {
  const { appear, select, still } = AGENT_FEEDBACK_ANIMATIONS[reaction];
  const [isAppearStarted, startAppear] = useFlag(false);
  const [isAppeared, markAppeared] = useFlag(false);
  const [isSelectLoaded, markSelectLoaded] = useFlag(false);
  const selectKeyRef = useStateRef(selectKey);
  // A hover before the icon has appeared does not play `select` once it has
  const appearedSelectKeyRef = useRef(selectKey);

  useEffect(() => {
    if (noAnimation || isAppeared) return undefined;

    const timeout = window.setTimeout(startAppear, appearDelay);
    return () => window.clearTimeout(timeout);
  }, [appearDelay, isAppeared, noAnimation, startAppear]);

  const handleAppearEnded = useLastCallback(() => {
    appearedSelectKeyRef.current = selectKeyRef.current;
    markAppeared();
  });

  if (noAnimation) {
    return (
      <span className={styles.icon}>
        <img className={styles.still} src={still} alt="" draggable={false} />
      </span>
    );
  }

  const isSelectPlaying = isAppeared && Boolean(selectKey) && selectKey !== appearedSelectKeyRef.current;

  return (
    <span className={styles.icon}>
      {!isSelectLoaded && (
        <AnimatedSticker
          className={styles.sticker}
          renderId={`agent-reaction-${reaction}-appear-${AGENT_FEEDBACK_CLOUD_ICON_SIZE}`}
          tgsUrl={appear}
          size={AGENT_FEEDBACK_CLOUD_ICON_SIZE}
          play={isAppearStarted}
          noLoop
          forceOnHeavyAnimation
          onEnded={handleAppearEnded}
        />
      )}
      {isAppeared && (
        <AnimatedSticker
          className={styles.sticker}
          renderId={`agent-reaction-${reaction}-select-${AGENT_FEEDBACK_CLOUD_ICON_SIZE}`}
          tgsUrl={select}
          size={AGENT_FEEDBACK_CLOUD_ICON_SIZE}
          play={isSelectPlaying ? selectKey : false}
          noLoop
          forceOnHeavyAnimation
          onLoad={markSelectLoaded}
        />
      )}
    </span>
  );
}

export default memo(AgentFeedbackCloudIcon);
