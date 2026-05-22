import type { ElementRef } from '../../../../../lib/teact/teact';
import { useEffect, useState } from '../../../../../lib/teact/teact';

import { requestMeasure } from '../../../../../lib/fasterdom/fasterdom';

import useLastCallback from '../../../../../hooks/useLastCallback';

const SCROLL_EDGE_TOLERANCE_PX = 5;
const EDGE_HOVER_ZONE_RATIO = 0.25;

type EdgeHoverZone = 'left' | 'right' | undefined;

interface OwnProps {
  containerRef: ElementRef<HTMLDivElement | undefined>;
  viewportRef?: ElementRef<HTMLDivElement | undefined>;
  isDisabled?: boolean;
  noAnimation?: boolean;
}

export default function useScrollButtonsVisibility({
  containerRef,
  viewportRef,
  isDisabled,
  noAnimation,
}: OwnProps) {
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(false);
  const [hoverZone, setHoverZone] = useState<EdgeHoverZone>(undefined);

  useEffect(() => {
    if (isDisabled) {
      setCanScrollLeft(false);
      setCanScrollRight(false);

      return undefined;
    }

    const container = containerRef.current;
    if (!container) return undefined;

    let isScheduled = false;

    function update() {
      isScheduled = false;
      const el = containerRef.current;
      if (!el) return;

      const { scrollLeft, scrollWidth, clientWidth } = el;
      const max = scrollWidth - clientWidth;

      setCanScrollLeft(scrollLeft > SCROLL_EDGE_TOLERANCE_PX);
      setCanScrollRight(scrollLeft < max - SCROLL_EDGE_TOLERANCE_PX);
    }

    function schedule() {
      if (isScheduled) return;

      isScheduled = true;
      requestMeasure(update);
    }

    schedule();
    container.addEventListener('scroll', schedule, { passive: true });

    const resizeObserver = new ResizeObserver(schedule);
    resizeObserver.observe(container);

    // Children added/removed (e.g. NFTs load and new collection cells appear) change `scrollWidth`
    // without changing the container's bounding box, so `ResizeObserver` alone misses them.
    const mutationObserver = new MutationObserver(schedule);
    mutationObserver.observe(container, { childList: true });

    return () => {
      container.removeEventListener('scroll', schedule);
      resizeObserver.disconnect();
      mutationObserver.disconnect();
    };
  }, [containerRef, isDisabled]);

  useEffect(() => {
    if (isDisabled) {
      setHoverZone(undefined);
      return undefined;
    }

    const targetRef = viewportRef ?? containerRef;
    const el = targetRef.current;
    if (!el) return undefined;

    let isScheduled = false;
    let pendingClientX = 0;
    let isCancelled = false;
    let currentHoverZone: EdgeHoverZone;

    function updateHoverZone(next: EdgeHoverZone) {
      if (next === currentHoverZone) return;

      currentHoverZone = next;
      setHoverZone(next);
    }

    function measureHoverZone() {
      isScheduled = false;
      if (isCancelled) return;

      const target = targetRef.current;
      if (!target) return;

      const rect = target.getBoundingClientRect();
      const x = pendingClientX - rect.left;
      const edge = rect.width * EDGE_HOVER_ZONE_RATIO;

      if (x < edge) {
        updateHoverZone('left');
      } else if (x > rect.width - edge) {
        updateHoverZone('right');
      } else {
        updateHoverZone(undefined);
      }
    }

    function handleMove(e: MouseEvent) {
      pendingClientX = e.clientX;
      if (isScheduled) return;

      isScheduled = true;
      requestMeasure(measureHoverZone);
    }

    function handleLeave() {
      updateHoverZone(undefined);
    }

    el.addEventListener('mousemove', handleMove, { passive: true });
    el.addEventListener('mouseleave', handleLeave);

    return () => {
      isCancelled = true;
      el.removeEventListener('mousemove', handleMove);
      el.removeEventListener('mouseleave', handleLeave);
    };
  }, [containerRef, viewportRef, isDisabled]);

  const scrollByOneCell = useLastCallback((direction: 'left' | 'right') => {
    const el = containerRef.current;
    if (!el) return;

    const firstChild = el.firstElementChild as HTMLElement | null;
    if (!firstChild) return;

    const gap = parseFloat(getComputedStyle(el).columnGap) || 0;
    const step = (firstChild.offsetWidth ?? el.clientWidth) + gap;

    el.scrollBy({ left: direction === 'left' ? -step : step, behavior: noAnimation ? 'auto' : 'smooth' });
  });

  return {
    isLeftButtonVisible: canScrollLeft && hoverZone === 'left',
    isRightButtonVisible: canScrollRight && hoverZone === 'right',
    scrollByOneCell,
  };
}
