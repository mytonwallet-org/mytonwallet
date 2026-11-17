import { getActions } from '../../../global';

import usePerpsPolling, { PERPS_REFRESH_INTERVAL } from './usePerpsPolling';

/**
 * Refreshes the positions of the current account while a screen shows them and the app is in the foreground.
 *
 * With `shouldLoadOnce` the screen loads them once, when it shows. The Wallet screen does so for an account without
 * positions: one load is enough to notice a position opened on another device, and the polling then starts.
 *
 * A screen that stays mounted across a wallet switch passes `accountId`, so the positions of the new wallet load
 * at once.
 */
export default function usePerpsSnapshotPolling(isActive?: boolean, shouldLoadOnce?: boolean, accountId?: string) {
  const { loadPerpsSnapshot } = getActions();

  usePerpsPolling(
    loadPerpsSnapshot,
    isActive,
    shouldLoadOnce ? undefined : PERPS_REFRESH_INTERVAL,
    [shouldLoadOnce, accountId],
  );
}
