import { type ElementRef, useEffect } from '../lib/teact/teact';

import type { CardMotionFrame } from '../util/card/types';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { animate } from '../util/animation';
import { createCardPressTimeline, getCardPressMatrix } from '../util/card/pressMotion';
import { createCardTouchGlow } from '../util/card/touchGlow';
import { vibrate } from '../util/haptics';
import { clamp } from '../util/math';

interface OwnProps {
  cardRef: ElementRef<HTMLElement>;
  rotatorRef: ElementRef<HTMLElement>;
  isDisabled?: boolean;
  onMotionFrame?: (frame: CardMotionFrame) => void;
}

const HOLD_DELAY_MS = 150;
const HOLD_MOVEMENT = 12;
const SCROLL_IDLE_MS = 80;
const INTERACTIVE = 'button, a, input, textarea, select, [role="button"], [role="menuitem"], [contenteditable="true"]';

export default function useCardPress({ cardRef, rotatorRef, isDisabled, onMotionFrame }: OwnProps) {
  useEffect(() => {
    const card = cardRef.current;
    const rotator = rotatorRef.current;
    if (!card || !rotator || isDisabled) return undefined;

    const motion = createCardPressTimeline();
    const glow = createCardTouchGlow();
    let isCancelled = false;
    let isAnimating = false;
    let isReturningToRest = false;
    let previousTime: number | undefined;
    let pointerId: number | undefined;
    let width = 0;
    let pendingX = 0;
    let pendingY = 0;
    let isBeginPending = false;
    let isReleasePending = false;
    let isMeasureScheduled = false;
    const pointerOptions = { passive: true };
    let holdTimer: number | undefined;
    let isHoldCandidate = false;
    let isPlaying = false;
    let shouldSuppressClick = false;
    let startX = 0;
    let startY = 0;
    let lastScrollAt = -Infinity;
    let touchId: number | undefined;
    let capturedPointerId: number | undefined;
    let pointer: readonly [number, number] | undefined;
    let isHovering = false;
    let hoverPointerId: number | undefined;

    function renderPlay() {
      if (isCancelled) return;

      onMotionFrame?.({ press: motion.value, light: glow.light, pointer, isPlaying, isHovering });
    }

    function clearHold() {
      if (holdTimer !== undefined) window.clearTimeout(holdTimer);
      holdTimer = undefined;
      isHoldCandidate = false;

      if (capturedPointerId !== undefined) {
        const id = capturedPointerId;
        capturedPointerId = undefined;
        if (card!.hasPointerCapture?.(id)) card!.releasePointerCapture(id);
      }

      if (isPlaying) {
        isPlaying = false;
        window.removeEventListener('wheel', blockWheel, true);
        requestMutation(renderPlay);
      }
    }

    function startHold(target: EventTarget | null) {
      const control = target instanceof Element ? target.closest(INTERACTIVE) : undefined;

      isHoldCandidate = !(control && card!.contains(control) && !control.hasAttribute('data-card-play-allowed'))
        && performance.now() - lastScrollAt >= SCROLL_IDLE_MS;

      if (!isHoldCandidate) return;

      holdTimer = window.setTimeout(() => {
        holdTimer = undefined;

        if (!isHoldCandidate || pointerId === undefined || isCancelled || document.visibilityState !== 'visible') {
          return;
        }

        isPlaying = true;
        shouldSuppressClick = true;
        window.addEventListener('wheel', blockWheel, { passive: false, capture: true });

        // Capture the pointer only once the hold is confirmed, so ordinary taps and page scrolling work as usual
        try {
          card!.setPointerCapture?.(pointerId);
          capturedPointerId = pointerId;
        } catch {
          // The pointer may already be gone by the time the hold timer fires
        }

        requestMutation(renderPlay);
        vibrate();
      }, HOLD_DELAY_MS);
    }

    function blockWheel(e: WheelEvent) {
      if (isPlaying) e.preventDefault();
    }

    function renderTransform() {
      if (isCancelled) return;

      // The transform goes straight to the rotator, so a frame moves its layer without restyling the card content
      rotator!.style.transform = motion.value.every((v) => v === 0)
        ? 'none' : `matrix3d(${getCardPressMatrix(motion.value, width).join(',')})`;
    }

    function render() {
      if (isCancelled) return;

      renderTransform();

      if (isReturningToRest) return;

      onMotionFrame?.({ press: motion.value, light: glow.light, pointer, isPlaying, isHovering });
    }

    function tick() {
      if (isCancelled) return false;

      const now = performance.now();

      // The first frame counts as 1/60 s, and a long pause such as a background tab counts as at most 0.1 s
      const dt = previousTime === undefined ? 1 / 60 : clamp((now - previousTime) / 1000, 0, 0.1);
      previousTime = now;
      motion.advance(dt);
      if (!isReturningToRest) glow.advance(dt);
      requestMutation(render);
      isAnimating = !motion.isSettled || (!isReturningToRest && !glow.isSettled);
      if (!isAnimating) previousTime = undefined;

      return isAnimating;
    }

    function start() {
      if (isAnimating) return;

      isAnimating = true;
      previousTime = undefined;
      animate(tick, requestMeasure);
    }

    function schedulePoint() {
      if (isMeasureScheduled) return;

      isMeasureScheduled = true;

      requestMeasure(() => {
        isMeasureScheduled = false;

        if (isCancelled || isReturningToRest
          || (!isBeginPending && !isReleasePending && pointerId === undefined && !isHovering)) return;

        const bounds = card!.getBoundingClientRect();
        width = bounds.width;

        if (!width || !bounds.height) return;

        const x = 2 * (pendingX - bounds.left) / width - 1;
        const y = 2 * (pendingY - bounds.top) / bounds.height - 1;

        pointer = pointerId === undefined && !isHovering
          ? undefined : [clamp(x, -1, 1), clamp(y, -1, 1)];

        motion.press(x, y, isBeginPending);
        if (!isReleasePending || isBeginPending) glow.press(x, y, isBeginPending);
        isBeginPending = false;

        // A quick tap can end before this frame, and it still shows a press that is released right away
        if (isReleasePending) {
          isReleasePending = false;
          motion.release();
          glow.release();
        }

        start();
      });
    }

    function handleEnter(e: PointerEvent) {
      if (e.pointerType !== 'mouse' || window.matchMedia?.('(any-hover: hover)').matches === false
        || isHovering || pointerId !== undefined
        || document.visibilityState !== 'visible' || performance.now() - lastScrollAt < SCROLL_IDLE_MS) return;

      isReturningToRest = false;
      isHovering = true;
      hoverPointerId = e.pointerId;
      isPlaying = true;
      pendingX = e.clientX;
      pendingY = e.clientY;
      isBeginPending = true;
      isReleasePending = false;
      requestMutation(renderPlay);
      schedulePoint();
    }

    function handleLeave(e: PointerEvent) {
      if (!isHovering || e.pointerId !== hoverPointerId) return;

      isHovering = false;
      hoverPointerId = undefined;
      pointerId = undefined;
      pointer = undefined;
      clearHold();
      isReleasePending = true;
      glow.release();
      schedulePoint();
    }

    function handleDown(e: PointerEvent) {
      if (!e.isPrimary || e.button !== 0 || pointerId !== undefined || document.visibilityState !== 'visible') return;

      if (e.pointerType === 'mouse') {
        handleEnter(e);

        if (isHovering) {
          pointerId = e.pointerId;
          shouldSuppressClick = false;
          pendingX = e.clientX;
          pendingY = e.clientY;
          schedulePoint();
        }
        return;
      }

      isReturningToRest = false;
      pointerId = e.pointerId;
      shouldSuppressClick = false;
      pendingX = e.clientX;
      pendingY = e.clientY;
      isBeginPending = true;
      isReleasePending = false;
      startX = e.clientX;
      startY = e.clientY;
      startHold(e.target);
      schedulePoint();
    }

    function handleMove(e: PointerEvent) {
      // `handleEnter` skips a mouse that arrives right after a scroll, and `pointerenter` does not fire again
      // while the mouse stays over the card. The next move over the card starts the hover instead.
      if (e.pointerType === 'mouse' && !isHovering && pointerId === undefined
        && e.target instanceof Node && card!.contains(e.target)) handleEnter(e);

      if (e.pointerId !== pointerId && (!isHovering || e.pointerId !== hoverPointerId)) return;

      if (!isPlaying && isHoldCandidate && Math.hypot(e.clientX - startX, e.clientY - startY) > HOLD_MOVEMENT) {
        clearHold();
      }

      // While a finger tilts the card, its moves stop here, as in `handleTouchMove` and `handleMouseMove`,
      // so swipe gestures elsewhere in the app do not react to them
      if (isPlaying && !isHovering) e.stopPropagation();
      pendingX = e.clientX;
      pendingY = e.clientY;
      schedulePoint();
    }

    function handleUp(e: PointerEvent) {
      if (e.pointerId !== pointerId) return;

      pendingX = e.clientX;
      pendingY = e.clientY;
      pointerId = undefined;

      if (isHovering && e.pointerType === 'mouse') {
        schedulePoint();
        return;
      }

      pointer = undefined;
      touchId = undefined;
      clearHold();
      isReleasePending = true;

      // The glow fades out at once, even though the card itself stays pressed for at least 70 ms
      glow.release();
      schedulePoint();
    }

    function interrupt() {
      pointerId = undefined;
      hoverPointerId = undefined;
      isHovering = false;
      pointer = undefined;
      touchId = undefined;
      clearHold();
      isBeginPending = false;
      isReleasePending = false;
      isReturningToRest = false;
      motion.reset();
      glow.reset();
      requestMutation(render);
    }

    function handleCancel(e: PointerEvent) {
      if (e.pointerId !== pointerId && e.pointerId !== hoverPointerId) return;

      pointerId = undefined;
      hoverPointerId = undefined;
      isHovering = false;
      pointer = undefined;
      touchId = undefined;
      clearHold();
      if (isBeginPending) isReleasePending = true;
      else motion.release();
      glow.release();
      start();
    }

    function handleLostCapture(e: PointerEvent) {
      // On touch, the browser first captures the pointer to the touched child. The hold moves the capture
      // to the card, so the child's `lostpointercapture` that bubbles up here is not a cancel.
      if (e.target !== card || card.hasPointerCapture?.(e.pointerId)) return;

      handleCancel(e);
    }

    function handleVisibility() {
      if (document.visibilityState !== 'visible') interrupt();
    }

    function handleScroll(e: Event) {
      // Only scrolling the page or a container of the card stops the press, not a menu scrolling inside it
      if (e.target === document || (e.target instanceof Element && e.target.contains(card!))) {
        lastScrollAt = performance.now();
        releaseInput();
      }
    }

    function releaseInput() {
      if (pointerId === undefined && !isHovering && !isPlaying && !isBeginPending) return;

      pointerId = undefined;
      hoverPointerId = undefined;
      isHovering = false;
      pointer = undefined;
      touchId = undefined;
      clearHold();
      isReturningToRest = true;
      isBeginPending = false;
      isReleasePending = false;
      motion.releaseImmediately();
      glow.reset();
      onMotionFrame?.({ press: [0, 0, 0], light: glow.light, isPlaying: false, isHovering: false });
      start();
    }

    function handleTouchStart(e: TouchEvent) {
      if (e.touches.length > 1) {
        interrupt();
      } else if (pointerId !== undefined) {
        touchId = e.touches[0]?.identifier;
      }
    }

    function handleTouchMove(e: TouchEvent) {
      if (!isPlaying || touchId === undefined) return;

      const touch = Array.from(e.changedTouches).find((t) => t.identifier === touchId);
      if (!touch) return;

      // During a hold the page must not scroll. Setting `touch-action` 150 ms into the touch is too late
      // for that, so the moves are cancelled here, in a listener added before the touch started.
      if (e.cancelable) e.preventDefault();
      e.stopPropagation();
      pendingX = touch.clientX;
      pendingY = touch.clientY;
      schedulePoint();
    }

    function handleMouseMove(e: MouseEvent) {
      if (isPlaying && !isHovering) e.stopPropagation();
    }

    function handleClick(e: MouseEvent) {
      if (!shouldSuppressClick || e.detail === 0) return;

      shouldSuppressClick = false;
      e.preventDefault();
      e.stopImmediatePropagation();
    }

    function handleContextMenu(e: Event) {
      if (isPlaying && !isHovering) e.preventDefault();
    }

    card.addEventListener('pointerdown', handleDown, pointerOptions);
    card.addEventListener('pointerenter', handleEnter, pointerOptions);
    card.addEventListener('pointerleave', handleLeave, pointerOptions);
    card.addEventListener('lostpointercapture', handleLostCapture, pointerOptions);
    card.addEventListener('touchstart', handleTouchStart, { passive: true, capture: true });
    card.addEventListener('touchmove', handleTouchMove, { passive: false, capture: true });
    card.addEventListener('click', handleClick, true);
    card.addEventListener('contextmenu', handleContextMenu);
    window.addEventListener('pointermove', handleMove, { passive: true, capture: true });
    window.addEventListener('mousemove', handleMouseMove, { passive: true, capture: true });
    window.addEventListener('pointerup', handleUp, pointerOptions);
    window.addEventListener('pointercancel', handleCancel, pointerOptions);
    window.addEventListener('blur', interrupt);
    document.addEventListener('visibilitychange', handleVisibility);
    document.addEventListener('scroll', handleScroll, true);

    return () => {
      // The light and particles that follow the finger reset, so an interrupted play does not freeze them
      if (isPlaying || pointer) {
        onMotionFrame?.({ press: [0, 0, 0], light: { x: 0, y: 0, opacity: 0 }, isPlaying: false, isHovering: false });
      }

      isCancelled = true;
      clearHold();
      card.removeEventListener('pointerdown', handleDown);
      card.removeEventListener('pointerenter', handleEnter);
      card.removeEventListener('pointerleave', handleLeave);
      card.removeEventListener('lostpointercapture', handleLostCapture);
      card.removeEventListener('touchstart', handleTouchStart, true);
      card.removeEventListener('touchmove', handleTouchMove, true);
      card.removeEventListener('click', handleClick, true);
      card.removeEventListener('contextmenu', handleContextMenu);
      window.removeEventListener('pointermove', handleMove, true);
      window.removeEventListener('mousemove', handleMouseMove, true);
      window.removeEventListener('pointerup', handleUp);
      window.removeEventListener('pointercancel', handleCancel);
      window.removeEventListener('blur', interrupt);
      document.removeEventListener('visibilitychange', handleVisibility);
      document.removeEventListener('scroll', handleScroll, true);

      requestMutation(() => {
        rotator.style.removeProperty('transform');
      });
    };
  }, [cardRef, rotatorRef, isDisabled, onMotionFrame]);
}
