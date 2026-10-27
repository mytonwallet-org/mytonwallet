import { useMemo, useUnmountCleanup } from '../lib/teact/teact';

import useLastCallback from './useLastCallback';

const HOLD_DELAY_MS = 400;
const MOVE_THRESHOLD = 12;

interface Options {
  isHidden: boolean;
  onToggle: NoneToVoidFunction;
  onMenu: NoneToVoidFunction;
}

export default function useCardBalanceGesture(options: Options) {
  const getOptions = useLastCallback(() => options);
  const gesture = useMemo(() => createBalanceGesture(getOptions), [getOptions]);
  useUnmountCleanup(gesture.cancel);

  return gesture.handlers;
}

function createBalanceGesture(getOptions: () => Options) {
  let timeoutId: number | undefined;
  let pointerId: number | undefined;
  let startX = 0;
  let startY = 0;
  let shouldConsumeClick = false;

  function cancel() {
    window.clearTimeout(timeoutId);
    timeoutId = undefined;
    pointerId = undefined;
    window.removeEventListener('pointermove', handleMove);
    window.removeEventListener('pointerup', handleUp);
    window.removeEventListener('pointercancel', handleUp);
    window.removeEventListener('blur', cancel);
  }

  // A swipe that starts on the balance scrolls the page, so neither the hold nor the release click counts
  function handleMove(e: PointerEvent) {
    if (e.pointerId === pointerId && Math.hypot(e.clientX - startX, e.clientY - startY) > MOVE_THRESHOLD) {
      shouldConsumeClick = true;
      cancel();
    }
  }

  function handleUp(e: PointerEvent) {
    if (e.pointerId === pointerId) cancel();
  }

  return {
    cancel,
    handlers: {
      onPointerDown(e: React.PointerEvent<HTMLElement>) {
        if (e.button !== 0) return;

        cancel();
        pointerId = e.pointerId;
        startX = e.clientX;
        startY = e.clientY;
        shouldConsumeClick = false;
        window.addEventListener('pointermove', handleMove, { passive: true });
        window.addEventListener('pointerup', handleUp);
        window.addEventListener('pointercancel', handleUp);
        window.addEventListener('blur', cancel);

        if (getOptions().isHidden) return;

        const isTouch = e.pointerType === 'touch';

        timeoutId = window.setTimeout(() => {
          timeoutId = undefined;

          if (getOptions().isHidden) return;

          shouldConsumeClick = true;
          if (isTouch) suppressReleaseTap();
          getOptions().onMenu();
        }, HOLD_DELAY_MS);
      },
      onClick(e: React.MouseEvent<HTMLElement>) {
        // A keyboard-initiated click has no detail and is never part of a hold
        if (shouldConsumeClick && e.detail !== 0) {
          shouldConsumeClick = false;
          e.preventDefault();
          return;
        }

        getOptions().onToggle();
      },
      // On Windows and Linux, browsers also send this for Shift+F10 and the context menu key
      onContextMenu(e: React.MouseEvent<HTMLElement>) {
        e.preventDefault();
        cancel();

        const { isHidden, onMenu } = getOptions();
        if (!isHidden) onMenu();
      },
      onKeyDown(e: React.KeyboardEvent<HTMLElement>) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();

          // A held key repeats `keydown`, which would keep hiding and revealing the balance
          if (!e.repeat) getOptions().onToggle();
        }
      },
    },
  };
}

/**
 * The hold opens the menu while the finger is still down. A release before the system long-press counts as a tap,
 * and the `mousedown` that the browser emulates for it lands on the menu backdrop and closes the menu at once.
 * Cancelling `touchend` stops the emulated mouse events and the click.
 */
function suppressReleaseTap() {
  function handleTouchEnd(e: TouchEvent) {
    if (e.type === 'touchend') e.preventDefault();

    window.removeEventListener('touchend', handleTouchEnd);
    window.removeEventListener('touchcancel', handleTouchEnd);
  }

  window.addEventListener('touchend', handleTouchEnd, { passive: false });
  window.addEventListener('touchcancel', handleTouchEnd);
}
