import type { ElementRef } from '../../../lib/teact/teact';
import { useLayoutEffect, useRef, useState } from '../../../lib/teact/teact';

import { requestForcedReflow } from '../../../lib/fasterdom/fasterdom';
import windowSize from '../../../util/windowSize';

const VIEWPORT_PADDING = 8;

type Position = 'top' | 'bottom';

interface SuggestionsPositionResult {
  position: Position;
  isPositionReady: boolean;
}

/**
 * Dynamically calculate the position of a suggestions list
 * based on available viewport space above and below the input
 */
export default function useSuggestionsPosition(
  wrapperRef: ElementRef<HTMLElement>,
  suggestionsRef: ElementRef<HTMLElement>,
  suggestionsCount: number,
  isOpen: boolean,
): SuggestionsPositionResult {
  const [position, setPosition] = useState<Position>('bottom');
  const [isPositionReady, setIsPositionReady] = useState(false);
  const prevPositionRef = useRef<Position>('bottom');

  useLayoutEffect(() => {
    if (!isOpen) {
      setIsPositionReady(false);
      return;
    }

    const wrapper = wrapperRef.current;
    const suggestions = suggestionsRef.current;
    if (!wrapper || !suggestions) return;

    let rafId: number | undefined;

    requestForcedReflow(() => {
      const wrapperRect = wrapper.getBoundingClientRect();
      const suggestionsHeight = suggestions.offsetHeight;

      const newPosition = calculatePosition(wrapperRect, suggestionsHeight);
      const positionChanged = prevPositionRef.current !== newPosition;

      return () => {
        prevPositionRef.current = newPosition;
        setPosition(newPosition);

        if (positionChanged) {
          // If position changed, first hide menu, then show after DOM updates.
          // This is needed to avoid flickering
          setIsPositionReady(false);
          rafId = requestAnimationFrame(() => {
            setIsPositionReady(true);
          });
        } else {
          // If position unchanged, show menu immediately
          setIsPositionReady(true);
        }
      };
    });

    return () => {
      if (rafId !== undefined) {
        cancelAnimationFrame(rafId);
      }
    };
  }, [isOpen, suggestionsCount, wrapperRef, suggestionsRef]);

  return { position, isPositionReady };
}

function calculatePosition(
  wrapperRect: DOMRect,
  suggestionsHeight: number,
): Position {
  const { height: windowHeight, safeAreaTop, safeAreaBottom } = windowSize.get();

  const spaceBelow = windowHeight - wrapperRect.bottom - VIEWPORT_PADDING - safeAreaBottom;
  const spaceAbove = wrapperRect.top - VIEWPORT_PADDING - safeAreaTop;

  // Prefer bottom position if there's enough space
  if (suggestionsHeight <= spaceBelow) {
    return 'bottom';
  }
  if (suggestionsHeight <= spaceAbove) {
    return 'top';
  }

  // Otherwise, choose the one with more space
  return spaceBelow >= spaceAbove ? 'bottom' : 'top';
}
