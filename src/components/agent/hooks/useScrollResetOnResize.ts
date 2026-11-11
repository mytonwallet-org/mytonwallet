import { useEffect, useRef } from '../../../lib/teact/teact';

import { requestMeasure } from '../../../lib/fasterdom/fasterdom';
import { isAnimatingScroll, restartScrollAnimation } from '../../../util/animateScroll';

import { useDeviceScreen } from '../../../hooks/useDeviceScreen';
import useLastCallback from '../../../hooks/useLastCallback';

// Far longer than the browser's smooth scroll, which takes about half a second even through a few slow frames, so a
// scroll that another one replaces does not hold the list's state for long
const SNAP_MAX_DURATION = 2000;

interface Snap {
  targetTop: number;
  /** How far from the target the list stood at the last position it passed */
  distance: number;
  endsAt: number;
}

/**
 * Keeps scroll position pinned to the bottom when the virtual keyboard opens or closes.
 * Uses `visualViewport` resize events.
 *
 * The list scrolls to its end smoothly (`.custom-scroll`), so the positions it passes on the way are its own scroll
 * to the end rather than the user's: `getIsSnappingToBottom` tells the list not to count them as leaving the end.
 */
export default function useScrollResetOnResize(
  scrollRef: React.RefObject<HTMLDivElement | undefined>,
  isAtBottomRef: React.RefObject<boolean>,
) {
  const { isPortrait } = useDeviceScreen();
  const snapRef = useRef<Snap>();

  useEffect(() => {
    if (!isPortrait) return undefined;

    function snapToBottom() {
      if (!isAtBottomRef.current) return;

      requestMeasure(() => {
        const el = scrollRef.current;
        if (!el) return;

        if (isAnimatingScroll(el)) {
          restartScrollAnimation();
          return;
        }

        const targetTop = el.scrollHeight - el.clientHeight;
        snapRef.current = {
          targetTop,
          distance: Math.abs(targetTop - el.scrollTop),
          endsAt: Date.now() + SNAP_MAX_DURATION,
        };
        el.scrollTop = el.scrollHeight;
        isAtBottomRef.current = true;
      });
    }

    const viewport = window.visualViewport;
    if (!viewport) return undefined;

    viewport.addEventListener('resize', snapToBottom);
    return () => viewport.removeEventListener('resize', snapToBottom);
  }, [isAtBottomRef, isPortrait, scrollRef]);

  // The scroll ends at the position it aimed at, or at the end where the content shrank under it. A position further
  // from the target than the last one is not this scroll, as when the keys take the list up on the way.
  const getIsSnappingToBottom = useLastCallback((element: HTMLElement) => {
    const snap = snapRef.current;
    if (!snap) return false;

    const { scrollTop, scrollHeight, clientHeight } = element;
    const distance = Math.abs(scrollTop - snap.targetTop);
    if (
      Date.now() > snap.endsAt
      || distance < 1
      || distance > snap.distance
      || scrollHeight - clientHeight - scrollTop < 1
    ) {
      snapRef.current = undefined;
      return false;
    }

    snap.distance = distance;
    return true;
  });

  const cancelSnapToBottom = useLastCallback(() => {
    snapRef.current = undefined;
  });

  return { getIsSnappingToBottom, cancelSnapToBottom };
}
