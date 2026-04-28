import { type ElementRef, useEffect } from '../lib/teact/teact';

interface OwnProps {
  containerRef: ElementRef<HTMLDivElement>;
  isDisabled?: boolean;
  shouldPreventDefault?: boolean;
  contentSelector?: string;
}

function useHorizontalScroll({
  containerRef,
  isDisabled,
  shouldPreventDefault = false,
  contentSelector,
}: OwnProps) {
  useEffect(() => {
    const container = containerRef.current;

    if (isDisabled || !container) {
      return undefined;
    }

    function handleScroll(e: WheelEvent) {
      // Ignore horizontal scroll and let it work natively (e.g. on touchpad)
      if (!e.deltaX) {
        const content = contentSelector ? container!.querySelector(contentSelector) : container;
        if (!content) return;

        const { scrollLeft, scrollWidth, clientWidth } = content;
        const isAtEnd = e.deltaY > 0 && scrollLeft + clientWidth >= scrollWidth;
        const isAtStart = e.deltaY < 0 && scrollLeft <= 0;

        content.scrollLeft += e.deltaY / 4;
        if (shouldPreventDefault && !isAtEnd && !isAtStart) e.preventDefault();
      }
    }

    container.addEventListener('wheel', handleScroll, { passive: !shouldPreventDefault });

    return () => {
      container.removeEventListener('wheel', handleScroll);
    };
  }, [containerRef, contentSelector, isDisabled, shouldPreventDefault]);
}

export default useHorizontalScroll;
