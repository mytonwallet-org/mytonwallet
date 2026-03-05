import { type ElementRef, useEffect, useRef } from '../lib/teact/teact';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import animateHorizontalScroll from '../util/animateHorizontalScroll';
import { applyStyles } from '../util/animation';
import { stopEvent } from '../util/domEvents';
import useLastCallback from './useLastCallback';

interface OwnProps {
  containerRef: ElementRef<HTMLDivElement>;
  isDisabled?: boolean;
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

function useDragScroll({ containerRef, isDisabled }: OwnProps) {
  const cleanupDragRef = useRef<NoneToVoidFunction | undefined>();

  const handleMouseDown = useLastCallback((e: MouseEvent) => {
    if (e.button !== 0) return;

    const container = containerRef.current;
    if (!container) return;

    const startX = e.pageX;
    const startScrollLeft = container.scrollLeft;
    let hasDragged = false;
    let pendingScrollLeft = container.scrollLeft;
    const mousePointerSamples: MousePointerSample[] = [{ x: e.pageX, t: Date.now() }];

    function handleMouseMove(moveEvent: MouseEvent) {
      const deltaX = moveEvent.pageX - startX;
      if (!hasDragged) {
        if (Math.abs(deltaX) < DRAG_THRESHOLD_PX) return;
        hasDragged = true;
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

      pendingScrollLeft = startScrollLeft - deltaX;
      requestMutation(() => {
        container!.scrollLeft = pendingScrollLeft;
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

      const momentum = velocityPxPerMs * MOMENTUM_MULTIPLIER * MOMENTUM_DURATION_MS;
      if (Math.abs(momentum) > MOMENTUM_MIN_PX) {
        // Restore `scroll-snap` in case `animateHorizontalScroll` returns early at scroll edge (`path === 0`)
        void animateHorizontalScroll(container!, pendingScrollLeft - momentum, MOMENTUM_DURATION_MS)
          .then(restoreScrollSnap);
      } else {
        // No momentum — restore `scroll-snap` so browser re-snaps to nearest item
        restoreScrollSnap();
      }

      window.addEventListener('click', stopEvent, { capture: true, once: true });
    }

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
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
