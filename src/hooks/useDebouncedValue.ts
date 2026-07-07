import { useEffect, useState } from '../lib/teact/teact';

import useDebouncedCallback from './useDebouncedCallback';

// Fixes input lag caused by re-running heavy work on every keystroke, especially in Safari on iOS.
// Returns a trailing-debounced copy of `value` so consumers recompute after typing pauses, not on every change.
export default function useDebouncedValue<T>(value: T, ms: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);
  const updateDebouncedValue = useDebouncedCallback(setDebouncedValue, [setDebouncedValue], ms, true);

  useEffect(() => {
    updateDebouncedValue(value);
  }, [value, updateDebouncedValue]);

  return debouncedValue;
}
