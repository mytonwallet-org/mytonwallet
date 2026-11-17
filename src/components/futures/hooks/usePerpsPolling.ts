import { useEffect } from '../../../lib/teact/teact';

import { SECOND } from '../../../util/dateFormat';

import useInterval from '../../../hooks/useInterval';
import useIsInForeground from '../../../hooks/useIsInForeground';
import useLastCallback from '../../../hooks/useLastCallback';

export const PERPS_REFRESH_INTERVAL = 20 * SECOND;

/**
 * Calls `callback` when a screen shows its data, then every `interval` while the screen stays active and the app is
 * in the foreground. Without `interval` the screen loads the data only when it shows.
 *
 * A change of `dependencies`, such as another market or language, loads the data again right away.
 */
export default function usePerpsPolling(
  callback: NoneToVoidFunction,
  isActive?: boolean,
  interval?: number,
  dependencies: readonly unknown[] = [],
) {
  const isInForeground = useIsInForeground();
  const isEnabled = Boolean(isActive && isInForeground);
  const refresh = useLastCallback(callback);

  useEffect(() => {
    if (isEnabled) refresh();
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [isEnabled, refresh, ...dependencies]);

  useInterval(refresh, isEnabled ? interval : undefined, true);
}
