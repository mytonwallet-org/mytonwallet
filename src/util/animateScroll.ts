import { setExtraStyles } from '../lib/teact/teact-dom';

import { getPhase, requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { animateSingle, cancelSingleAnimation } from './animation';

type GetTargetScrollTop = (container: HTMLElement) => number;

export interface AnimateScrollOptions {
  maxDistance?: number;
  forceDuration?: number;
  // A curve in place of the one picked by distance. A re-aimed animation keeps its start and its progress along it,
  // so a curve that starts at rest does not start again from rest.
  transition?: (t: number) => number;
  // A jump (`forceDuration: 0`) that the user asks for, as with the scroll button, can land in the fling or the
  // trackpad's inertia of their earlier swipe. It then waits for that momentum and holds the target against it, as the
  // end of an animated scroll does.
  shouldWaitForMomentum?: boolean;
  onEnd?: NoneToVoidFunction;
}

interface ScrollAnimationTiming {
  startAt: number;
  endAt: number;
  scrollFrom: number;
}

const MIN_DURATION = 300;
const MAX_DURATION = 600;
const MAX_DISTANCE = 800;
const SHORT_TRANSITION_MAX_DISTANCE = 300;
// A fling, or a trackpad's inertia, goes on moving the container after the animation reaches its target. The target is
// held until the container has not moved on its own for this long, and for no longer than the maximum.
const MOMENTUM_IDLE_DURATION = 120;
const MAX_HOLD_DURATION = 2000;
// A trackpad's inertial wheel events come at short intervals and die down, while a new swipe follows a pause or speeds up
const WHEEL_TRAIN_MAX_GAP = 100;
const WHEEL_TRAIN_MAX_GROWTH = 1.25;

interface WheelTrain {
  // `lastAt` is when the last event was handled, and `timeStamp` is when it was made. A busy page can handle an event
  // well after it was made.
  lastAt: number;
  timeStamp: number;
  deltaY: number;
  isLeftover: boolean;
}

let activeContainer: HTMLElement | undefined;
let activeGetTargetScrollTop: GetTargetScrollTop | undefined;
let activeOptions: AnimateScrollOptions | undefined;
let activeTiming: ScrollAnimationTiming | undefined;
// When the animation of `activeContainer` was asked for, which re-aiming it does not change
let activeStartedAt = 0;
let activeWrittenScrollTop: number | undefined;
// When the container last moved without the animation moving it
let activeMovedAt = 0;
let isHoldingTarget = false;
let holdStartedAt = 0;
let holdTimer: number | undefined;
let watchedContainer: HTMLElement | undefined;
const wheelTrains = new WeakMap<HTMLElement, WheelTrain>();

/**
 * Measures `container` and returns a mutation that scrolls it to the position returned by `getTargetScrollTop`.
 * Call it in a measure phase and run the returned function in a mutation phase.
 *
 * The duration grows with the distance, from 300 ms up to 600 ms at 800 px. When the distance exceeds
 * `maxDistance`, the scroll first jumps so that only the last `maxDistance` pixels are animated.
 *
 * `onEnd` runs once the target is reached, instantly or animated. It does not run when the animation
 * is cancelled or replaced by another one.
 *
 * A fling or a trackpad's inertia from before the animation goes on moving the container under it. An animated scroll
 * stays at its target until that momentum dies down, and counts as running meanwhile; `cancelScrollAnimation` lets go.
 * A jump with `forceDuration: 0` and `shouldWaitForMomentum` holds its target the same way, and counts as running
 * until the container has rested at it.
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
  timing?: ScrollAnimationTiming,
): NoneToVoidFunction {
  const {
    maxDistance = MAX_DISTANCE, forceDuration, transition: customTransition, shouldWaitForMomentum, onEnd,
  } = options;
  const { scrollTop, scrollHeight, clientHeight } = container;
  const maxScrollTop = Math.max(0, scrollHeight - clientHeight);
  const target = Math.round(Math.min(Math.max(getTargetScrollTop(container), 0), maxScrollTop));
  const offset = target - scrollTop;
  const resumedTiming = customTransition ? timing : undefined;
  const scrollFrom = resumedTiming?.scrollFrom
    ?? (Math.abs(offset) > maxDistance ? target - Math.sign(offset) * maxDistance : scrollTop);
  const path = target - scrollFrom;
  const absPath = Math.abs(path);
  const remainingDuration = timing ? Math.max(timing.endAt - Date.now(), 0) : undefined;

  return () => {
    if (absPath < 1 || forceDuration === 0 || remainingDuration === 0) {
      // A jump in place of an animation may land in a fling, and a re-aimed animation that runs out may still be in one
      const isJump = forceDuration === 0 && !timing && Boolean(shouldWaitForMomentum);
      const isRunningOut = activeContainer === container && Date.now() - activeMovedAt < MOMENTUM_IDLE_DURATION;
      if (isJump || isRunningOut) {
        cancelSingleAnimation();
        setExtraStyles(container, { scrollBehavior: 'auto' });
        container.scrollTop = target;
        holdAfterJump(container, getTargetScrollTop, options, target, isJump);
        onEnd?.();
        return;
      }

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

    const transition = customTransition
      ?? (absPath <= SHORT_TRANSITION_MAX_DISTANCE ? shortTransition : longTransition);
    const startAt = resumedTiming?.startAt ?? Date.now();
    const duration = resumedTiming ? resumedTiming.endAt - resumedTiming.startAt : (
      remainingDuration ?? forceDuration ?? MIN_DURATION + (absPath / MAX_DISTANCE) * (MAX_DURATION - MIN_DURATION)
    );

    if (activeContainer && activeContainer !== container) {
      setExtraStyles(activeContainer, { scrollBehavior: '' });
    }

    if (!timing || activeContainer !== container) {
      activeStartedAt = Date.now();
      activeMovedAt = 0;
    }
    stopHoldingTarget();
    activeContainer = container;
    activeGetTargetScrollTop = getTargetScrollTop;
    activeOptions = options;
    activeTiming = { startAt, endAt: timing?.endAt ?? startAt + duration, scrollFrom };
    activeWrittenScrollTop = scrollTop;
    watchMomentum(container);
    // Scroll containers may have `scroll-behavior: smooth`, which would smear every frame into its own smooth scroll
    setExtraStyles(container, { scrollBehavior: 'auto' });

    animateSingle(() => {
      const t = Math.min((Date.now() - startAt) / duration, 1);
      const currentScrollTop = Math.round(target - path * (1 - transition(t)));
      container.scrollTop = currentScrollTop;
      activeWrittenScrollTop = currentScrollTop;

      const isRunning = t < 1 && currentScrollTop !== target;
      if (!isRunning) {
        if (Date.now() - activeMovedAt < MOMENTUM_IDLE_DURATION) {
          startHoldingTarget(container);
        } else {
          resetActiveAnimation();
        }
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
  const timing = activeTiming;
  if (!container || !getTargetScrollTop) return;

  if (isHoldingTarget) {
    holdTarget(container);
    return;
  }

  requestMeasure(() => {
    if (activeContainer !== container) return;

    const mutate = createScrollAnimation(container, getTargetScrollTop, options!, timing);
    requestMutation(() => {
      if (activeContainer === container) mutate();
    });
  });
}

export function cancelScrollAnimation() {
  cancelSingleAnimation();
  resetActiveAnimation();
}

/**
 * Records a wheel event on `container` and returns whether it only carries on the inertia of a swipe made before the
 * running scroll animation of `container` started, as a trackpad goes on sending events once the fingers leave it.
 * Such events do not stop the animation. Call it for every wheel event on the container, so that it knows the swipe
 * that each event belongs to.
 */
export function trackWheelInertia(container: HTMLElement, e: WheelEvent) {
  const now = Date.now();
  const train = wheelTrains.get(container);
  const isLeftover = train !== undefined
    && e.timeStamp - train.timeStamp < WHEEL_TRAIN_MAX_GAP
    && Math.sign(e.deltaY) === Math.sign(train.deltaY)
    && Math.abs(e.deltaY) <= Math.abs(train.deltaY) * WHEEL_TRAIN_MAX_GROWTH + 1
    && activeContainer === container
    && (train.isLeftover || train.lastAt <= activeStartedAt);
  wheelTrains.set(container, {
    lastAt: now, timeStamp: e.timeStamp, deltaY: e.deltaY, isLeftover,
  });

  return isLeftover;
}

function watchMomentum(container: HTMLElement) {
  if (watchedContainer === container) return;

  unwatchMomentum();
  watchedContainer = container;
  container.addEventListener('scroll', handleWatchedScroll, { passive: true });
  container.addEventListener('keydown', handleWatchedKeyDown);
}

function unwatchMomentum() {
  watchedContainer?.removeEventListener('scroll', handleWatchedScroll);
  watchedContainer?.removeEventListener('keydown', handleWatchedKeyDown);
  watchedContainer = undefined;
}

function handleWatchedScroll() {
  const container = activeContainer;
  if (!container || container !== watchedContainer || activeWrittenScrollTop === undefined) return;
  if (Math.abs(container.scrollTop - activeWrittenScrollTop) <= 1) return;

  activeMovedAt = Date.now();
  if (isHoldingTarget) holdTarget(container);
}

// Keys scroll the list on their own, which the held target would undo
function handleWatchedKeyDown() {
  if (isHoldingTarget) cancelScrollAnimation();
}

// The jump takes the place of the running animation, and is held as its end would be
function holdAfterJump(
  container: HTMLElement,
  getTargetScrollTop: GetTargetScrollTop,
  options: AnimateScrollOptions,
  target: number,
  isJump: boolean,
) {
  if (activeContainer && activeContainer !== container) resetActiveAnimation();

  stopHoldingTarget();
  activeContainer = container;
  activeGetTargetScrollTop = getTargetScrollTop;
  activeOptions = options;
  activeTiming = undefined;
  activeWrittenScrollTop = target;
  // A jump waits for as long as momentum would take to show itself
  if (isJump) {
    activeStartedAt = Date.now();
    activeMovedAt = activeStartedAt;
  }
  watchMomentum(container);
  startHoldingTarget(container);
}

function startHoldingTarget(container: HTMLElement) {
  isHoldingTarget = true;
  holdStartedAt = Date.now();
  holdTarget(container);
  scheduleHoldCheck();
}

function scheduleHoldCheck() {
  holdTimer = window.setTimeout(() => {
    holdTimer = undefined;
    if (!isHoldingTarget) return;

    const now = Date.now();
    if (now - activeMovedAt >= MOMENTUM_IDLE_DURATION || now - holdStartedAt >= MAX_HOLD_DURATION) {
      const container = activeContainer;
      resetActiveAnimation();
      // The container's listeners pass over its positions while the target is held, and read where it rests now
      container?.dispatchEvent(new Event('scroll'));
      return;
    }

    scheduleHoldCheck();
  }, MOMENTUM_IDLE_DURATION);
}

function holdTarget(container: HTMLElement) {
  requestMeasure(() => {
    if (activeContainer !== container || !isHoldingTarget || !activeGetTargetScrollTop) return;

    const { scrollHeight, clientHeight } = container;
    const maxScrollTop = Math.max(0, scrollHeight - clientHeight);
    const target = Math.round(Math.min(Math.max(activeGetTargetScrollTop(container), 0), maxScrollTop));
    requestMutation(() => {
      if (activeContainer !== container || !isHoldingTarget) return;

      container.scrollTop = target;
      activeWrittenScrollTop = target;
    });
  });
}

function stopHoldingTarget() {
  isHoldingTarget = false;
  if (holdTimer !== undefined) {
    window.clearTimeout(holdTimer);
    holdTimer = undefined;
  }
}

function resetActiveAnimation() {
  if (activeContainer) {
    restoreScrollBehavior(activeContainer);
  }

  stopHoldingTarget();
  unwatchMomentum();
  activeContainer = undefined;
  activeGetTargetScrollTop = undefined;
  activeOptions = undefined;
  activeTiming = undefined;
  activeWrittenScrollTop = undefined;
  activeMovedAt = 0;
}

// A touch or a wheel stops the animation outside the mutation phase, so the style is cleared in the next one.
// A new animation that has taken the container by then keeps its `scroll-behavior`.
function restoreScrollBehavior(container: HTMLElement) {
  if (getPhase() === 'mutate') {
    setExtraStyles(container, { scrollBehavior: '' });
    return;
  }

  requestMutation(() => {
    if (activeContainer !== container) {
      setExtraStyles(container, { scrollBehavior: '' });
    }
  });
}

function shortTransition(t: number) {
  return 1 - ((1 - t) ** 3.5);
}

function longTransition(t: number) {
  return 1 - ((1 - t) ** 6);
}

/** Starts and ends at rest, as the system's ease-in-out */
export function easeInOutTransition(t: number) {
  return (1 - Math.cos(Math.PI * t)) / 2;
}
