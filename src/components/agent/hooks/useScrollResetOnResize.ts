import { useEffect } from '../../../lib/teact/teact';

import { IS_CAPACITOR } from '../../../config';
import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import { onVirtualKeyboardClose, onVirtualKeyboardOpen } from '../../../util/windowSize';

import { useDeviceScreen } from '../../../hooks/useDeviceScreen';

/**
 * Keeps scroll position pinned to the bottom when the virtual keyboard opens or closes.
 * Uses Capacitor keyboard events when available, falls back to `visualViewport` resize.
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

    if (IS_CAPACITOR) {
      const unsubOpen = onVirtualKeyboardOpen(snapToBottom);
      const unsubClose = onVirtualKeyboardClose(snapToBottom);

      return () => {
        unsubOpen();
        unsubClose();
      };
    }

    const viewport = window.visualViewport;
    if (!viewport) return undefined;

    viewport.addEventListener('resize', snapToBottom);
    return () => viewport.removeEventListener('resize', snapToBottom);
  }, [isAtBottomRef, isPortrait, scrollRef]);
}
