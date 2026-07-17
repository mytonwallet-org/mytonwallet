import { useEffect } from '../../../lib/teact/teact';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';

import { useDeviceScreen } from '../../../hooks/useDeviceScreen';

/**
 * Keeps scroll position pinned to the bottom when the virtual keyboard opens or closes.
 * Uses `visualViewport` resize events.
 */
export default function useScrollResetOnResize(
  scrollRef: React.RefObject<HTMLDivElement | undefined>,
  isAtBottomRef: React.RefObject<boolean>,
) {
  const { isPortrait } = useDeviceScreen();

  useEffect(() => {
    if (!isPortrait) return undefined;

    function snapToBottom() {
      if (!isAtBottomRef.current) return;

      requestMeasure(() => {
        const el = scrollRef.current;
        if (el) {
          el.scrollTop = el.scrollHeight;
          isAtBottomRef.current = true;
        }
      });
    }

    const viewport = window.visualViewport;
    if (!viewport) return undefined;

    viewport.addEventListener('resize', snapToBottom);
    return () => viewport.removeEventListener('resize', snapToBottom);
  }, [isAtBottomRef, isPortrait, scrollRef]);
}
