import { setExtraStyles } from '../lib/teact/teact-dom';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { animateSingle, cancelSingleAnimation } from './animation';

type GetTargetScrollTop = (container: HTMLElement) => number;

export interface AnimateScrollOptions {
  maxDistance?: number;
  forceDuration?: number;
  onEnd?: NoneToVoidFunction;
}

const MIN_DURATION = 300;
const MAX_DURATION = 600;
const MAX_DISTANCE = 800;
const SHORT_TRANSITION_MAX_DISTANCE = 300;

let activeContainer: HTMLElement | undefined;
let activeGetTargetScrollTop: GetTargetScrollTop | undefined;
let activeOptions: AnimateScrollOptions | undefined;
let activeEndAt: number | undefined;

/**
 * Measures `container` and returns a mutation that scrolls it to the position returned by `getTargetScrollTop`.
 * Call it in a measure phase and run the returned function in a mutation phase.
 *
 * The duration grows with the distance, from 300 ms up to 600 ms at 800 px. When the distance exceeds
 * `maxDistance`, the scroll first jumps so that only the last `maxDistance` pixels are animated.
 *
 * `onEnd` runs once the target is reached, instantly or animated. It does not run when the animation
 * is cancelled or replaced by another one.
 */
export default function animateScroll(
  container: HTMLElement,
  getTargetScrollTop: GetTargetScrollTop,
  options: AnimateScrollOptions = {},
): NoneToVoidFunction {
  return createScrollAnimation(container, getTargetScrollTop, options);
}

function createScrollAnimation(
  container: HTMLElement,
  getTargetScrollTop: GetTargetScrollTop,
  options: AnimateScrollOptions,
  endAt?: number,
): NoneToVoidFunction {
  const { maxDistance = MAX_DISTANCE, forceDuration, onEnd } = options;
  const { scrollTop, scrollHeight, clientHeight } = container;
  const maxScrollTop = Math.max(0, scrollHeight - clientHeight);
  const target = Math.round(Math.min(Math.max(getTargetScrollTop(container), 0), maxScrollTop));
  const offset = target - scrollTop;
  const scrollFrom = Math.abs(offset) > maxDistance ? target - Math.sign(offset) * maxDistance : scrollTop;
  const path = target - scrollFrom;
  const absPath = Math.abs(path);
  const remainingDuration = endAt !== undefined ? Math.max(endAt - Date.now(), 0) : undefined;

  return () => {
    if (absPath < 1 || forceDuration === 0 || remainingDuration === 0) {
      if (activeContainer === container) {
        cancelScrollAnimation();
      }
      if (scrollTop !== target) {
        setExtraStyles(container, { scrollBehavior: 'auto' });
        container.scrollTop = target;
        setExtraStyles(container, { scrollBehavior: '' });
      }
      onEnd?.();
      return;
    }

    const transition = absPath <= SHORT_TRANSITION_MAX_DISTANCE ? shortTransition : longTransition;
    const duration = remainingDuration
      ?? forceDuration
      ?? MIN_DURATION + (absPath / MAX_DISTANCE) * (MAX_DURATION - MIN_DURATION);
    const startAt = Date.now();

    if (activeContainer && activeContainer !== container) {
      setExtraStyles(activeContainer, { scrollBehavior: '' });
    }

    activeContainer = container;
    activeGetTargetScrollTop = getTargetScrollTop;
    activeOptions = options;
    activeEndAt = endAt ?? startAt + duration;
    // Scroll containers may have `scroll-behavior: smooth`, which would smear every frame into its own smooth scroll
    setExtraStyles(container, { scrollBehavior: 'auto' });

    animateSingle(() => {
      const t = Math.min((Date.now() - startAt) / duration, 1);
      const currentScrollTop = Math.round(target - path * (1 - transition(t)));
      container.scrollTop = currentScrollTop;

      const isRunning = t < 1 && currentScrollTop !== target;
      if (!isRunning) {
        resetActiveAnimation();
        onEnd?.();
      }

      return isRunning;
    }, requestMutation);
  };
}

export function isAnimatingScroll(container?: HTMLElement) {
  return Boolean(container) && activeContainer === container;
}

/**
 * Re-measures the running animation's target and continues towards it from the current position.
 * Content that grows or shrinks during the animation would otherwise leave it ending at a stale position.
 *
 * The animation keeps the end time it started with. Growing content can re-aim it on every frame, and
 * restarting the clock each time would turn it into an endless chase of the moving target.
 */
export function restartScrollAnimation() {
  const container = activeContainer;
  const getTargetScrollTop = activeGetTargetScrollTop;
  const options = activeOptions;
  const endAt = activeEndAt;
  if (!container || !getTargetScrollTop) return;

  requestMeasure(() => {
    if (activeContainer !== container) return;

    const mutate = createScrollAnimation(container, getTargetScrollTop, options!, endAt);
    requestMutation(() => {
      if (activeContainer === container) mutate();
    });
  });
}

export function cancelScrollAnimation() {
  cancelSingleAnimation();
  resetActiveAnimation();
}

function resetActiveAnimation() {
  if (activeContainer) {
    setExtraStyles(activeContainer, { scrollBehavior: '' });
  }

  activeContainer = undefined;
  activeGetTargetScrollTop = undefined;
  activeOptions = undefined;
  activeEndAt = undefined;
}

function shortTransition(t: number) {
  return 1 - ((1 - t) ** 3.5);
}

function longTransition(t: number) {
  return 1 - ((1 - t) ** 6);
}
