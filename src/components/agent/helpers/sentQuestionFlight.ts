import type { RgbaColor } from '../../../util/colors';
import type { BezierCurve, MotionPoint, MotionRect } from './agentMotion';

import { requestMeasure, requestMutation } from '../../../lib/fasterdom/fasterdom';
import { animate } from '../../../util/animation';
import buildClassName from '../../../util/buildClassName';
import { compositeCssColors, parseCssColor } from '../../../util/colors';
import { lerp } from '../../../util/math';
import {
  cacheWhileConnected,
  copyTextStyle,
  createTextPicture,
  getBezierProgress,
  getBorderRadii,
  getLayerRect,
} from './agentMotion';

import styles from '../SentQuestionFlight.module.scss';

/** The field's text as the question went, which the question's bubble comes out of */
export interface SentTextPicture {
  /** The field's text box in the chat's motion layer, out of sight until the flight */
  element: HTMLElement;
  /** The text's lines, scrolled as far as the field's */
  lines: HTMLElement;
  /** The text in them, whose box is where the text shows */
  text: HTMLElement;
  /** The field's text box and the field itself, in the layer */
  box: MotionRect;
  field: MotionRect;
  scrollTop: number;
  fontSize: number;
  color: string;
  isRtl: boolean;
  time: number;
}

/** Where the flight starts: the field, and the leading top corner of its text's first line, in the layer */
export interface SentFlightStart {
  field: MotionRect;
  textOrigin: MotionPoint;
  fontSize: number;
}

/** Where the flight goes: the bubble's body, without its tail, in the layer, and its text */
export interface SentFlightTarget {
  frame: MotionRect;
  /** From the body's leading top corner to the leading top corner of the text's first line */
  textOffset: MotionPoint;
  fontSize: number;
}

/** What the flight shows at a moment of its way */
interface SentFlightState {
  /** The bubble's body, its tail hanging off its end */
  frame: MotionRect;
  /** The leading top corner of the text's first line, where the field's text and the bubble's stand together */
  textOrigin: MotionPoint;
  /** Each scales about that corner, the field's text from its own size and the bubble's to its own */
  fieldTextScale: number;
  bubbleTextScale: number;
  /** How far the bubble and its text have come in, as the field's text has gone */
  appearance: number;
  /** How far the clip has gone from the layer's bottom up to the list's */
  clipShare: number;
}

// Telegram's `TextMessageEnterTransition`, as Android plays it too: one linear clock of
// `ChatListItemAnimator.DEFAULT_DURATION`
export const SENT_QUESTION_FLIGHT_DURATION = 250;
// The text moves up, and the bubble's top and bottom with it, on `ChatListItemAnimator.DEFAULT_INTERPOLATOR`
const VERTICAL_CURVE: BezierCurve = {
  x1: 0.19919472913616398, y1: 0.010644531250000006, x2: 0.27920937042459737, y2: 0.91025390625,
};
// It moves across and changes its size, and the clip rises, on `EASE_OUT` of `EASE_OUT_QUINT`
const EASE_OUT_QUINT: BezierCurve = {
  x1: 0.23, y1: 1, x2: 0.32, y2: 1,
};
const EASE_OUT: BezierCurve = {
  x1: 0, y1: 0, x2: 0.58, y2: 1,
};
// The bubble and its text come in, and the field's text goes, over this share of the clock
const APPEARANCE_SHARE = 0.4;
// The bubble's end starts this far past where it lands, Telegram's 4 dp, in px
const BUBBLE_END_OVERHANG = 4;
// A picture older than this is not the sent question's any more. It outlives the wait of a chat that opens with the
// question for the question to show, `QUESTION_WAIT` of `agentOpeningQuestion.ts`, by the time the flight takes to
// measure the layout once the question shows.
const PICTURE_LIFETIME = 1200;
// The list's longest scroll, the most the text waits in the field for a bubble the list brings up from under it
const FIELD_HOLD_LIMIT = 600;
// A bubble under the field that has not risen for this long is not being brought up by the list
const STILL_BUBBLE_WAIT = 60;
// The most a flight waits where it starts for its time to be known, as for the transition of a screen it is stretched
// over to start
const DURATION_WAIT_LIMIT = 500;
// Telegram sends a longer message without its transition, the bubble showing in its place, as Android does here too
const MAX_FLIGHT_LINES = 10;

/**
 * Pictures the text of the field as it shows, in its place in the chat's motion `layer`, for the question's bubble to
 * come out of. The picture stays out of sight until the flight, unless `shouldShow`, as when it holds the text in place
 * for a chat on another screen. It reads the layout, so it is called outside a mutation phase, and the picture is added
 * in a mutation.
 */
export function createSentTextPicture(
  input: HTMLTextAreaElement, layer: HTMLElement, shouldShow = false,
): SentTextPicture | undefined {
  const { value } = input;
  if (!value.trim()) return undefined;

  const style = getComputedStyle(input);
  const paddingLeft = parseFloat(style.paddingLeft) || 0;
  const paddingTop = parseFloat(style.paddingTop) || 0;
  const width = input.clientWidth - paddingLeft - (parseFloat(style.paddingRight) || 0);
  const height = input.clientHeight - paddingTop - (parseFloat(style.paddingBottom) || 0);
  if (width < 1 || height < 1) return undefined;

  const rect = input.getBoundingClientRect();
  const layerRect = layer.getBoundingClientRect();
  const box: MotionRect = {
    left: rect.left + input.clientLeft + paddingLeft - layerRect.left,
    top: rect.top + input.clientTop + paddingTop - layerRect.top,
    width,
    height,
  };
  const element = document.createElement('div');
  element.className = buildClassName(styles.picture, shouldShow && styles.pictureFlying);
  element.style.left = `${box.left}px`;
  element.style.top = `${box.top}px`;
  element.style.width = `${width}px`;
  element.style.height = `${height}px`;

  // The lines break as in the field, and scroll as far
  const lines = document.createElement('div');
  lines.className = styles.pictureLines;
  copyTextStyle(lines, style);
  lines.style.width = `${width}px`;
  lines.style.marginTop = `${-input.scrollTop}px`;
  const text = document.createElement('span');
  text.textContent = value;
  lines.appendChild(text);
  element.appendChild(lines);

  requestMutation(() => {
    layer.appendChild(element);
  });

  return {
    element,
    lines,
    text,
    box,
    field: getLayerRect(rect, layerRect),
    scrollTop: input.scrollTop,
    fontSize: parseFloat(style.fontSize) || 0,
    color: style.color,
    isRtl: style.direction === 'rtl',
    time: Date.now(),
  };
}

export function removeSentTextPicture({ element }: SentTextPicture) {
  requestMutation(() => {
    element.remove();
  });
}

/**
 * Telegram's send: the question's bubble comes out of the field. Its background grows from the field's box into the
 * bubble as it comes in, its start keeping its padding from the text and its end past the tail nearly in place, while
 * the field's text moves onto the bubble's text, taking its size and colour, and gives way to it. The flight follows
 * the bubble wherever the list shows it meanwhile, as when the list takes the question up, which `getBubble` finds
 * again whenever the bubble found has left the document, and the bubble stays out of sight until the flight ends and
 * the bubble takes its place at once. The text only ever rises out of the field: while the list brings the bubble up
 * from under the field, the text waits in the field until the bubble has come over it, and a bubble left under the
 * field is aimed at on the field's line. The flight passes under the field once it is past it: it is clipped from the
 * layer's bottom up to the top of the field's row, which `getFieldRow` finds, as it goes across. Stretched over a
 * longer `duration`, as a screen's transition, it keeps its curves and the share of its time the bubble takes to come
 * in, and `onEnd` follows its end. A `duration` given as a function is read as the flight's time starts, and the
 * flight waits where it starts while it gives none, as while that transition has yet to start, for
 * `DURATION_WAIT_LIMIT` at most.
 *
 * It reads the layout, so it is called in a measure phase, and returns the flight to start in a mutation, which returns
 * what ends it where it stands. A picture that is gone or too old, a bubble without its text, or one of more than
 * `MAX_FLIGHT_LINES` lines has no flight.
 */
export function measureSentQuestionFlight(
  picture: SentTextPicture,
  bubble: HTMLElement,
  text: HTMLElement,
  getBubble: () => HTMLElement | undefined,
  layer: HTMLElement,
  getFieldRow: () => Element | undefined,
  duration: number | (() => number | undefined) = SENT_QUESTION_FLIGHT_DURATION,
  onEnd?: NoneToVoidFunction,
) {
  const {
    element, lines, box, isRtl,
  } = picture;
  const body = bubble.getBoundingClientRect();
  const textRect = text.getBoundingClientRect();
  if (!element.isConnected || Date.now() - picture.time > PICTURE_LIFETIME || body.width < 1 || textRect.width < 1) {
    return undefined;
  }

  let layerRect = layer.getBoundingClientRect();
  const bubbleStyle = getComputedStyle(bubble);
  if (getLineCount(body, bubbleStyle) > MAX_FLIGHT_LINES) return undefined;

  const tailStyle = getComputedStyle(bubble, '::after');
  const textStyle = getComputedStyle(text);
  const tailWidth = parseFloat(tailStyle.width) || 0;
  const bubbleFontSize = parseFloat(textStyle.fontSize) || picture.fontSize || 1;
  const start: SentFlightStart = {
    field: picture.field,
    textOrigin: { x: isRtl ? box.left + box.width : box.left, y: box.top - picture.scrollTop },
    fontSize: picture.fontSize || bubbleFontSize,
  };
  let target: SentFlightTarget = {
    frame: getLayerRect(body, layerRect),
    textOffset: {
      x: isRtl ? body.right - textRect.right : textRect.left - body.left,
      y: (parseFloat(bubbleStyle.borderTopWidth) || 0) + (parseFloat(bubbleStyle.paddingTop) || 0),
    },
    fontSize: bubbleFontSize,
  };
  const radii = getBorderRadii(bubbleStyle).map((radius) => parseFloat(radius) || 0);
  const fieldColor = parseCssColor(picture.color);
  const bubbleColor = parseCssColor(textStyle.color);
  const findBubble = cacheWhileConnected(getBubble);
  const findFieldRow = cacheWhileConnected(getFieldRow);
  const getClipLine = () => findFieldRow()?.getBoundingClientRect().top;
  let clipLine = getClipLine();

  const flight = document.createElement('div');
  flight.className = styles.flight;
  const background = document.createElement('div');
  background.className = styles.flightBubble;
  background.style.backgroundColor = bubbleStyle.backgroundColor;
  const tail = document.createElement('div');
  tail.className = styles.flightTail;
  tail.style.width = `${tailWidth}px`;
  tail.style.height = tailStyle.height;
  tail.style.backgroundColor = tailStyle.backgroundColor;
  tail.style.setProperty('mask-image', tailStyle.getPropertyValue('mask-image'));
  tail.style.setProperty('-webkit-mask-image', tailStyle.getPropertyValue('-webkit-mask-image'));
  tail.style.setProperty(isRtl ? 'left' : 'right', `${-tailWidth}px`);
  background.appendChild(tail);
  const bubbleText = createTextPicture(text, textRect.width, styles.flightText);
  const bubbleTextWidth = Math.ceil(textRect.width);
  bubbleText.style.transformOrigin = isRtl ? '100% 0' : '0 0';

  function showState(state: SentFlightState) {
    const { frame, textOrigin, appearance } = state;
    const layerBottom = layerRect.height;
    const listBottom = clipLine === undefined ? layerBottom : clipLine - layerRect.top;
    flight.style.height = `${Math.max(0, lerp(layerBottom, listBottom, state.clipShare))}px`;
    background.style.transform = `translate(${frame.left}px, ${frame.top}px)`;
    background.style.width = `${frame.width}px`;
    background.style.height = `${frame.height}px`;
    background.style.borderRadius = radii.map((radius) => `${Math.min(radius, frame.height / 2)}px`).join(' ');
    background.style.opacity = String(appearance);
    const fieldTextShiftX = textOrigin.x - start.textOrigin.x;
    const fieldTextShiftY = textOrigin.y - start.textOrigin.y;
    element.style.transform = `translate(${fieldTextShiftX}px, ${fieldTextShiftY}px) scale(${state.fieldTextScale})`;
    element.style.opacity = String(1 - appearance);
    if (fieldColor && bubbleColor) {
      const color = mixColors(fieldColor, bubbleColor, appearance);
      lines.style.color = color;
      lines.style.setProperty('-webkit-text-fill-color', color);
    }
    const bubbleTextLeft = isRtl ? textOrigin.x - bubbleTextWidth : textOrigin.x;
    bubbleText.style.transform = `translate(${bubbleTextLeft}px, ${textOrigin.y}px) scale(${state.bubbleTextScale})`;
    bubbleText.style.opacity = String(appearance);
  }

  // The flight's time starts once it is known, or once the flight has waited for it as long as it may
  function startClock(now: number, waitedFor: number) {
    const time = typeof duration === 'number' ? duration : duration();
    if (time === undefined && waitedFor < DURATION_WAIT_LIMIT) return undefined;

    return { startedAt: now, duration: time ?? SENT_QUESTION_FLIGHT_DURATION };
  }

  return () => {
    let isFinished = false;
    let firstFrameAt: number | undefined;
    let risenAt: number | undefined;
    let clock: { startedAt: number; duration: number } | undefined;
    let hiddenBubble: HTMLElement | undefined;

    function hideBubble(shownBubble: HTMLElement) {
      if (hiddenBubble === shownBubble) return;

      hiddenBubble?.style.removeProperty('opacity');
      hiddenBubble = shownBubble;
      shownBubble.style.opacity = '0';
    }

    // The real bubble takes over at the end, at once: two translucent bubbles would show lighter than either
    function finish() {
      if (isFinished) return;

      isFinished = true;
      requestMutation(() => {
        flight.remove();
        hiddenBubble?.style.removeProperty('opacity');
        onEnd?.();
      });
    }

    // The field's text scales about where its first line starts, which lies above its box as far as the field scrolled
    element.style.transformOrigin = `${isRtl ? '100%' : '0'} ${-picture.scrollTop}px`;
    element.classList.add(styles.pictureFlying);
    flight.append(background, element, bubbleText);
    showState(getSentFlightState(start, target, 0, isRtl));
    layer.appendChild(flight);
    hideBubble(bubble);

    animate(() => {
      if (isFinished) return false;

      const now = Date.now();
      const previousTop = target.frame.top;
      const shownBubble = findBubble();
      const shownBody = shownBubble?.getBoundingClientRect();
      layerRect = layer.getBoundingClientRect();
      if (shownBody && shownBody.width >= 1 && shownBody.height >= 1) {
        target = { ...target, frame: getLayerRect(shownBody, layerRect) };
      }
      clipLine = getClipLine();
      // The flight's time starts with its first frame on screen, so a busy frame as the question goes in keeps it
      // whole. A bubble under the field is waited for while the list keeps bringing it up, until it has come over the
      // field, for the list's longest scroll at most.
      firstFrameAt ??= now;
      if (risenAt === undefined || target.frame.top < previousTop) risenAt = now;
      const isBubbleAwaited = target.frame.top > start.field.top && now - risenAt < STILL_BUBBLE_WAIT
        && now - firstFrameAt < FIELD_HOLD_LIMIT;
      if (!clock && !isBubbleAwaited) clock = startClock(now, now - firstFrameAt);
      const fraction = clock ? Math.min(1, (now - clock.startedAt) / clock.duration) : 0;
      const state = getSentFlightState(start, target, fraction, isRtl);

      requestMutation(() => {
        if (isFinished) return;

        if (shownBubble) hideBubble(shownBubble);
        showState(state);
        if (fraction >= 1) finish();
      });

      return fraction < 1;
    }, requestMeasure);

    return finish;
  };
}

/** The flight as it stands `fraction` of its time into it, from `start` to `target` */
export function getSentFlightState(
  start: SentFlightStart,
  target: SentFlightTarget,
  fraction: number,
  isRtl: boolean,
): SentFlightState {
  const verticalProgress = getBezierProgress(VERTICAL_CURVE, fraction);
  const progress = getBezierProgress(EASE_OUT, getBezierProgress(EASE_OUT_QUINT, fraction));
  const { frame, textOffset } = target;
  const right = frame.left + frame.width;
  const targetTextX = isRtl ? right - textOffset.x : frame.left + textOffset.x;
  // The body's start goes across with the text, and its end starts a little past where it lands
  const textShift = (start.textOrigin.x - targetTextX) * (1 - progress);
  const endOverhang = BUBBLE_END_OVERHANG * (1 - progress);
  const left = isRtl ? frame.left - endOverhang : frame.left + textShift;
  const end = isRtl ? right + textShift : right + endOverhang;
  // It never goes down out of the field: a bubble still under the field is aimed at on the field's line
  const targetTop = Math.min(frame.top, start.field.top);
  const top = lerp(start.field.top, targetTop, verticalProgress);
  const bottom = lerp(start.field.top + start.field.height, targetTop + frame.height, verticalProgress);
  const fieldTextScale = lerp(1, target.fontSize / start.fontSize, progress);

  return {
    frame: {
      left, top, width: Math.max(0, end - left), height: Math.max(0, bottom - top),
    },
    textOrigin: {
      x: lerp(start.textOrigin.x, targetTextX, progress),
      y: lerp(start.textOrigin.y, targetTop + textOffset.y, verticalProgress),
    },
    fieldTextScale,
    bubbleTextScale: (fieldTextScale * start.fontSize) / target.fontSize,
    appearance: Math.min(1, fraction / APPEARANCE_SHARE),
    clipShare: progress,
  };
}

// The lines of a bubble's text, from the height its line boxes take in it
function getLineCount(body: DOMRect, style: CSSStyleDeclaration) {
  const lineHeight = parseFloat(style.lineHeight);
  if (!lineHeight) return 1;

  const padding = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
  const border = (parseFloat(style.borderTopWidth) || 0) + (parseFloat(style.borderBottomWidth) || 0);
  return Math.round((body.height - padding - border) / lineHeight);
}

// The field's colour gone `share` of the way to the bubble's
function mixColors(from: RgbaColor, to: RgbaColor, share: number) {
  return compositeCssColors(from, [{ ...to, alpha: to.alpha * share }]);
}
