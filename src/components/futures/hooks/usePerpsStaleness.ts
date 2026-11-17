import { useRef } from '../../../lib/teact/teact';

/**
 * Whether a screen shows its data as stale. Data restored from the cache or kept after failed reads is stale until
 * the screen first shows fresh data, and afterwards the screen keeps showing it as usual, as on iOS.
 */
export default function usePerpsStaleness(isStale: boolean, hasData: boolean) {
  const hasShownFreshRef = useRef(false);

  if (!hasData) {
    hasShownFreshRef.current = false;
    return isStale;
  }

  if (!isStale) hasShownFreshRef.current = true;

  return isStale && !hasShownFreshRef.current;
}
