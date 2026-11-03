import { useEffect } from '../../../lib/teact/teact';

import { PORTRAIT_SCREEN_QUERY } from '../../../hooks/useDeviceScreen';
import useLastCallback from '../../../hooks/useLastCallback';

/**
 * Calls `onSwitch` as the app switches between its portrait and landscape layouts, which mount the Agent separately.
 * The call comes before either layout renders, while the screens on their way out can still be measured.
 */
export default function useAgentLayoutSwitch(onSwitch: NoneToVoidFunction, isEnabled: boolean) {
  const handleSwitch = useLastCallback(onSwitch);

  useEffect(() => {
    if (!isEnabled) return undefined;

    const query = window.matchMedia(PORTRAIT_SCREEN_QUERY);
    query.addEventListener('change', handleSwitch);
    return () => query.removeEventListener('change', handleSwitch);
  }, [handleSwitch, isEnabled]);
}
