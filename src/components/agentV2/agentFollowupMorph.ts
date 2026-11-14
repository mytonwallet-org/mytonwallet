import type { MotionPoint, MotionRect } from '../agent/helpers/agentMotion';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import { lerp } from '../../util/math';
import {
  cacheWhileConnected,
  createTextPicture,
  getBorderRadii,
  getRectCenter,
  getShare,
  getTelegramProgress,
  interpolateRect,
} from '../agent/helpers/agentMotion';

import styles from './AgentV2Conversation.module.scss';

/** Where the morph starts: the pill tapped, with its title */
export interface FollowupMorphStart {
  frame: MotionRect;
  /** From the pill's leading top corner to the title's */
  titleOffset: MotionPoint;
  titleFontSize: number;
  /** The pill's corners, rounded as far as its glass is */
  radius: number;
}

/** Where the morph goes: the bubble's body, without its tail, and its text */
export interface FollowupMorphTarget {
  frame: MotionRect;
  /** From the body's leading top corner to the text's */
  textOffset: MotionPoint;
  fontSize: number;
  /** The body's corners: top left, top right, bottom right and bottom left */
  radii: number[];
}

/** What the morph shows at a moment of its way into the bubble */
interface FollowupMorphState {
  frame: MotionRect;
  radii: number[];
  /** Where the title and the text stand in the frame, on one point, from its leading top corner */
  textOffset: MotionPoint;
  /** Each scales about its leading top corner, the title from its own size and the text to its own */
  titleScale: number;
  textScale: number;
  pillOpacity: number;
  fillOpacity: number;
  titleOpacity: number;
  textOpacity: number;
  titleBlur: number;
  textBlur: number;
  /** How far the bubble's tail has grown out of its corner, or nothing before it starts to */
  tailScale?: number;
}

/** A tapped suggestion as it stood, for its question's bubble to come out of */
export interface FollowupSource {
  button: HTMLElement;
  start: FollowupMorphStart;
  /** The pill's glass, without its title and arrow */
  pill: HTMLElement;
  title: HTMLElement;
  isRtl: boolean;
  time: number;
}

// The tapped suggestion turns into its question's bubble over 0.45 s, as on iOS
export const FOLLOWUP_MORPH_DURATION = 450;
// The title gives way to the bubble's text, and the pill's fill to the bubble's, over this part of the morph
const CROSSFADE_START = 0.15;
const CROSSFADE_END = 0.6;
// The bubble's tail grows out of its corner over this part of the morph, once the fill is the bubble's
const TAIL_GROWTH_START = 0.6;
const TAIL_GROWTH_END = 1;
// The tail at its smallest: a point in the corner
const TAIL_COLLAPSED_SCALE = 0.01;
// The blur of the title as it fades out, and of the text before it fades in, half the Agent's blur transition's
export const FOLLOWUP_MORPH_BLUR = 4;
// A source older than this is not the sent question's any more. It outlives the wait of a chat that opens with the
// question for the question to show, `QUESTION_WAIT` of `agentOpeningQuestion.ts`, by the time the morph takes to
// measure the layout once the question shows.
const SOURCE_LIFETIME = 1200;
// The suggestions beside the tapped one leave this way, each this long after the one nearer to it
const RIPPLE_DURATION = 200;
const RIPPLE_STAGGER = 30;
const RIPPLE_END_SCALE = 0.95;
const RIPPLE_BLUR = 4;

/**
 * Takes the suggestion `button` as it stands, for the question it sends to come out of. It reads the layout, so it is
 * called in a measure phase.
 */
export function captureFollowupSource(button: HTMLElement): FollowupSource | undefined {
  const label = button.querySelector<HTMLElement>(`.${styles.followupLabel}`);
  const frame = button.getBoundingClientRect();
  const titleRect = label?.getBoundingClientRect();
  if (!label || !titleRect || frame.width < 1 || frame.height < 1 || titleRect.width < 1) return undefined;

  const style = getComputedStyle(button);
  const isRtl = style.direction === 'rtl';
  const pill = button.cloneNode() as HTMLElement;
  pill.style.cssText = button.style.cssText;
  pill.classList.add(styles.followupMorphPill);
  pill.removeAttribute('data-agent-followup-id');
  pill.tabIndex = -1;

  return {
    button,
    start: {
      frame: toMotionRect(frame),
      titleOffset: {
        x: isRtl ? frame.right - titleRect.right : titleRect.left - frame.left,
        y: titleRect.top - frame.top,
      },
      titleFontSize: parseFloat(getComputedStyle(label).fontSize),
      radius: Math.min(parseFloat(style.borderTopLeftRadius) || 0, frame.height / 2, frame.width / 2),
    },
    pill,
    title: createTextPicture(label, titleRect.width, styles.followupMorphText),
    isRtl,
    time: Date.now(),
  };
}

/**
 * The suggestions beside the tapped one leave as a ripple away from the finger, the nearest first: each fades out with
 * a slight blur, shrinking a little toward its own centre. Pictures of them leave in the chat's motion `layer`, while
 * they themselves go out of sight at once, so the list closes up under the pictures as it would, and a suggestion
 * still there once its picture has gone, as when the question did not go, shows again. It reads the layout, so it is
 * called in a measure phase.
 */
export function rippleFollowupsAway(tapped: HTMLElement, layer: HTMLElement) {
  const row = tapped.parentElement;
  if (!row || !tapped.animate) return;

  const layerRect = layer.getBoundingClientRect();
  const followups = Array.from(row.children)
    .filter((button): button is HTMLElement => button instanceof HTMLElement && button !== tapped)
    .map((button) => ({ button, rect: button.getBoundingClientRect() }))
    .filter(({ button, rect }) => rect.width && rect.height && getComputedStyle(button).visibility !== 'hidden');
  const order = getRippleOrder(followups.map(({ rect }) => rect), tapped.getBoundingClientRect());

  requestMutation(() => {
    order.forEach((index, rank) => {
      const { button, rect } = followups[index];
      const picture = createButtonPicture(button);
      picture.classList.add(styles.followupRipplePicture);
      picture.style.left = `${rect.left - layerRect.left}px`;
      picture.style.top = `${rect.top - layerRect.top}px`;
      picture.style.width = `${rect.width}px`;
      picture.style.height = `${rect.height}px`;
      layer.appendChild(picture);
      button.style.visibility = 'hidden';

      const animation = picture.animate([
        { opacity: 1, transform: 'none', filter: 'none' },
        { opacity: 0, transform: `scale(${RIPPLE_END_SCALE})`, filter: `blur(${RIPPLE_BLUR}px)` },
      ], {
        duration: RIPPLE_DURATION, delay: rank * RIPPLE_STAGGER, easing: 'ease-out', fill: 'both',
      });
      animation.onfinish = () => {
        requestMutation(() => {
          picture.remove();
          button.style.removeProperty('visibility');
        });
      };
    });
  });
}

/**
 * The order in which the suggestions at `rects` leave the one tapped at `tapped`: the nearest first, by their centres
 */
export function getRippleOrder(rects: MotionRect[], tapped: MotionRect) {
  const center = getRectCenter(tapped);
  const distances = rects.map((rect) => {
    const { x, y } = getRectCenter(rect);
    return Math.hypot(x - center.x, y - center.y);
  });

  return rects.map((_, index) => index).sort((a, b) => distances[a] - distances[b]);
}

/**
 * The tapped suggestion turns into its question's bubble, as on iOS: the pill's frame, corners and glassy fill become
 * the bubble's body, corners and colour, and its title moves onto the bubble's `text`, scaling with it from the title's
 * size to the text's, as the one fades into the other. Each goes out of focus as it fades, so the two never show sharp
 * together, wherever their lines break. Once the fill is the bubble's, the bubble's tail grows out of its corner. The
 * morph follows the bubble wherever the list shows it meanwhile, which `getBubble` finds again whenever the bubble
 * found has left the document, and the bubble stays out of sight until the morph ends and the bubble takes its place at
 * once, and `onEnd` follows.
 *
 * It reads the layout, so it is called in a measure phase, and returns the morph to start in a mutation, which returns
 * what ends it where it stands. A source that is too old or a bubble without its text has no morph.
 */
export function measureFollowupMorph(
  source: FollowupSource,
  bubble: HTMLElement,
  text: HTMLElement,
  getBubble: () => HTMLElement | undefined,
  layer: HTMLElement,
  onEnd?: NoneToVoidFunction,
) {
  const body = bubble.getBoundingClientRect();
  const textRect = text.getBoundingClientRect();
  if (Date.now() - source.time > SOURCE_LIFETIME || body.width < 1 || textRect.width < 1 || !layer.animate) {
    return undefined;
  }

  const {
    start, pill, title, isRtl, button,
  } = source;
  const bubbleStyle = getComputedStyle(bubble);
  const tailStyle = getComputedStyle(bubble, '::after');
  const tailWidth = parseFloat(tailStyle.width) || 0;
  // The text's lines start at the top of the bubble's content, which is where its picture's lines start too
  let target: FollowupMorphTarget = {
    frame: toMotionRect(body),
    textOffset: {
      x: isRtl ? body.right - textRect.right : textRect.left - body.left,
      y: (parseFloat(bubbleStyle.borderTopWidth) || 0) + (parseFloat(bubbleStyle.paddingTop) || 0),
    },
    fontSize: parseFloat(getComputedStyle(text).fontSize),
    radii: getBorderRadii(bubbleStyle).map((radius) => parseFloat(radius) || 0),
  };
  let layerRect = layer.getBoundingClientRect();
  const findBubble = cacheWhileConnected(getBubble);

  const textPicture = createTextPicture(text, textRect.width, styles.followupMorphText);
  const morph = document.createElement('div');
  morph.className = styles.followupMorph;
  const background = document.createElement('div');
  background.className = styles.followupMorphBackground;
  const fill = document.createElement('div');
  fill.className = styles.followupMorphFill;
  fill.style.backgroundColor = bubbleStyle.backgroundColor;
  const tail = document.createElement('div');
  tail.className = styles.followupMorphTail;
  tail.style.width = `${tailWidth}px`;
  tail.style.height = tailStyle.height;
  tail.style.backgroundColor = tailStyle.backgroundColor;
  tail.style.setProperty('mask-image', tailStyle.getPropertyValue('mask-image'));
  tail.style.setProperty('-webkit-mask-image', tailStyle.getPropertyValue('-webkit-mask-image'));
  // The tail hangs off the bubble's end, from the body's bottom corner, which it grows out of
  tail.style.setProperty(isRtl ? 'left' : 'right', `${-tailWidth}px`);
  tail.style.transformOrigin = isRtl ? '100% 100%' : '0 100%';
  title.style.transformOrigin = isRtl ? '100% 0' : '0 0';
  textPicture.style.transformOrigin = title.style.transformOrigin;
  background.append(pill, fill);
  morph.append(background, tail, title, textPicture);

  function showState(state: FollowupMorphState) {
    const { frame } = state;
    morph.style.transform = `translate(${frame.left - layerRect.left}px, ${frame.top - layerRect.top}px)`;
    morph.style.width = `${frame.width}px`;
    morph.style.height = `${frame.height}px`;
    background.style.borderRadius = state.radii.map((radius) => `${radius}px`).join(' ');
    pill.style.opacity = String(state.pillOpacity);
    fill.style.opacity = String(state.fillOpacity);
    placeText(title, state.titleScale, state.titleOpacity, state.titleBlur);
    placeText(textPicture, state.textScale, state.textOpacity, state.textBlur);
    tail.style.visibility = state.tailScale === undefined ? 'hidden' : 'visible';
    tail.style.transform = `scale(${state.tailScale ?? TAIL_COLLAPSED_SCALE})`;

    function placeText(element: HTMLElement, scale: number, opacity: number, blur: number) {
      element.style.setProperty(isRtl ? 'right' : 'left', `${state.textOffset.x}px`);
      element.style.top = `${state.textOffset.y}px`;
      element.style.transform = `scale(${scale})`;
      element.style.opacity = String(opacity);
      element.style.filter = blur ? `blur(${blur}px)` : 'none';
    }
  }

  return () => {
    let isFinished = false;
    let startedAt: number | undefined;
    let hiddenBubble: HTMLElement | undefined;

    function hideBubble(element: HTMLElement) {
      if (hiddenBubble === element) return;

      hiddenBubble?.style.removeProperty('opacity');
      hiddenBubble = element;
      element.style.opacity = '0';
    }

    // The real bubble takes over at the end, at once: two translucent bubbles would show lighter than either
    function finish() {
      if (isFinished) return;

      isFinished = true;
      requestMutation(() => {
        morph.remove();
        hiddenBubble?.style.removeProperty('opacity');
        button.style.removeProperty('visibility');
        onEnd?.();
      });
    }

    showState(getFollowupMorphState(start, target, 0));
    layer.appendChild(morph);
    hideBubble(bubble);
    // The tapped suggestion goes out of sight under its morph, which shows its glass in its place
    button.style.visibility = 'hidden';

    animate(() => {
      if (isFinished) return false;

      // The morph's time starts with its first frame on screen, so a busy frame as the question goes in keeps it whole
      const now = Date.now();
      startedAt ??= now;
      const fraction = Math.min(1, (now - startedAt) / FOLLOWUP_MORPH_DURATION);
      const shownBubble = findBubble();
      const shownBody = shownBubble?.getBoundingClientRect();
      if (shownBody && shownBody.width >= 1 && shownBody.height >= 1) {
        target = { ...target, frame: toMotionRect(shownBody) };
      }
      layerRect = layer.getBoundingClientRect();
      const state = getFollowupMorphState(start, target, getTelegramProgress(fraction));

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

/** The morph as it stands `progress` of the way, on its curve, into the bubble */
export function getFollowupMorphState(
  start: FollowupMorphStart,
  target: FollowupMorphTarget,
  progress: number,
): FollowupMorphState {
  const frame = interpolateRect(start.frame, target.frame, progress);
  // The title and the text stand on one point, scaled alike, so the one fades into the other in place
  const shift = getShare(progress, CROSSFADE_START, CROSSFADE_END);
  const textScale = target.fontSize / start.titleFontSize;
  const titleScale = lerp(1, textScale, progress);
  const tailGrowth = getShare(progress, TAIL_GROWTH_START, TAIL_GROWTH_END);

  return {
    frame,
    radii: target.radii.map((radius) => Math.min(lerp(start.radius, radius, progress), frame.height / 2)),
    textOffset: {
      x: lerp(start.titleOffset.x, target.textOffset.x, progress),
      y: lerp(start.titleOffset.y, target.textOffset.y, progress),
    },
    titleScale,
    textScale: titleScale / textScale,
    pillOpacity: 1 - shift,
    fillOpacity: shift,
    titleOpacity: 1 - shift,
    textOpacity: shift,
    // Halfway through, both are as much out of focus, and by its end the text is sharp
    titleBlur: FOLLOWUP_MORPH_BLUR * shift,
    textBlur: FOLLOWUP_MORPH_BLUR * (1 - shift),
    tailScale: tailGrowth > 0 ? lerp(TAIL_COLLAPSED_SCALE, 1, tailGrowth) : undefined,
  };
}

// A copy of the suggestion as it shows, without its entrance and out of the reach of the keyboard and of selectors
function createButtonPicture(button: HTMLElement) {
  const picture = button.cloneNode(true) as HTMLElement;
  picture.style.cssText = button.style.cssText;
  picture.removeAttribute('data-agent-followup-id');
  picture.tabIndex = -1;
  return picture;
}

function toMotionRect({
  left, top, width, height,
}: DOMRect): MotionRect {
  return {
    left, top, width, height,
  };
}
