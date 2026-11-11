import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';
import type { Point } from './agentFeedback';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import { clamp, lerp } from '../../util/math';
import {
  AGENT_FEEDBACK_ANIMATIONS,
  AGENT_FEEDBACK_BADGE_ICON_SIZE,
  getAgentFeedbackBadgeCenter,
  getAgentFeedbackParabolaPoint,
} from './agentFeedback';

import { playAgentFeedbackEffect } from './AgentFeedbackEffect';

import styles from './AgentFeedbackPill.module.scss';

/** The flying emoji at its centre and size, with how much of it is already the corner's drawing of it */
interface IconState extends Point {
  size: number;
  badgeShare: number;
}

/** The flying emoji: the cloud's still of it under the corner's first drawing of it, which cross-fade on the way */
interface FlightIcon {
  root: HTMLElement;
  /** The size the emoji is laid out at, which the flight scales to its current size */
  size: number;
  still: HTMLImageElement;
  badge: HTMLImageElement;
}

/** Ends a flight at once, showing the answer's emoji at rest */
export type AgentFeedbackFlightStop = NoneToVoidFunction;

/** Called once the flight has landed, or once it ended on its way */
type LandingWaiter = (hasLanded: boolean) => void;

// The answer's emoji waits out of sight for the reaction flying to it, and the emoji it replaces stays. In the frame
// the reaction lands, the new emoji shows and the old one goes.
const AWAITING_ATTRIBUTE = 'data-agent-feedback-awaiting';
const AWAITING_ICON_SELECTOR = `[data-agent-feedback-badge] [${AWAITING_ATTRIBUTE}]`;

// Telegram's `animateOutToReaction`: 0.2 s with linear timing along a parabola 30 px over the start halfway across,
// with the burst from 0.15 s
const FLIGHT_DURATION = 200;
const FLIGHT_ELEVATION = 30;
const BURST_DELAY = 150;
// Telegram's burst: three times the landing emoji expanded to twice the corner's
const BURST_SIZE = AGENT_FEEDBACK_BADGE_ICON_SIZE * 2 * 3;

// The answers whose emoji waits for a reaction flying to it, with what waits with it
const waitersByMessageId = new Map<number, Set<LandingWaiter>>();

/**
 * Choosing a reaction in the cloud, as Telegram's `animateOutToReaction` for a small reaction: its emoji leaves its
 * place in the cloud and flies to the answer's corner in 0.2 s along Telegram's parabola, its size going to the
 * corner's and its drawing from the cloud's still into the corner's first one. The burst starts around the corner
 * 0.15 s in. In the frame the emoji lands, the corner shows its own, which plays `center` from there. The corner is
 * measured on every frame, so that the flight follows the answer.
 */
export function startAgentFeedbackFlight(messageId: number, {
  reaction, getCloudIcon, getBubbleElement, isRtl,
}: {
  reaction: AgentAnswerFeedbackV2;
  /** The reaction's place in the cloud, which its emoji leaves at the size it has there */
  getCloudIcon: () => HTMLElement | undefined;
  getBubbleElement: () => HTMLElement | undefined;
  isRtl: boolean;
}): AgentFeedbackFlightStop {
  if (waitersByMessageId.has(messageId)) return () => undefined;

  function getCenter() {
    const bubble = getBubbleElement();
    if (!bubble) return undefined;

    return getCornerCenter(bubble, isRtl);
  }

  let icon: FlightIcon | undefined;
  let burstTimeout: number | undefined;
  let isFinished = false;

  function land(hasLanded: boolean) {
    if (isFinished) return;

    isFinished = true;
    window.clearTimeout(burstTimeout);
    // The corner shows its emoji in the very frame the flying one goes
    getBubbleElement()?.querySelectorAll(AWAITING_ICON_SELECTOR).forEach((badgeIcon) => {
      badgeIcon.removeAttribute(AWAITING_ATTRIBUTE);
    });
    icon?.root.remove();
    const waiters = waitersByMessageId.get(messageId);
    waitersByMessageId.delete(messageId);
    waiters?.forEach((onLanded) => onLanded(hasLanded));
  }

  waitersByMessageId.set(messageId, new Set());
  requestForcedReflow(() => {
    const iconRect = getCloudIcon()?.getBoundingClientRect();

    return () => {
      if (isFinished) return;

      if (!iconRect?.width) {
        land(true);
        return;
      }

      const start: IconState = {
        x: iconRect.left + iconRect.width / 2,
        y: iconRect.top + iconRect.height / 2,
        size: iconRect.width,
        badgeShare: 0,
      };
      const flightIcon = createIcon(reaction, start.size);
      icon = flightIcon;
      applyIconState(flightIcon, start);
      document.body.append(flightIcon.root);
      burstTimeout = window.setTimeout(() => playBurst(reaction, getCenter), BURST_DELAY);

      const startedAt = Date.now();
      let hasArrived = false;
      animate(() => {
        if (isFinished) return false;

        const target = getCenter();
        const progress = Math.min(1, (Date.now() - startedAt) / FLIGHT_DURATION);
        requestMutation(() => {
          if (isFinished) return;

          // The emoji lands in the frame after it has arrived, or at once without its target, as when the answer left
          // the screen
          if (!target || hasArrived) {
            land(true);
            return;
          }

          applyIconState(flightIcon, {
            ...getAgentFeedbackParabolaPoint(start, target, FLIGHT_ELEVATION, progress),
            size: lerp(start.size, AGENT_FEEDBACK_BADGE_ICON_SIZE, progress),
            badgeShare: progress,
          });
          hasArrived = progress === 1;
        });

        return Boolean(target) && !hasArrived;
      }, requestMeasure);
    };
  });

  return () => land(false);
}

/**
 * Calls `onLanded` once the reaction flying to the answer's corner has landed, telling whether it reached the corner
 * or ended on its way, or at once when none is on its way
 */
export function waitForAgentFeedbackFlight(messageId: number, onLanded: LandingWaiter) {
  const waiters = waitersByMessageId.get(messageId);
  if (!waiters) {
    onLanded(false);
    return undefined;
  }

  waiters.add(onLanded);
  return () => {
    waiters.delete(onLanded);
  };
}

export function getIsAgentFeedbackFlying(messageId: number) {
  return waitersByMessageId.has(messageId);
}

function getCornerCenter(bubble: HTMLElement, isRtl: boolean) {
  const bubbleRect = bubble.getBoundingClientRect();
  return bubbleRect.width ? getAgentFeedbackBadgeCenter(bubbleRect, isRtl) : undefined;
}

// The corner's drawing draws the emoji smaller in its frame, which is as much larger, so that both emoji match
function createIcon(reaction: AgentAnswerFeedbackV2, size: number): FlightIcon {
  const { still: stillUrl, start: startUrl, centerSize } = AGENT_FEEDBACK_ANIMATIONS[reaction];
  const badgeScale = centerSize / AGENT_FEEDBACK_BADGE_ICON_SIZE;

  const root = document.createElement('div');
  root.className = styles.flightIcon;
  root.setAttribute('aria-hidden', 'true');
  root.dataset.agentFeedbackFlight = reaction;
  root.style.width = `${size}px`;
  root.style.height = `${size}px`;
  const still = document.createElement('img');
  const badge = document.createElement('img');
  [still, badge].forEach((image) => {
    image.className = styles.flightIconImage;
    image.alt = '';
    image.draggable = false;
  });
  still.src = stillUrl;
  badge.src = startUrl;
  badge.style.width = `${badgeScale * 100}%`;
  badge.style.height = `${badgeScale * 100}%`;
  badge.style.left = `${(1 - badgeScale) * 50}%`;
  badge.style.top = `${(1 - badgeScale) * 50}%`;
  root.append(still, badge);

  return {
    root, size, still, badge,
  };
}

function playBurst(reaction: AgentAnswerFeedbackV2, getCenter: () => Point | undefined) {
  if (!getCenter()) return;

  playAgentFeedbackEffect({
    tgsUrl: AGENT_FEEDBACK_ANIMATIONS[reaction].burst,
    renderId: `agent-reaction-${reaction}-burst`,
    size: BURST_SIZE,
    getCenter,
  });
}

// The corner's drawing covers the still as it fades in over the first half, and the still fades out under it after
function applyIconState({
  root, size: layoutSize, still, badge,
}: FlightIcon, {
  x, y, size, badgeShare,
}: IconState) {
  const share = clamp(badgeShare, 0, 1);
  root.style.transform = `translate3d(${x - size / 2}px, ${y - size / 2}px, 0) scale(${size / layoutSize})`;
  still.style.opacity = String(clamp((1 - share) * 2, 0, 1));
  badge.style.opacity = String(clamp(share * 2, 0, 1));
}
