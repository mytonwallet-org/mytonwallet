import { useRef } from '../../../../../lib/teact/teact';

import useEffectOnce from '../../../../../hooks/useEffectOnce';
import useLastCallback from '../../../../../hooks/useLastCallback';

export default function useDelayedAction<T extends unknown[]>(action: (...args: T) => void, delayMs: number) {
  const timerRef = useRef<number | undefined>();

  const cancel = useLastCallback(() => {
    if (!timerRef.current) return;

    window.clearTimeout(timerRef.current);
    timerRef.current = undefined;
  });

  const schedule = useLastCallback((...args: T) => {
    cancel();
    timerRef.current = window.setTimeout(() => {
      timerRef.current = undefined;
      action(...args);
    }, delayMs);
  });

  useEffectOnce(() => cancel);

  return [schedule, cancel] as const;
}
