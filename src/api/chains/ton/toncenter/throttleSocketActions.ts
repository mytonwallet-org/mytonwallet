import type { ActivitiesUpdate, NewActivitiesCallback } from '../../../common/websocket/abstractWsClient';
import type { SocketFinality } from './types';

import { setCancellableTimeout } from '../../../../util/schedulers';
import { isActivityUpdateFinal } from './socket';

const FINALITY_ORDER: Record<SocketFinality, number> = {
  pending: 0,
  confirmed: 1,
  signed: 2,
  finalized: 3,
};

/**
 * Compares two finality levels. Returns true if `a` is at least as final as `b`.
 * This prevents race conditions where an older pending update could overwrite a newer confirmed one.
 */
function isFinalityAtLeast(a: SocketFinality, b: SocketFinality) {
  return FINALITY_ORDER[a] >= FINALITY_ORDER[b];
}

/**
 * The Toncenter websocket sends too many updates of pending actions. For example, sends a pending activity right before
 * sending the confirmed version of that activity. This function throttles them, but makes sure the pending actions are
 * created immediately.
 */
export function throttleToncenterSocketActions(
  delayMs: number,
  onUpdates: (updates: ActivitiesUpdate[]) => void,
): NewActivitiesCallback {
  // A record item is created when the first pending version arrives and is removed when it gets confirmed or invalidated.
  // All message hashes are throttled independently.
  const updatesByHash: Record<string, { toReport?: ActivitiesUpdate; cancelReport?: NoneToVoidFunction }> = {};

  const scheduleReport = (hash: string) => {
    updatesByHash[hash] ??= {};
    updatesByHash[hash].cancelReport ??= setCancellableTimeout(delayMs, () => {
      delete updatesByHash[hash].cancelReport;
      const { toReport } = updatesByHash[hash];
      if (toReport) {
        onUpdates([toReport]);
      }
    });
  };

  return (update) => {
    const hash = update.messageHashNormalized;

    if (isActivityUpdateFinal(update)) {
      // This is the final update for the hash. It should be delivered immediately and removed.
      updatesByHash[hash]?.cancelReport?.();
      delete updatesByHash[hash];
      onUpdates([update]);
    } else if (!updatesByHash[hash]) {
      // This is the first version of the hash's update. It should (and must for pendings) be delivered immediately.
      onUpdates([update]);
      scheduleReport(hash);
    } else {
      // Throttle the update, but only if it doesn't regress finality.
      // This prevents race conditions where an older 'pending' update arriving late could overwrite a 'confirmed' one.
      const { toReport } = updatesByHash[hash];
      if (!toReport || isFinalityAtLeast(update.finality, toReport.finality)) {
        updatesByHash[hash].toReport = update;
      }
      scheduleReport(hash);
    }
  };
}
