import { type RefObject, useCallback } from '../lib/teact/teact';

export function useCombinedRefs<T>(
  ...refs: Array<RefObject<T | undefined> | undefined>
): (node?: T) => void {
  return useCallback(
    (node?: T) => {
      refs.forEach((ref) => {
        if (ref) ref.current = node;
      });
    },
    [refs],
  );
}
