import type { ElementRef, RefObject } from '../lib/teact/teact';
import { useEffect, useRef } from '../lib/teact/teact';

import { SEC } from '../api/constants';
import useElementVisibility from './useElementVisibility';
import useFlag from './useFlag';
import useInterval from './useInterval';
import useLastCallback from './useLastCallback';

interface OwnProps {
  containerRef: ElementRef<HTMLDivElement>;
  itemSelector: string;
  interval: number;
  isDisabled?: boolean;
}

const MANUAL_SCROLL_PAUSE_DURATION = 5 * SEC;
const AUTO_SCROLL_FALLBACK_RESET_MS = 700;

function useAutoScroll({
  containerRef,
  itemSelector,
  interval,
  isDisabled,
}: OwnProps) {
  const [isHovered, markIsHovered, unmarkIsHovered] = useFlag(false);
  const [isManuallyScrolling, markIsManuallyScrolling, unmarkIsManuallyScrolling] = useFlag(false);

  const isAutoScrollingRef = useRef(false);
  const currentIndexRef = useRef(0);
  const lastAutoScrollTimeRef = useRef(0);
  const manualScrollTimeoutRef = useRef<number | undefined>();
  const autoScrollResetTimeoutRef = useRef<number | undefined>();

  const { isVisible } = useElementVisibility({
    targetRef: containerRef,
    rootMargin: '0px',
    threshold: [0.1],
    isDisabled,
  });

  const shouldAutoScroll = !isDisabled && !isHovered && !isManuallyScrolling && isVisible;

  const resetAutoScrollingFlag = useLastCallback(() => {
    isAutoScrollingRef.current = false;
    clearTimeoutRef(autoScrollResetTimeoutRef);
  });

  const syncIndexFromContainer = useLastCallback(() => {
    const container = containerRef.current;
    if (!container) return;

    const items = container.querySelectorAll(itemSelector);
    if (!items.length) return;

    currentIndexRef.current = calcIndexFromScrollLeft(container, items);
  });

  const pauseAutoScroll = useLastCallback(() => {
    markIsManuallyScrolling();
    clearTimeoutRef(manualScrollTimeoutRef);
    manualScrollTimeoutRef.current = window.setTimeout(unmarkIsManuallyScrolling, MANUAL_SCROLL_PAUSE_DURATION);
  });

  const markAutoScrollStarted = useLastCallback(() => {
    isAutoScrollingRef.current = true;
    lastAutoScrollTimeRef.current = Date.now();
    clearTimeoutRef(autoScrollResetTimeoutRef);
    autoScrollResetTimeoutRef.current = window.setTimeout(resetAutoScrollingFlag, AUTO_SCROLL_FALLBACK_RESET_MS);
  });

  const handleScroll = useLastCallback(() => {
    if (isAutoScrollingRef.current) return;

    // Ignore scroll events that happen shortly after auto-scroll start (smooth scroll emits trailing events)
    const timeSinceLastAuto = Date.now() - lastAutoScrollTimeRef.current;
    if (timeSinceLastAuto < AUTO_SCROLL_FALLBACK_RESET_MS) return;

    syncIndexFromContainer();
    pauseAutoScroll();
  });

  const handleScrollEnd = useLastCallback(() => {
    if (isAutoScrollingRef.current) {
      resetAutoScrollingFlag();
      return;
    }
    syncIndexFromContainer();
  });

  const handleAutoScroll = useLastCallback(() => {
    const container = containerRef.current;
    if (!container || !shouldAutoScroll) return;

    const items = container.querySelectorAll(itemSelector);
    if (!items.length) return;

    const nextIndex = (currentIndexRef.current + 1) % items.length;
    markAutoScrollStarted();

    items[nextIndex].scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
      inline: 'start',
    });

    currentIndexRef.current = nextIndex;
  });

  useInterval(handleAutoScroll, shouldAutoScroll ? interval : undefined, true);

  // Disable auto-scroll on hover
  useEffect(() => {
    const container = containerRef.current;
    if (!container || isDisabled) return undefined;

    container.addEventListener('mouseenter', markIsHovered, { passive: true });
    container.addEventListener('mouseleave', unmarkIsHovered, { passive: true });

    return () => {
      container.removeEventListener('mouseenter', markIsHovered);
      container.removeEventListener('mouseleave', unmarkIsHovered);
    };
  }, [containerRef, isDisabled, markIsHovered, unmarkIsHovered]);

  // Initialize tracked index on mount / when selector changes
  useEffect(() => {
    if (isDisabled) return;
    syncIndexFromContainer();
  }, [isDisabled, syncIndexFromContainer, itemSelector]);

  // Stop auto-scroll on manual scroll
  useEffect(() => {
    const container = containerRef.current;
    if (!container || isDisabled) return undefined;

    const supportsScrollEnd = isScrollEndSupported();

    container.addEventListener('scroll', handleScroll, { passive: true });
    if (supportsScrollEnd) {
      container.addEventListener('scrollend', handleScrollEnd, { passive: true });
    }

    return () => {
      container.removeEventListener('scroll', handleScroll);
      if (supportsScrollEnd) {
        container.removeEventListener('scrollend', handleScrollEnd);
      }
      clearTimeoutRef(manualScrollTimeoutRef);
      clearTimeoutRef(autoScrollResetTimeoutRef);
    };
  }, [containerRef, isDisabled, handleScroll, handleScrollEnd]);
}

export default useAutoScroll;

function getGapPx(container: HTMLElement) {
  const gap = parseFloat(getComputedStyle(container).gap);
  return Number.isFinite(gap) ? gap : 0;
}

function getStepSize(container: HTMLElement, firstItem: Element) {
  const itemWidth = (firstItem as HTMLElement).offsetWidth;
  return itemWidth + getGapPx(container);
}

function calcIndexFromScrollLeft(container: HTMLElement, items: NodeListOf<Element>) {
  if (!items.length) return 0;

  const step = getStepSize(container, items[0]);
  return step ? Math.round(container.scrollLeft / step) : 0;
}

function isScrollEndSupported() {
  return 'onscrollend' in window;
}

function clearTimeoutRef(ref: RefObject<number | undefined>) {
  if (ref.current !== undefined) {
    window.clearTimeout(ref.current);
    ref.current = undefined;
  }
}
