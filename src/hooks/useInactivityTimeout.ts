import { useEffect } from '../lib/teact/teact';

import { MINUTE } from '../util/dateFormat';
import useLastCallback from './useLastCallback';

const INACTIVITY_TIMEOUT = 5 * MINUTE;
// Pointer events also cover touch input
const ACTIVITY_EVENTS = ['pointerdown', 'pointermove', 'keydown', 'wheel'] as const;

/**
 * Calls `onTimeout` once while `isActive` is true and the user has not touched, clicked, moved the pointer,
 * scrolled or typed for 5 minutes.
 *
 * Time spent with the app minimized or in a background tab counts as inactivity.
 */
export default function useInactivityTimeout(onTimeout: NoneToVoidFunction, isActive = false) {
  const lastOnTimeout = useLastCallback(onTimeout);

  useEffect(() => {
    if (!isActive) return undefined;

    let lastActivityAt = Date.now();
    let timeoutId: number | undefined;

    function handleActivity() {
      const now = Date.now();

      // The overdue timer can fire after this event, for example right after the system wakes from sleep.
      // Input after the deadline must not extend it.
      if (now >= lastActivityAt + INACTIVITY_TIMEOUT) {
        checkDeadline();
        return;
      }

      lastActivityAt = now;
    }

    // Browsers throttle or suspend timers on a hidden page, so the deadline can pass unnoticed while the app
    // is minimized. Checking it on return calls `onTimeout` as soon as the app is opened again.
    function handleVisibilityChange() {
      if (document.visibilityState === 'visible') checkDeadline();
    }

    function checkDeadline() {
      const remaining = lastActivityAt + INACTIVITY_TIMEOUT - Date.now();

      if (remaining > 0) {
        window.clearTimeout(timeoutId);
        timeoutId = window.setTimeout(checkDeadline, remaining);
        return;
      }

      stopWatching();
      lastOnTimeout();
    }

    function stopWatching() {
      window.clearTimeout(timeoutId);
      ACTIVITY_EVENTS.forEach((eventName) => {
        window.removeEventListener(eventName, handleActivity, true);
      });
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    }

    ACTIVITY_EVENTS.forEach((eventName) => {
      window.addEventListener(eventName, handleActivity, { capture: true, passive: true });
    });
    document.addEventListener('visibilitychange', handleVisibilityChange);
    checkDeadline();

    return stopWatching;
  }, [isActive, lastOnTimeout]);
}
