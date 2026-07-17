import { type ElementRef, useEffect, useState } from '../lib/teact/teact';
import { addExtraClass, removeExtraClass } from '../lib/teact/teact-dom';

import type { IAnchorPosition } from '../global/types';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import { stopEvent } from '../util/domEvents';
import { vibrate } from '../util/haptics';
import { IS_IOS, IS_PWA, IS_TOUCH_ENV } from '../util/windowEnvironment';
import useLastCallback from './useLastCallback';

const LONG_TAP_DURATION_MS = 200;
const IOS_PWA_CONTEXT_MENU_DELAY_MS = 100;

interface OwnProps {
  elementRef: ElementRef<HTMLElement>;
  isMenuDisabled?: boolean;
  shouldDisableOnLink?: boolean;
  shouldDisableOnLongTap?: boolean;
  shouldDisablePropagation?: boolean;
}

const useContextMenuHandlers = ({
  elementRef,
  isMenuDisabled,
  shouldDisableOnLink,
  shouldDisableOnLongTap,
  shouldDisablePropagation,
}: OwnProps) => {
  const [isContextMenuOpen, setIsContextMenuOpen] = useState(false);
  const [contextMenuAnchor, setContextMenuAnchor] = useState<IAnchorPosition | undefined>(undefined);
  const [contextMenuTarget, setContextMenuTarget] = useState<HTMLElement | undefined>(undefined);

  const handleBeforeContextMenu = useLastCallback((e: React.MouseEvent) => {
    if (!isMenuDisabled && e.button === 2) {
      requestMutation(() => {
        addExtraClass(e.target as HTMLElement, 'no-selection');
      });
    }
  });

  const handleContextMenu = useLastCallback((e: React.MouseEvent) => {
    requestMutation(() => {
      removeExtraClass(e.target as HTMLElement, 'no-selection');
    });

    if (isMenuDisabled || (shouldDisableOnLink && (e.target as HTMLElement).matches('a[href]'))) {
      return;
    }
    stopEvent(e);

    if (contextMenuAnchor) {
      return;
    }

    setIsContextMenuOpen(true);
    setContextMenuAnchor({ x: e.clientX, y: e.clientY });
    setContextMenuTarget(e.target as HTMLElement);
    vibrate();
  });

  const handleContextMenuClose = useLastCallback(() => {
    setIsContextMenuOpen(false);
  });

  const handleContextMenuHide = useLastCallback(() => {
    setContextMenuAnchor(undefined);
  });

  const handleTouchMove = useLastCallback((e: TouchEvent) => {
    if (isContextMenuOpen) {
      stopEvent(e);
    }
  });

  // Support context menu on touch devices
  useEffect(() => {
    if (isMenuDisabled || !IS_TOUCH_ENV || shouldDisableOnLongTap) {
      return undefined;
    }

    const element = elementRef.current;
    if (!element) {
      return undefined;
    }

    let timer: number | undefined;

    const clearLongPressTimer = () => {
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
      }
    };
    const clearLongPressTimerAndStopEvent = (origialEvent: TouchEvent) => {
      clearLongPressTimer();
      handleTouchMove(origialEvent);
    };

    const emulateContextMenuEvent = (originalEvent: TouchEvent) => {
      clearLongPressTimer();

      const { clientX, clientY, target } = originalEvent.touches[0];

      if (contextMenuAnchor || (shouldDisableOnLink && (target as HTMLElement).matches('a[href]'))) {
        return;
      }

      // Temporarily intercept and clear the next click
      document.addEventListener('touchend', (e) => {
        // On iOS in PWA mode, the context menu may cause click-through to the element in the menu upon opening
        if (IS_IOS && IS_PWA) {
          setTimeout(() => {
            document.removeEventListener('mousedown', stopEvent, {
              capture: true,
            });
            document.removeEventListener('click', stopEvent, {
              capture: true,
            });
          }, IOS_PWA_CONTEXT_MENU_DELAY_MS);
        }
        stopEvent(e);
      }, {
        once: true,
        capture: true,
      });

      // On iOS15, in PWA mode, the context menu immediately closes after opening
      if (IS_PWA && IS_IOS) {
        document.addEventListener('mousedown', stopEvent, {
          once: true,
          capture: true,
        });
        document.addEventListener('click', stopEvent, {
          once: true,
          capture: true,
        });
      }

      setIsContextMenuOpen(true);
      setContextMenuAnchor({ x: clientX, y: clientY });
      vibrate();
    };

    const startLongPressTimer = (e: TouchEvent) => {
      if (isMenuDisabled) {
        return;
      }
      if (shouldDisablePropagation) e.stopPropagation();
      clearLongPressTimer();

      timer = window.setTimeout(() => emulateContextMenuEvent(e), LONG_TAP_DURATION_MS);
    };

    // @perf Consider event delegation
    element.addEventListener('touchstart', startLongPressTimer, { passive: true });
    element.addEventListener('touchcancel', clearLongPressTimer, true);
    element.addEventListener('touchend', clearLongPressTimer, true);
    // `useCapture` is needed to prevent the content from scrolling behind the context menu
    element.addEventListener('touchmove', clearLongPressTimerAndStopEvent, true);

    return () => {
      clearLongPressTimer();
      element.removeEventListener('touchstart', startLongPressTimer);
      element.removeEventListener('touchcancel', clearLongPressTimer, true);
      element.removeEventListener('touchend', clearLongPressTimer, true);
      element.removeEventListener('touchmove', clearLongPressTimerAndStopEvent, true);
    };
  }, [
    contextMenuAnchor, isMenuDisabled, shouldDisableOnLongTap, elementRef, shouldDisableOnLink,
    shouldDisablePropagation,
  ]);

  return {
    isContextMenuOpen,
    contextMenuAnchor,
    contextMenuTarget,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
  };
};

export default useContextMenuHandlers;
