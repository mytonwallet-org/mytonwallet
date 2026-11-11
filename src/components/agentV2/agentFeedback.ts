import type { AgentAnswerFeedbackV2 } from '../../api/agentV2/protocol/types';

import { clamp } from '../../util/math';
import { REM } from '../../util/windowEnvironment';

import heartAppear from '../../assets/lottie/agent_reaction_heart_appear.tgs';
import brokenHeartAppear from '../../assets/lottie/agent_reaction_heart_broken_appear.tgs';
import brokenHeartBurst from '../../assets/lottie/agent_reaction_heart_broken_burst.tgs';
import brokenHeartCenter from '../../assets/lottie/agent_reaction_heart_broken_center.tgs';
import brokenHeartSelect from '../../assets/lottie/agent_reaction_heart_broken_select.tgs';
import heartBurst from '../../assets/lottie/agent_reaction_heart_burst.tgs';
import heartCenter from '../../assets/lottie/agent_reaction_heart_center.tgs';
import heartSelect from '../../assets/lottie/agent_reaction_heart_select.tgs';
import brokenHeartRest from '../../assets/lottiePreview/agent_reaction_heart_broken_center.png';
import brokenHeartStart from '../../assets/lottiePreview/agent_reaction_heart_broken_center_start.png';
import brokenHeartStill from '../../assets/lottiePreview/agent_reaction_heart_broken_select.png';
import heartRest from '../../assets/lottiePreview/agent_reaction_heart_center.png';
import heartStart from '../../assets/lottiePreview/agent_reaction_heart_center_start.png';
import heartStill from '../../assets/lottiePreview/agent_reaction_heart_select.png';

export interface Point {
  x: number;
  y: number;
}

interface Rect {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

interface Viewport {
  width: number;
  height: number;
  /** The inset of the system's bar at the top, which the cloud keeps clear of */
  safeAreaTop: number;
}

interface AgentFeedbackCloudLayout {
  /** The capsule's top left corner in the window */
  left: number;
  top: number;
  /** The centres of the tail's 16 px and 8 px dots, from the capsule's top left corner */
  largeDotX: number;
  largeDotY: number;
  smallDotX: number;
  smallDotY: number;
  /** Without room above the bubble, the cloud hangs under the message, and the menu under the cloud */
  isBelow: boolean;
}

/** Telegram's animated emoji of a reaction, from its available reactions, with stills of the frames they rest on */
interface AgentFeedbackAnimations {
  /** Plays once in the cloud as it opens */
  appear: string;
  /** Plays in the cloud on hover or press. Its first frame is the cloud's still icon. */
  select: string;
  /** Plays once at the answer's corner as a reaction lands there */
  center: string;
  /** The burst around the corner as a reaction lands there, drawn in a 512 px frame as Telegram's effects are */
  burst: string;
  /** The first frame of `select`, on which the cloud's icons rest, and which a chosen reaction leaves the cloud as */
  still: string;
  /** The last frame of `center`, on which the corner's emoji rests */
  rest: string;
  /** The first frame of `center`, which a reaction flying to the corner turns into before `center` plays from it */
  start: string;
  /** The size `center`, `rest` and `start` are drawn at, so that the emoji is as large as the design's 22 px icon */
  centerSize: number;
}

// A heart likes an answer, and a broken heart dislikes it. `center` fills 236 (heart) and 255 (broken heart) px of its
// 512 px frame, drawn about 18 px wide at these sizes.
export const AGENT_FEEDBACK_ANIMATIONS: Record<AgentAnswerFeedbackV2, AgentFeedbackAnimations> = {
  like: {
    appear: heartAppear,
    select: heartSelect,
    center: heartCenter,
    burst: heartBurst,
    still: heartStill,
    rest: heartRest,
    start: heartStart,
    centerSize: 40,
  },
  dislike: {
    appear: brokenHeartAppear,
    select: brokenHeartSelect,
    center: brokenHeartCenter,
    burst: brokenHeartBurst,
    still: brokenHeartStill,
    rest: brokenHeartRest,
    start: brokenHeartStart,
    centerSize: 36,
  },
};

// The emoji of `appear` and `select` fills 417 of their 512 px frame, so a 36 px icon in the cloud draws it 29 px wide,
// as the design's 36 px icon drew its 30 px heart
export const AGENT_FEEDBACK_CLOUD_ICON_SIZE = 36;

// The rem the cloud and the answer's emoji are drawn in: the root font size, taken as 16 px where it is not computed
const DESIGN_REM = REM || 16;

// The cloud of the design at a 16 px rem: a 108 × 56 capsule, 6 px over the bubble, with a tail of a 16 px dot on its
// bottom edge and an 8 px dot beside the bubble's top trailing corner
const CLOUD_WIDTH = 6.75 * DESIGN_REM;
export const AGENT_FEEDBACK_CLOUD_HEIGHT = 3.5 * DESIGN_REM;
const CLOUD_GAP = 0.375 * DESIGN_REM;
export const AGENT_FEEDBACK_LARGE_DOT_RADIUS = 0.5 * DESIGN_REM;
export const AGENT_FEEDBACK_SMALL_DOT_RADIUS = 0.25 * DESIGN_REM;
// How far the capsule's trailing end and the dots' centres reach past the bubble's trailing edge: 47, 4 and 13 px
const CLOUD_OVERHANG = 2.9375 * DESIGN_REM;
const LARGE_DOT_OVERHANG = 0.25 * DESIGN_REM;
const SMALL_DOT_OVERHANG = 0.8125 * DESIGN_REM;
// The 8 px dot's centre is 8 px into the bubble's height
const SMALL_DOT_INSET = 0.5 * DESIGN_REM;
const SCREEN_MARGIN = 0.75 * DESIGN_REM;
// The 8 px dot beside the bubble's corner keeps 4 px from the side of the screen
const SMALL_DOT_SCREEN_MARGIN = 0.25 * DESIGN_REM;

// The answer's emoji at a 16 px rem: 22 px, its centre 3 px inside the bubble's trailing edge and its bottom 3 px under
// the bubble's
export const AGENT_FEEDBACK_BADGE_ICON_SIZE = 1.375 * DESIGN_REM;
const BADGE_INSET = 0.1875 * DESIGN_REM;
const BADGE_DROP = 0.1875 * DESIGN_REM;
// Telegram's `generateParabollicMotionKeyframes` goes straight between ends nearer than this
const PARABOLA_STRAIGHT_DISTANCE = 5;

/**
 * Where the cloud of reactions stands over an answer: clear of its bubble, with the tail down beside the bubble's top
 * trailing corner, and the capsule moved in from a side of the screen it would cross. Where the tail beside the corner
 * would then come near the side of the screen or off the capsule, it moves in with the capsule and keeps its place
 * under it as in the design, over the bubble's top. Without room above the bubble the cloud hangs under the message
 * instead, its tail up beside the bubble's trailing side. Without room under it either, it stays at the top of the
 * screen over the message, the tail at the same offsets from the capsule, as Telegram keeps its reactions in reach
 * over a long message.
 */
export function getAgentFeedbackCloudLayout(
  bubbleRect: Rect,
  messageBottom: number,
  viewport: Viewport,
  isRtl: boolean,
): AgentFeedbackCloudLayout {
  const direction = isRtl ? -1 : 1;
  const trailingEdge = isRtl ? bubbleRect.left : bubbleRect.right;
  const capsuleEnd = trailingEdge + direction * CLOUD_OVERHANG;
  // The capsule's place in the design, where its tail is beside the bubble's corner
  const designLeft = isRtl ? capsuleEnd : capsuleEnd - CLOUD_WIDTH;
  const left = clamp(designLeft, SCREEN_MARGIN, viewport.width - SCREEN_MARGIN - CLOUD_WIDTH);
  const tailLeft = getIsTailAtCorner(trailingEdge, left, viewport.width, isRtl) ? left : designLeft;
  const largeDotX = trailingEdge + direction * LARGE_DOT_OVERHANG - tailLeft;
  const smallDotX = trailingEdge + direction * SMALL_DOT_OVERHANG - tailLeft;

  const topAbove = bubbleRect.top - CLOUD_GAP - AGENT_FEEDBACK_CLOUD_HEIGHT;
  const topBelow = messageBottom + CLOUD_GAP;
  const minTop = viewport.safeAreaTop + SCREEN_MARGIN;
  const isBelow = topAbove < minTop
    && topBelow + AGENT_FEEDBACK_CLOUD_HEIGHT <= viewport.height - SCREEN_MARGIN;

  if (isBelow) {
    return {
      left,
      top: topBelow,
      largeDotX,
      largeDotY: 0,
      smallDotX,
      smallDotY: messageBottom - SMALL_DOT_INSET - topBelow,
      isBelow,
    };
  }

  const top = Math.max(minTop, topAbove);
  return {
    left,
    top,
    largeDotX,
    largeDotY: AGENT_FEEDBACK_CLOUD_HEIGHT,
    smallDotX,
    smallDotY: AGENT_FEEDBACK_CLOUD_HEIGHT + CLOUD_GAP + SMALL_DOT_INSET,
    isBelow,
  };
}

/** The centre of the answer's emoji, at its bubble's bottom trailing corner */
export function getAgentFeedbackBadgeCenter(bubbleRect: Rect, isRtl: boolean): Point {
  return {
    x: isRtl ? bubbleRect.left + BADGE_INSET : bubbleRect.right - BADGE_INSET,
    y: bubbleRect.bottom + BADGE_DROP - AGENT_FEEDBACK_BADGE_ICON_SIZE / 2,
  };
}

/**
 * Telegram's `generateParabollicMotionKeyframes`: the point `progress` of the way along the parabola from `from` to
 * `to` through the point halfway across, `elevation` over `from`. It moves linearly across, so that it rises briefly
 * and then falls fast where `to` is lower. Ends nearer than 5 px go straight.
 */
export function getAgentFeedbackParabolaPoint(from: Point, to: Point, elevation: number, progress: number): Point {
  const x = from.x + (to.x - from.x) * progress;
  const isNear = Math.abs(to.x - from.x) < PARABOLA_STRAIGHT_DISTANCE
    && Math.abs(to.y - from.y) < PARABOLA_STRAIGHT_DISTANCE;
  if (isNear) {
    return { x, y: from.y + (to.y - from.y) * progress };
  }

  // The parabola through the three points, written in the progress, which `x` follows linearly
  const middleY = from.y - elevation;
  const y = from.y * (1 - progress) * (1 - 2 * progress)
    + middleY * 4 * progress * (1 - progress)
    + to.y * progress * (2 * progress - 1);
  return { x, y };
}

/**
 * The tail stays beside the bubble's corner while its 8 px dot keeps 4 px from the side of the screen and its 16 px
 * dot's centre is over the capsule
 */
function getIsTailAtCorner(trailingEdge: number, capsuleLeft: number, screenWidth: number, isRtl: boolean) {
  const direction = isRtl ? -1 : 1;
  const largeDotCenter = trailingEdge + direction * LARGE_DOT_OVERHANG;
  const smallDotOuterEdge = trailingEdge + direction * (SMALL_DOT_OVERHANG + AGENT_FEEDBACK_SMALL_DOT_RADIUS);
  const smallDotRoom = isRtl ? smallDotOuterEdge : screenWidth - smallDotOuterEdge;

  return smallDotRoom >= SMALL_DOT_SCREEN_MARGIN
    && largeDotCenter >= capsuleLeft
    && largeDotCenter <= capsuleLeft + CLOUD_WIDTH;
}
