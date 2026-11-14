import { type ElementRef, useEffect, useRef } from '../lib/teact/teact';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import animateHorizontalScroll from '../util/animateHorizontalScroll';
import { applyStyles } from '../util/animation';
import { stopEvent } from '../util/domEvents';
import { clamp } from '../util/math';
import useLastCallback from './useLastCallback';

interface OwnProps {
  containerRef: ElementRef<HTMLDivElement>;
  isDisabled?: boolean;
  dragThreshold?: number;
  getScrollBounds?: () => [number, number] | undefined;
  onDragStart?: NoneToVoidFunction;
  /** Replaces the built-in momentum. The velocity is in pixels per millisecond, and a resting pointer gives zero */
  onDragEnd?: (velocity: number) => void;
}

interface MousePointerSample {
  x: number;
  t: number;
}

const DRAG_THRESHOLD_PX = 5;
const VELOCITY_WINDOW_MS = 100;
const MOMENTUM_DURATION_MS = 300;
const MOMENTUM_MULTIPLIER = 0.6;
const MOMENTUM_MIN_PX = 1;

function useDragScroll({
  containerRef,
  isDisabled,
  dragThreshold = DRAG_THRESHOLD_PX,
  getScrollBounds,
  onDragStart,
  onDragEnd,
}: OwnProps) {
  const cleanupDragRef = useRef<NoneToVoidFunction | undefined>();

  const handleMouseDown = useLastCallback((e: MouseEvent) => {
    if (e.button !== 0) return;

    const container = containerRef.current;
    if (!container) return;

    const startX = e.pageX;
    let startScrollLeft = container.scrollLeft;
    let hasDragged = false;
    let hasReportedEnd = false;
    let pendingScrollLeft = container.scrollLeft;
    const mousePointerSamples: MousePointerSample[] = [{ x: e.pageX, t: Date.now() }];

    function handleMouseMove(moveEvent: MouseEvent) {
      // The page does not always receive a `mouseup` from outside the window
      if (!moveEvent.buttons) {
        handleMouseUp();
        return;
      }

      const deltaX = moveEvent.pageX - startX;
      if (!hasDragged) {
        if (Math.abs(deltaX) < dragThreshold) return;
        hasDragged = true;
        // A running scroll animation can move the container between the press and this moment
        startScrollLeft = container!.scrollLeft;
        onDragStart?.();
        // Disable `scroll-snap` so programmatic `scrollLeft` isn't overridden by browser snap
        requestMutation(() => {
          applyStyles(container!, { scrollSnapType: 'none' });
          container!.style.setProperty('--custom-cursor', 'grabbing');
        });
      }

      const now = Date.now();
      mousePointerSamples.push({ x: moveEvent.pageX, t: now });
      // Keep only samples within velocity window
      const cutoff = now - VELOCITY_WINDOW_MS;
      while (mousePointerSamples.length > 1 && mousePointerSamples[0].t < cutoff) {
        mousePointerSamples.shift();
      }

      const bounds = getScrollBounds?.();

      pendingScrollLeft = bounds ? clamp(startScrollLeft - deltaX, bounds[0], bounds[1]) : startScrollLeft - deltaX;
      requestMutation(() => {
        // The position belongs to `onDragEnd` after the release
        if (!hasReportedEnd) container!.scrollLeft = pendingScrollLeft;
      });
    }

    function restoreScrollSnap() {
      requestMutation(() => {
        applyStyles(container!, { scrollSnapType: '' });
      });
    }

    function cleanupWindowListeners() {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
      window.removeEventListener('blur', handleMouseUp);
      cleanupDragRef.current = undefined;
    }

    function handleMouseUp() {
      cleanupWindowListeners();

      if (!hasDragged) return;

      requestMutation(() => {
        container!.style.removeProperty('--custom-cursor');
      });

      let velocityPxPerMs = 0;
      if (mousePointerSamples.length >= 2) {
        const first = mousePointerSamples[0];
        const last = mousePointerSamples[mousePointerSamples.length - 1];
        const elapsedMs = last.t - first.t;
        if (elapsedMs > 0) {
          velocityPxPerMs = (last.x - first.x) / elapsedMs;
        }
      }

      window.addEventListener('click', stopEvent, { capture: true, once: true });
      // A release without its own `click`, such as outside the window, must keep the next real click
      setTimeout(() => window.removeEventListener('click', stopEvent, { capture: true }));

      if (onDragEnd) {
        const { t: lastMoveAt } = mousePointerSamples[mousePointerSamples.length - 1];

        // The callback reads the position, so the last move is written here instead of in its queued mutation
        hasReportedEnd = true;
        container!.scrollLeft = pendingScrollLeft;
        onDragEnd(Date.now() - lastMoveAt < VELOCITY_WINDOW_MS ? velocityPxPerMs : 0);
        restoreScrollSnap();
        return;
      }

      const momentum = velocityPxPerMs * MOMENTUM_MULTIPLIER * MOMENTUM_DURATION_MS;
      if (Math.abs(momentum) > MOMENTUM_MIN_PX) {
        // Restore `scroll-snap` in case `animateHorizontalScroll` returns early at scroll edge (`path === 0`)
        void animateHorizontalScroll(container!, pendingScrollLeft - momentum, MOMENTUM_DURATION_MS)
          .then(restoreScrollSnap);
      } else {
        // No momentum — restore `scroll-snap` so browser re-snaps to nearest item
        restoreScrollSnap();
      }
    }

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    window.addEventListener('blur', handleMouseUp);
    cleanupDragRef.current = cleanupWindowListeners;
  });

  useEffect(() => {
    const container = containerRef.current;
    if (isDisabled || !container) return undefined;

    container.addEventListener('mousedown', handleMouseDown);

    return () => {
      container.removeEventListener('mousedown', handleMouseDown);
      cleanupDragRef.current?.();
    };
  }, [containerRef, handleMouseDown, isDisabled]);
}

export default useDragScroll;
