import type { RefObject } from '../../../lib/teact/teact';

import type { TextRevealPhase } from '../../../util/agent/TextRevealController';

const HEIGHT_SMOOTHING_TAU_SECONDS = 0.14;
const HEIGHT_FRAME_DELTA_CAP_SECONDS = 0.05;
const HEIGHT_SETTLE_THRESHOLD_PX = 0.5;

export interface HeightAnimationState {
  displayedHeight: number;
  targetHeight: number;
  lastFrameTime?: number;
  shouldReleaseWhenSettled: boolean;
}

interface HeightAnimationFrame {
  animation: HeightAnimationState;
  sourceDisplayedHeight: number;
  sourceLastFrameTime?: number;
  displayedHeight: number;
  hasHeightChanged: boolean;
  lastFrameTime: number;
  shouldReset: boolean;
  targetHeight: number;
  shouldReleaseWhenSettled: boolean;
}

export function applyHeightAnimationTarget(
  container: HTMLElement,
  targetHeight: number,
  shouldAnimate: boolean,
  phase: TextRevealPhase,
  animationRef: RefObject<HeightAnimationState | undefined>,
) {
  if (!shouldAnimate) {
    resetHeightAnimation(container, animationRef);
    return false;
  }

  const animation = animationRef.current;

  if (!animation) {
    if (phase === 'complete') {
      resetHeightAnimation(container, animationRef);
      return false;
    }

    container.style.height = `${targetHeight}px`;
    animationRef.current = {
      displayedHeight: targetHeight,
      targetHeight,
      shouldReleaseWhenSettled: false,
    };
    return false;
  }

  if (animation.displayedHeight === 0 && targetHeight > 0) {
    animation.displayedHeight = targetHeight;
  }

  animation.targetHeight = targetHeight;
  animation.shouldReleaseWhenSettled = phase === 'complete';

  if (Math.abs(animation.targetHeight - animation.displayedHeight) >= HEIGHT_SETTLE_THRESHOLD_PX) {
    return true;
  }

  animation.displayedHeight = animation.targetHeight;
  container.style.height = `${animation.targetHeight}px`;
  if (animation.shouldReleaseWhenSettled) {
    resetHeightAnimation(container, animationRef);
  }

  return false;
}

export function getHeightAnimationFrame(
  animationRef: RefObject<HeightAnimationState | undefined>,
  now: number,
): HeightAnimationFrame | undefined {
  const animation = animationRef.current;
  if (!animation) return undefined;

  const sourceDisplayedHeight = animation.displayedHeight;
  const sourceLastFrameTime = animation.lastFrameTime;
  const frameDelta = Math.max(
    0,
    Math.min(now - (sourceLastFrameTime ?? now), HEIGHT_FRAME_DELTA_CAP_SECONDS),
  );
  const smoothing = Math.min(1, frameDelta / HEIGHT_SMOOTHING_TAU_SECONDS);
  let displayedHeight = sourceDisplayedHeight
    + (animation.targetHeight - sourceDisplayedHeight) * smoothing;

  if (Math.abs(animation.targetHeight - displayedHeight) < HEIGHT_SETTLE_THRESHOLD_PX) {
    displayedHeight = animation.targetHeight;
  }

  return {
    animation,
    sourceDisplayedHeight,
    sourceLastFrameTime,
    displayedHeight,
    hasHeightChanged: displayedHeight !== sourceDisplayedHeight,
    lastFrameTime: now,
    shouldReset: displayedHeight === animation.targetHeight
      && animation.shouldReleaseWhenSettled,
    targetHeight: animation.targetHeight,
    shouldReleaseWhenSettled: animation.shouldReleaseWhenSettled,
  };
}

export function commitHeightAnimationFrame(
  container: HTMLElement,
  animationRef: RefObject<HeightAnimationState | undefined>,
  frame: HeightAnimationFrame,
) {
  if (
    animationRef.current !== frame.animation
    || frame.animation.displayedHeight !== frame.sourceDisplayedHeight
    || frame.animation.lastFrameTime !== frame.sourceLastFrameTime
    || frame.animation.targetHeight !== frame.targetHeight
    || frame.animation.shouldReleaseWhenSettled !== frame.shouldReleaseWhenSettled
  ) {
    return false;
  }

  frame.animation.displayedHeight = frame.displayedHeight;
  frame.animation.lastFrameTime = frame.lastFrameTime;
  container.style.height = `${frame.displayedHeight}px`;
  if (frame.shouldReset) {
    resetHeightAnimation(container, animationRef);
  }
  return true;
}

export function resetHeightAnimation(
  container: HTMLElement,
  animationRef: RefObject<HeightAnimationState | undefined>,
) {
  animationRef.current = undefined;
  container.style.removeProperty('height');
}

export function getIsHeightAnimationActive(animation?: HeightAnimationState) {
  return Boolean(
    animation
    && Math.abs(animation.targetHeight - animation.displayedHeight) >= HEIGHT_SETTLE_THRESHOLD_PX,
  );
}
