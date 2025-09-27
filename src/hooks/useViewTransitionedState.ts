import { useEffect, useRef, useState } from '../lib/teact/teact';

import useLastCallback from './useLastCallback';
import { useViewTransition } from './useViewTransition';

type Options = {
  transitionName?: string;
  noSkipFirst?: boolean;
};

interface Result<T> {
  renderedValue: T;
  vtnStyle?: string;
}

/**
 * Hook to mirror an external value into local state with View Transitions.
 *
 * - On first render, sets the value without transition (unless overridden).
 * - On subsequent updates, wraps the state update with `useViewTransition`.
 * - Optionally returns a ready-to-use inline style string for Teact: `view-transition-name: <name>`.
 */
export function useViewTransitionedState<T>(value: T, options?: Options): Result<T> {
  const { transitionName, noSkipFirst = false } = options || {};

  const [renderedValue, setRenderedValue] = useState<T>(value);
  const isFirstRenderRef = useRef<boolean>(true);
  const { startViewTransition, shouldApplyVtn } = useViewTransition();

  // For preventing re-rendering after update `useEffect` deps
  const handleStartViewTransition = useLastCallback((newValue: T) => {
    startViewTransition(() => setRenderedValue(newValue));
  });

  useEffect(() => {
    if (isFirstRenderRef.current) {
      isFirstRenderRef.current = false;
      if (!noSkipFirst) {
        setRenderedValue(value);
        return;
      }
    }

    handleStartViewTransition(value);
  }, [value, noSkipFirst]);

  const vtnStyle = shouldApplyVtn && transitionName
    ? `view-transition-name: ${transitionName}`
    : undefined;

  return {
    renderedValue,
    vtnStyle,
  };
}

export default useViewTransitionedState;
