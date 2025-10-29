import { useEffect, useRef, useState } from '../lib/teact/teact';

import useLastCallback from './useLastCallback';

const DEFAULT_THRESHOLD = 1;

/**
 * Hook to track scroll position state (beginning/end detection)
 * Optimized for high-frequency scroll events
 *
 * @param threshold - Distance in pixels from edge to consider as beginning/end
 */
export default function useScrolledState(threshold = DEFAULT_THRESHOLD) {
  const [scrollState, setScrollState] = useState({
    isAtBeginning: true,
    isAtEnd: true,
  });

  const rafRef = useRef<number | undefined>(undefined);

  const update = useLastCallback((element?: HTMLElement | null) => {
    if (!element) return;

    const { scrollHeight, scrollTop, clientHeight } = element;

    const newIsAtBeginning = scrollTop < threshold;
    const newIsAtEnd = scrollHeight - scrollTop - clientHeight < threshold;

    if (newIsAtBeginning !== scrollState.isAtBeginning || newIsAtEnd !== scrollState.isAtEnd) {
      setScrollState({
        isAtBeginning: newIsAtBeginning,
        isAtEnd: newIsAtEnd,
      });
    }
  });

  const handleScroll = useLastCallback((e: React.UIEvent<HTMLElement>) => {
    if (rafRef.current !== undefined) {
      cancelAnimationFrame(rafRef.current);
    }

    rafRef.current = requestAnimationFrame(() => {
      update(e.target as HTMLElement);
    });
  });

  useEffect(() => {
    return () => {
      if (rafRef.current !== undefined) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, []);

  return {
    isAtBeginning: scrollState.isAtBeginning,
    isAtEnd: scrollState.isAtEnd,
    isScrolled: !scrollState.isAtBeginning,
    handleScroll,
    update,
  };
}
