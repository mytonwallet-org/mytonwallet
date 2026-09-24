import { type ElementRef, useEffect } from '../lib/teact/teact';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { animate } from '../util/animation';
import { clamp, round } from '../util/math';
import { IS_TOUCH_ENV } from '../util/windowEnvironment';

interface OwnProps {
  cardRef: ElementRef<HTMLElement>;
  isDisabled?: boolean;
}

/** The spring advances in 60 Hz steps so its speed stays the same on faster displays */
const FRAME_MS = 1000 / 60;
/** Limit the work after an inactive tab resumes so the card does not replay missed frames */
const MAX_CATCH_UP_MS = 100;

/** A stronger spring keeps the card close to the current input position */
const FOLLOW_STIFFNESS = 0.066;
const FOLLOW_DAMPING = 0.25;
/** A softer spring lets the card drift back to center after input ends */
const RELEASE_STIFFNESS = 0.01;
const RELEASE_DAMPING = 0.06;

const REST_THRESHOLD = 0.0002;

const CENTER = 0.5;

/** Ignore small finger movements so a tap can tilt the card without being treated as a drag */
const TOUCH_GESTURE_THRESHOLD_PX = 8;

interface Spring {
  value: number;
  target: number;
  velocity: number;
}

export default function useCardTilt({ cardRef, isDisabled }: OwnProps) {
  useEffect(() => {
    const card = cardRef.current;
    if (!card || isDisabled) {
      return undefined;
    }

    const pointerX = createSpring(CENTER);
    const pointerY = createSpring(CENTER);
    const glow = createSpring(0);

    let isCancelled = false;
    let isFollowing = false;
    let isAnimating = false;
    let lastFrameAt = 0;
    let leftoverMs = 0;

    function render() {
      if (isCancelled) return;

      card!.style.setProperty('--card-pointer-x', String(round(pointerX.value, 4)));
      card!.style.setProperty('--card-pointer-y', String(round(pointerY.value, 4)));
      card!.style.setProperty('--card-glow-opacity', String(round(glow.value, 4)));
      card!.style.setProperty('--card-press', isFollowing ? '1' : '0');
    }

    function tick() {
      if (isCancelled) {
        isAnimating = false;
        return false;
      }

      const now = performance.now();
      const elapsed = Math.min(now - lastFrameAt, MAX_CATCH_UP_MS) + leftoverMs;
      lastFrameAt = now;

      const steps = Math.floor(elapsed / FRAME_MS);
      leftoverMs = elapsed - (steps * FRAME_MS);

      const stiffness = isFollowing ? FOLLOW_STIFFNESS : RELEASE_STIFFNESS;
      const damping = isFollowing ? FOLLOW_DAMPING : RELEASE_DAMPING;

      for (let i = 0; i < steps; i++) {
        stepSpring(pointerX, stiffness, damping);
        stepSpring(pointerY, stiffness, damping);
        stepSpring(glow, stiffness, damping);
      }

      const isAtRest = isSpringAtRest(pointerX) && isSpringAtRest(pointerY) && isSpringAtRest(glow);
      if (isAtRest) {
        settleSpring(pointerX);
        settleSpring(pointerY);
        settleSpring(glow);
        isAnimating = false;
      }

      // `animate` runs in `fasterdom`'s measure phase, where style writes are disallowed.
      // Schedule them for the mutation phase of the same frame.
      requestMutation(render);

      return !isAtRest;
    }

    function startAnimation() {
      if (isAnimating) return;

      isAnimating = true;
      lastFrameAt = performance.now();
      leftoverMs = 0;
      animate(tick, requestMeasure);
    }

    function setTarget(x: number, y: number) {
      isFollowing = true;
      pointerX.target = x;
      pointerY.target = y;
      glow.target = 1;
      startAnimation();
    }

    function release() {
      isTracking = false;
      isFollowing = false;
      pointerX.target = CENTER;
      pointerY.target = CENTER;
      glow.target = 0;
      startAnimation();
    }

    function reset() {
      isCancelled = true;
      requestMutation(() => {
        card!.style.removeProperty('--card-pointer-x');
        card!.style.removeProperty('--card-pointer-y');
        card!.style.removeProperty('--card-glow-opacity');
        card!.style.removeProperty('--card-press');
      });
    }

    let pendingClientX = 0;
    let pendingClientY = 0;
    let isMeasureScheduled = false;
    let isTracking = false;

    function followPoint(clientX: number, clientY: number) {
      isTracking = true;
      pendingClientX = clientX;
      pendingClientY = clientY;
      if (isMeasureScheduled) return;

      // Mouse and touch events can fire many times per frame. Measuring the card once per frame
      // avoids forced layout on every move.
      isMeasureScheduled = true;
      requestMeasure(() => {
        isMeasureScheduled = false;
        // The pointer may have left between the event and this frame, and no later event would
        // bring the card back
        if (isCancelled || !isTracking) return;

        const { left, top, width, height } = card!.getBoundingClientRect();
        if (!width || !height) return;

        setTarget(
          clamp((pendingClientX - left) / width, 0, 1),
          clamp((pendingClientY - top) / height, 0, 1),
        );
      });
    }

    if (!IS_TOUCH_ENV) {
      const handleMouseMove = (e: MouseEvent) => followPoint(e.clientX, e.clientY);

      card.addEventListener('mousemove', handleMouseMove);
      card.addEventListener('mouseleave', release);

      return () => {
        reset();
        card.removeEventListener('mousemove', handleMouseMove);
        card.removeEventListener('mouseleave', release);
      };
    }

    let touchStartX = 0;
    let touchStartY = 0;
    let isTouching = false;
    let isTouchDirectionKnown = false;

    function endTouch() {
      if (!isTouching) return;

      isTouching = false;
      release();
    }

    function handleTouchStart(e: TouchEvent) {
      const touch = e.touches[0];
      if (!touch) return;

      touchStartX = touch.clientX;
      touchStartY = touch.clientY;
      isTouching = true;
      isTouchDirectionKnown = false;
      followPoint(touch.clientX, touch.clientY);
    }

    function handleTouchMove(e: TouchEvent) {
      const touch = e.touches[0];
      if (!touch || !isTouching) return;

      if (!isTouchDirectionKnown) {
        const travelX = Math.abs(touch.clientX - touchStartX);
        const travelY = Math.abs(touch.clientY - touchStartY);
        if (Math.max(travelX, travelY) < TOUCH_GESTURE_THRESHOLD_PX) return;

        isTouchDirectionKnown = true;
        // A mostly vertical drag scrolls the page, so the card returns to center instead of following the finger
        if (travelY > travelX) {
          endTouch();
          return;
        }
      }

      followPoint(touch.clientX, touch.clientY);
    }

    // Passive touch listeners let the page scroll normally while the card tracks the finger
    card.addEventListener('touchstart', handleTouchStart, { passive: true });
    card.addEventListener('touchmove', handleTouchMove, { passive: true });
    card.addEventListener('touchend', endTouch, { passive: true });
    card.addEventListener('touchcancel', endTouch, { passive: true });

    return () => {
      reset();
      card.removeEventListener('touchstart', handleTouchStart);
      card.removeEventListener('touchmove', handleTouchMove);
      card.removeEventListener('touchend', endTouch);
      card.removeEventListener('touchcancel', endTouch);
    };
  }, [cardRef, isDisabled]);
}

function createSpring(value: number): Spring {
  return { value, target: value, velocity: 0 };
}

function stepSpring(spring: Spring, stiffness: number, damping: number) {
  spring.velocity = (spring.velocity + ((spring.target - spring.value) * stiffness)) * (1 - damping);
  spring.value += spring.velocity;
}

function isSpringAtRest(spring: Spring) {
  return Math.abs(spring.target - spring.value) <= REST_THRESHOLD && Math.abs(spring.velocity) <= REST_THRESHOLD;
}

function settleSpring(spring: Spring) {
  spring.value = spring.target;
  spring.velocity = 0;
}
