import { useCallback, useRef } from '../lib/teact/teact';

import { stopEvent } from '../util/domEvents';
import useEffectOnce from './useEffectOnce';

const DEFAULT_THRESHOLD = 350;

function useLongPress({
  onClick, onStart, onEnd, threshold = DEFAULT_THRESHOLD,
}: {
  onStart?: (target: HTMLElement) => void;
  onClick?: (event: React.MouseEvent) => void;
  onEnd?: NoneToVoidFunction;
  threshold?: number;
}) {
  const isLongPressActive = useRef(false);
  const isPressed = useRef(false);
  const timerId = useRef<number | undefined>(undefined);
  const targetRef = useRef<HTMLElement | undefined>(undefined);

  const start = useCallback((e: React.MouseEvent | React.TouchEvent) => {
    const canProcessEvent = ('button' in e && e.button === 0) || ('touches' in e && e.touches.length > 0);
    if (isPressed.current || !canProcessEvent) {
      return;
    }

    isLongPressActive.current = false;
    isPressed.current = true;
    targetRef.current = e.target as HTMLElement;
    timerId.current = window.setTimeout(() => {
      onStart?.(targetRef.current!);
      isLongPressActive.current = true;
    }, threshold);
  }, [onStart, threshold]);

  const end = useCallback(() => {
    if (!isPressed.current) return;

    if (isLongPressActive.current) {
      onEnd?.();
    }

    isPressed.current = false;
    window.clearTimeout(timerId.current);
  }, [onEnd]);

  // Besides the touch events, the browser generates a regular `click` for a tap, and it arrives
  // later than `touchend`. Acting right on `touchend` lets the UI re-render first, so that `click`
  // fires against the new element under the finger - e.g. the backdrop of a just-opened menu, which
  // instantly closes it. Binding `onClick` to the `click` itself avoids the race: it is the last
  // event of a tap, nothing else follows. The `click` that follows a long press is simply ignored -
  // this is what tells a tap from a long press.
  const handleClick = useCallback((e: React.MouseEvent) => {
    if (isLongPressActive.current) {
      isLongPressActive.current = false;
      stopEvent(e);
      return;
    }

    onClick?.(e);
  }, [onClick]);

  useEffectOnce(() => {
    return () => {
      window.clearTimeout(timerId.current);
    };
  });

  return {
    onMouseDown: start,
    onMouseUp: end,
    onMouseLeave: end,
    onTouchStart: start,
    onTouchEnd: end,
    onTouchCancel: end,
    onClick: handleClick,
  };
}

export default useLongPress;
