import { addExtraClass } from '../../../lib/teact/teact-dom';

import type { MotionPoint, MotionRect } from './agentMotion';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../../lib/fasterdom/fasterdom';
import { animate } from '../../../util/animation';
import { getTelegramProgress, interpolateRect, TELEGRAM_EASING } from './agentMotion';

import styles from '../AgentRunActivity.module.scss';

interface MotionSize {
  width: number;
  height: number;
}

/** What the answer's bubble shows of itself, in its own box */
interface TypingAnswerClip {
  rect: MotionRect;
  radius: number;
}

// The typing row turns into the answer over 0.4 s, as on iOS
export const TYPING_ANSWER_MORPH_DURATION = 400;
// The spinning top ends this small, this far toward the leading edge and up
const TOP_END_SCALE = 0.2;
const TOP_TRAVEL_X = -14;
const TOP_TRAVEL_Y = -10;
const TOP_DURATION = 300;
const STATUS_DISSOLVE_DURATION = 300;
// The answer's text comes into focus a moment after the status starts dissolving
const CONTENT_DELAY = 60;
const BUBBLE_FADE_DURATION = 200;
// What the bubble shows ends this far outside it, its corners concentric with the bubble's, so the bubble's own shape,
// its tail included, shows by then
const CLIP_OUTSET = 8;
// The blur the status leaves into and the answer's text comes out of, the Agent's blur transition's
const BLUR_RADIUS = '0.5rem';

/**
 * The typing row turns into the answer that takes its place rather than swapping for it, as on iOS: the spinning top
 * shrinks as it moves away, the status dissolves into the answer's first characters as it moves onto them, and the
 * answer's `bubble` grows out of the row's frame into its own, following the bubble as the answer streams in. The
 * `row` is the run's indicator that stood in for the bubble, which stands over it as it goes. It measures the two in
 * a forced reflow and starts the morph in its mutation.
 */
export function startTypingAnswerMorph(row: HTMLElement, bubble: HTMLElement) {
  requestForcedReflow(() => {
    const top = row.querySelector<HTMLElement>(`.${styles.icon}`);
    const status = row.querySelector<HTMLElement>(`.${styles.steps}`);
    const bubbleRect = bubble.getBoundingClientRect();
    if (!bubble.animate || !top || !status || bubbleRect.width < 1 || bubbleRect.height < 1) return undefined;

    const rowRect = row.getBoundingClientRect();
    const style = getComputedStyle(bubble);
    const isRtl = style.direction === 'rtl';
    // Where the answer's first characters stand
    const textStart = {
      x: isRtl
        ? bubbleRect.right - (parseFloat(style.borderRightWidth) || 0) - (parseFloat(style.paddingRight) || 0)
        : bubbleRect.left + (parseFloat(style.borderLeftWidth) || 0) + (parseFloat(style.paddingLeft) || 0),
      y: bubbleRect.top + (parseFloat(style.borderTopWidth) || 0) + (parseFloat(style.paddingTop) || 0),
    };
    const landing = getStatusLanding(status.getBoundingClientRect(), textStart, isRtl);
    const start: MotionRect = {
      left: rowRect.left - bubbleRect.left,
      top: rowRect.top - bubbleRect.top,
      width: rowRect.width,
      height: rowRect.height,
    };
    const radius = parseFloat(style.borderTopLeftRadius) || 0;
    const topTravelX = TOP_TRAVEL_X * (isRtl ? -1 : 1);

    return () => {
      // The row stands over the bubble as its top and its status leave on their own
      addExtraClass(row, styles.answerPlaceholderMorphing);
      top.animate([
        { translate: '0 0', scale: '1', opacity: 1 },
        { translate: `${topTravelX}px ${TOP_TRAVEL_Y}px`, scale: String(TOP_END_SCALE), opacity: 0 },
      ], { duration: TOP_DURATION, easing: TELEGRAM_EASING, fill: 'forwards' });
      status.animate([{ translate: '0 0' }, { translate: `${landing.x}px ${landing.y}px` }], {
        duration: TYPING_ANSWER_MORPH_DURATION, easing: TELEGRAM_EASING, fill: 'forwards',
      });
      status.animate([{ opacity: 1, filter: 'none' }, { opacity: 0, filter: `blur(${BLUR_RADIUS})` }], {
        duration: STATUS_DISSOLVE_DURATION, easing: 'ease-in', fill: 'forwards',
      });
      // The answer's text comes into focus where the status dissolves
      Array.from(bubble.children).forEach((content) => {
        content.animate([{ opacity: 0, filter: `blur(${BLUR_RADIUS})` }, { opacity: 1, filter: 'none' }], {
          duration: STATUS_DISSOLVE_DURATION, delay: CONTENT_DELAY, easing: 'ease-out', fill: 'backwards',
        });
      });
      bubble.animate([{ opacity: 0 }, { opacity: 1 }], { duration: BUBBLE_FADE_DURATION, easing: 'ease-out' });
      growBubble(bubble, start, radius, bubbleRect);
    };
  });
}

/** What the bubble shows `progress` of the way from the row's frame, `start` in its box, to the whole of itself */
export function getTypingAnswerClip(start: MotionRect, bubble: MotionSize, radius: number, progress: number) {
  const end: MotionRect = {
    left: -CLIP_OUTSET,
    top: -CLIP_OUTSET,
    width: bubble.width + 2 * CLIP_OUTSET,
    height: bubble.height + 2 * CLIP_OUTSET,
  };
  const rect = interpolateRect(start, end, progress);

  return {
    rect,
    radius: Math.max(0, Math.min(radius + CLIP_OUTSET * progress, rect.width / 2, rect.height / 2)),
  };
}

/** How far the status moves for its leading top corner to land on `textStart`, the answer's first characters */
export function getStatusLanding(status: MotionRect, textStart: MotionPoint, isRtl: boolean): MotionPoint {
  return {
    x: textStart.x - (isRtl ? status.left + status.width : status.left),
    y: textStart.y - status.top,
  };
}

// The bubble shows within the row's frame at first, which grows into the bubble's frame as the bubble is now, so the
// growth keeps up with an answer that streams in meanwhile
function growBubble(bubble: HTMLElement, start: MotionRect, radius: number, size: MotionSize) {
  const startedAt = Date.now();
  bubble.style.setProperty('clip-path', buildClipPath(getTypingAnswerClip(start, size, radius, 0), size));

  animate(() => {
    if (!bubble.isConnected) return false;

    const fraction = Math.min(1, (Date.now() - startedAt) / TYPING_ANSWER_MORPH_DURATION);
    const current = { width: bubble.offsetWidth, height: bubble.offsetHeight };
    const clipPath = fraction < 1
      ? buildClipPath(getTypingAnswerClip(start, current, radius, getTelegramProgress(fraction)), current)
      : undefined;
    requestMutation(() => {
      if (clipPath) {
        bubble.style.setProperty('clip-path', clipPath);
      } else {
        bubble.style.removeProperty('clip-path');
      }
    });

    return fraction < 1;
  }, requestMeasure);
}

function buildClipPath({ rect, radius }: TypingAnswerClip, { width, height }: MotionSize) {
  const right = width - rect.left - rect.width;
  const bottom = height - rect.top - rect.height;
  return `inset(${rect.top}px ${right}px ${bottom}px ${rect.left}px round ${radius}px)`;
}
