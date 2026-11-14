import { lerp } from '../../../util/math';

export interface MotionRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface MotionPoint {
  x: number;
  y: number;
}

/** A timing curve from 0 to 1 by its control points, as `cubic-bezier()` takes them */
export interface BezierCurve {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

/** Telegram's curve, which the Agent's messages move on as on iOS */
export const TELEGRAM_EASING = 'cubic-bezier(0.38, 0.7, 0.125, 1)';

const TELEGRAM_CURVE: BezierCurve = {
  x1: 0.38, y1: 0.7, x2: 0.125, y2: 1,
};
const NEWTON_ITERATIONS = 8;
const BISECTION_ITERATIONS = 32;
const CURVE_PRECISION = 1e-7;
// What a picture of text takes from the text it copies, so that it shows the same lines in the same look, a gradient
// drawn through the letters included
const TEXT_STYLE_PROPERTIES = [
  'font-family', 'font-size', 'font-weight', 'font-style', 'font-stretch', 'line-height', 'letter-spacing',
  'word-spacing', 'text-align', 'text-indent', 'text-transform', 'direction', 'unicode-bidi', 'white-space',
  'word-break', 'overflow-wrap', 'tab-size', 'color', '-webkit-text-fill-color', 'background-image',
  'background-size', 'background-position', 'background-repeat', 'background-clip', '-webkit-background-clip',
];

/** How far Telegram's curve has gone `fraction` of its way, as the browser plays `TELEGRAM_EASING` */
export function getTelegramProgress(fraction: number) {
  return getBezierProgress(TELEGRAM_CURVE, fraction);
}

/** How far `curve` has gone `fraction` of its way, as the browser plays it */
export function getBezierProgress({
  x1, y1, x2, y2,
}: BezierCurve, fraction: number) {
  if (fraction <= 0) return 0;
  if (fraction >= 1) return 1;

  return getBezierCoordinate(solveBezierTime(fraction, x1, x2), y1, y2);
}

/** How far `value` is through the range from `start` to `end`, from 0 before it to 1 after it */
export function getShare(value: number, start: number, end: number) {
  return Math.min(1, Math.max(0, (value - start) / (end - start)));
}

export function interpolateRect(from: MotionRect, to: MotionRect, progress: number): MotionRect {
  return {
    left: lerp(from.left, to.left, progress),
    top: lerp(from.top, to.top, progress),
    width: lerp(from.width, to.width, progress),
    height: lerp(from.height, to.height, progress),
  };
}

export function getRectCenter({
  left, top, width, height,
}: MotionRect): MotionPoint {
  return { x: left + width / 2, y: top + height / 2 };
}

/** `rect`, in the viewport, in a motion layer standing at `layerRect` */
export function getLayerRect(rect: MotionRect, layerRect: MotionRect): MotionRect {
  return {
    left: rect.left - layerRect.left, top: rect.top - layerRect.top, width: rect.width, height: rect.height,
  };
}

/** The corners of a box styled with `style`: top left, top right, bottom right and bottom left */
export function getBorderRadii(style: CSSStyleDeclaration) {
  return [
    style.borderTopLeftRadius, style.borderTopRightRadius, style.borderBottomRightRadius, style.borderBottomLeftRadius,
  ];
}

/**
 * Returns `find`, which looks for its element again only once the element it found has left the document, as when the
 * list renders it anew, so that a motion following the element does not search the document in each frame
 */
export function cacheWhileConnected<T extends Element>(find: () => T | undefined) {
  let element: T | undefined;
  return () => {
    if (!element?.isConnected) element = find();
    return element;
  };
}

/**
 * A picture of `element`'s text, as wide as the text shows, so that its lines break where the text's do. It reads the
 * element's style, so it is called in a measure phase.
 */
export function createTextPicture(element: HTMLElement, width: number, className: string) {
  const picture = document.createElement('div');
  picture.className = className;
  copyTextStyle(picture, getComputedStyle(element));
  picture.style.width = `${Math.ceil(width)}px`;
  picture.textContent = element.textContent;
  return picture;
}

/** Gives `element` the look of the text styled with `style` */
export function copyTextStyle(element: HTMLElement, style: CSSStyleDeclaration) {
  TEXT_STYLE_PROPERTIES.forEach((property) => {
    element.style.setProperty(property, style.getPropertyValue(property));
  });
}

// The time along the curve at which it has gone `fraction` of the way across, by Newton's method, or by bisection
// where the slope is too flat for it
function solveBezierTime(fraction: number, x1: number, x2: number) {
  let time = fraction;
  for (let i = 0; i < NEWTON_ITERATIONS; i++) {
    const error = getBezierCoordinate(time, x1, x2) - fraction;
    if (Math.abs(error) < CURVE_PRECISION) return time;

    const slope = getBezierSlope(time, x1, x2);
    if (Math.abs(slope) < CURVE_PRECISION) break;
    time -= error / slope;
  }

  let low = 0;
  let high = 1;
  time = fraction;
  for (let i = 0; i < BISECTION_ITERATIONS; i++) {
    const coordinate = getBezierCoordinate(time, x1, x2);
    if (Math.abs(coordinate - fraction) < CURVE_PRECISION) break;
    if (coordinate < fraction) {
      low = time;
    } else {
      high = time;
    }
    time = (low + high) / 2;
  }

  return time;
}

// A coordinate of the cubic Bézier curve from 0 to 1 with control coordinates `p1` and `p2`, at `time`
function getBezierCoordinate(time: number, p1: number, p2: number) {
  const inverse = 1 - time;
  return 3 * inverse * inverse * time * p1 + 3 * inverse * time * time * p2 + time * time * time;
}

function getBezierSlope(time: number, p1: number, p2: number) {
  const inverse = 1 - time;
  return 3 * inverse * inverse * p1 + 6 * inverse * time * (p2 - p1) + 3 * time * time * (1 - p2);
}
