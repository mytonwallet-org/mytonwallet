import { useEffect, useRef, useState } from '../../lib/teact/teact';

import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';

import { getIsAgentFeedbackFlying, waitForAgentFeedbackFlight } from './agentFeedbackFlight';

import { useStateRef } from '../../hooks/useStateRef';

/** How the answer's emoji changes in place: a reaction's emoji comes, or a withdrawn one's goes */
export type AgentFeedbackBadgeMotion = 'appearing' | 'leaving';

// Telegram swaps a reaction's emoji at its place in 0.12 s, as `AgentFeedbackBadge.module.scss` does
const MOTION_DURATION = 120;

/**
 * The reaction an answer's corner shows, and how it changes. A rated answer shows its emoji at once, and keeps it
 * while the answer's menu is open. A reaction chosen in the cloud flies to the corner, which keeps the emoji it had
 * until the flight lands; it then shows the new one, which plays its emoji, in the frame the flight lands, while the
 * old one goes. A reaction that comes otherwise appears in place, and a withdrawn one goes. A rating that changes while
 * the cloud is open reaches the corner once the cloud has gone.
 */
export default function useAgentFeedbackBadge(
  messageId: number,
  feedback: AgentAnswerFeedbackV2 | undefined,
  isCloudOpen: boolean,
) {
  const followedFeedbackRef = useRef(feedback);
  if (!isCloudOpen) followedFeedbackRef.current = feedback;
  const followedFeedback = followedFeedbackRef.current;

  const [shownFeedback, setShownFeedback] = useState(followedFeedback);
  const [replacedFeedback, setReplacedFeedback] = useState<AgentAnswerFeedbackV2>();
  const [motion, setMotion] = useState<AgentFeedbackBadgeMotion>();
  const [isAwaitingFlight, setIsAwaitingFlight] = useState(false);
  const [landingKey, setLandingKey] = useState<number>();
  const shownFeedbackRef = useStateRef(shownFeedback);
  const motionRef = useStateRef(motion);
  const lastFeedbackRef = useRef(followedFeedback);

  useEffect(() => {
    if (followedFeedback === lastFeedbackRef.current) return undefined;
    lastFeedbackRef.current = followedFeedback;

    let timeout: number | undefined;
    if (!followedFeedback) {
      setReplacedFeedback(undefined);
      setIsAwaitingFlight(false);
      setMotion('leaving');
      timeout = window.setTimeout(() => {
        setMotion(undefined);
        setShownFeedback(undefined);
      }, MOTION_DURATION);
      return () => window.clearTimeout(timeout);
    }

    // The emoji shown goes as the new one comes, unless it is going already
    const shown = shownFeedbackRef.current;
    setReplacedFeedback(shown !== followedFeedback && motionRef.current !== 'leaving' ? shown : undefined);
    setShownFeedback(followedFeedback);

    if (getIsAgentFeedbackFlying(messageId)) {
      setIsAwaitingFlight(true);
      setMotion(undefined);
      const stopWaiting = waitForAgentFeedbackFlight(messageId, (hasLanded) => {
        setIsAwaitingFlight(false);
        if (hasLanded) setLandingKey((key) => (key ?? 0) + 1);
        timeout = window.setTimeout(() => setReplacedFeedback(undefined), MOTION_DURATION);
      });

      return () => {
        stopWaiting!();
        window.clearTimeout(timeout);
      };
    }

    setIsAwaitingFlight(false);
    setMotion('appearing');
    timeout = window.setTimeout(() => {
      setMotion(undefined);
      setReplacedFeedback(undefined);
    }, MOTION_DURATION);

    return () => window.clearTimeout(timeout);
  }, [followedFeedback, lastFeedbackRef, messageId, motionRef, shownFeedbackRef]);

  return {
    feedback: shownFeedback,
    /** The reaction the shown one replaces, whose emoji stays until the new one shows and then goes */
    replacedFeedback,
    motion,
    /** The reaction flies to the corner, which shows its emoji in the frame it lands */
    isAwaitingFlight,
    /** Changes as a reaction lands at the corner, which plays its emoji then */
    landingKey,
  };
}
