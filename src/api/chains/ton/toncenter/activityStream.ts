import type { FallbackPollingOptions } from '../../../common/polling/fallbackPollingScheduler';
import type { Period } from '../../../common/polling/utils';
import type { ActivitiesUpdate, WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { ApiActivity, ApiNetwork } from '../../../types';

import { mergeSortedActivities, sortActivities } from '../../../../util/activities/order';
import { createCallbackManager } from '../../../../util/callbacks';
import { focusAwareDelay } from '../../../../util/focusAwareDelay';
import { extractKey } from '../../../../util/iteratees';
import { logDebugError } from '../../../../util/logs';
import { FallbackPollingScheduler } from '../../../common/polling/fallbackPollingScheduler';
import { periodToMs } from '../../../common/polling/utils';
import { FIRST_TRANSACTIONS_LIMIT } from '../../../constants';
import { fetchActions, fetchPendingActions } from './actions';
import { getToncenterSocket } from './socket';
import { throttleToncenterSocketActions } from './throttleSocketActions';

const SOCKET_THROTTLE_DELAY = 250;
const FINISHED_HASH_MEMORY_SIZE = 100;

/**
 * The activities are sorted by timestamp descending.
 * The updates may arrive not in the order of activity time and may duplicate.
 *
 * Terminology note: In this file, "finalized" refers to activities that are immutable and will never change
 * (status='completed'/'failed'). This is different from `finality: 'confirmed'` from the socket, which means
 * the activity is in a shard block but not yet in masterchain and can still be invalidated.
 *
 * - `newFinalizedActivities`: Newly finalized activities (status='completed'/'failed') that are immutable
 * - `allPendingActivities`: All non-finalized activities including:
 *   - status='pending'/'pendingTrusted': Show clock animation, can be updated/invalidated
 *   - status='confirmed': Don't show clock (looks final to user), but can still be invalidated
 *
 * Activities are removed from `allPendingActivities` when:
 * - They become finalized (appear in `newFinalizedActivities`)
 * - They are invalidated (are not committed into the masterchain)
 */
export type OnActivityUpdate = (
  newFinalizedActivities: ApiActivity[],
  allPendingActivities: readonly ApiActivity[],
) => void;

export type OnLoadingChange = (isLoading: boolean) => void;

/**
 * Streams the new activities (confirmed and pending) in the given TON wallet as they are received from the Toncenter
 * API (with no artificial activities like CEX swaps). Uses the socket, and fallbacks to HTTP polling when the socket is
 * unavailable.
 */
export class ActivityStream {
  #network: ApiNetwork;
  #address: string;
  #minPollDelay: Period;

  #newestConfirmedActivityTimestamp?: number;

  #pendingActivities = managePendingActivities();

  #walletWatcher: WalletWatcher;

  #fallbackPollingScheduler: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnActivityUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  /** When `true`, the polling retries until succeeds, and the confirmed actions from the socket get stashed */
  #doesNeedToRestoreHistory = false;

  /** Sorted by timestamp descending */
  #socketConfirmedActionsStash: ApiActivity[] = [];

  #isDestroyed = false;

  constructor(
    network: ApiNetwork,
    address: string,
    newestConfirmedActivityTimestamp: number | undefined,
    fallbackPollingOptions: FallbackPollingOptions,
  ) {
    this.#network = network;
    this.#address = address;
    this.#minPollDelay = fallbackPollingOptions.minPollDelay;
    this.#newestConfirmedActivityTimestamp = newestConfirmedActivityTimestamp;

    this.#walletWatcher = getToncenterSocket(network).watchWallets(
      [{ address }],
      {
        onConnect: this.#handleSocketConnect,
        onDisconnect: this.#handleSocketDisconnect,
        onNewActivities: throttleToncenterSocketActions(SOCKET_THROTTLE_DELAY, this.#handleSocketNewActivities),
      },
    );

    this.#doesNeedToRestoreHistory = this.#walletWatcher.isConnected;

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(
      this.#poll,
      this.#walletWatcher.isConnected,
      fallbackPollingOptions,
    );
  }

  /**
   * Registers a callback firing then new activities arrive.
   * The callback calls are throttled.
   */
  public onUpdate(callback: OnActivityUpdate) {
    return this.#updateListeners.addCallback(callback);
  }

  /**
   * Registers a callback firing when the regular polling starts of finishes.
   * Guaranteed to be called with `isLoading=false` after calling the `onUpdate` callbacks.
   */
  public onLoadingChange(callback: OnLoadingChange) {
    return this.#loadingListeners.addCallback(callback);
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#walletWatcher.destroy();
    this.#fallbackPollingScheduler.destroy();
  }

  #handleSocketConnect = () => {
    // When the socket gets connected, it's important to load the confirmed activities since the last activity,
    // otherwise the activities arriving from the socket will create a gap in the activity history.
    this.#doesNeedToRestoreHistory = true;
    this.#fallbackPollingScheduler.onSocketConnect();
  };

  #handleSocketDisconnect = () => {
    this.#doesNeedToRestoreHistory = false;
    this.#fallbackPollingScheduler.onSocketDisconnect();
  };

  #handleSocketNewActivities = (updates: ActivitiesUpdate[]) => {
    if (this.#isDestroyed) return;
    this.#fallbackPollingScheduler.onSocketMessage();

    // Split updates into two streams:
    // - finalizedActivities: finality='finalized' with actual activities - these are immutable
    // - pendingUpdates: everything else (pending/confirmed finality, or invalidations with empty activities)
    const { pendingUpdates, finalizedActivities } = splitSocketUpdates(updates);

    const instantFinalizedActivities = this.#doesNeedToRestoreHistory ? [] : finalizedActivities;
    const stashedFinalizedActivities = this.#doesNeedToRestoreHistory ? finalizedActivities : [];

    // One of the goals here is preventing the stashed activities from removing pending activities (switching an activity
    // from pending to finalized must be seamless). Another goal is delivering the pending activities with no delay.
    this.#socketConfirmedActionsStash.unshift(...stashedFinalizedActivities);
    this.#handleNewActivities(instantFinalizedActivities, undefined, pendingUpdates);
  };

  /** Fetches the activities when the socket is not connected or has just connected */
  #poll = async () => {
    try {
      this.#loadingListeners.runCallbacks(true);

      const [pendingActivities, newFinalizedActivities] = await Promise.all([
        loadPendingActivities(this.#network, this.#address),
        this.#loadNewFinalizedActivities(),
      ]);

      if (this.#isDestroyed) return;

      this.#handleNewActivities(
        mergeSortedActivities(
          newFinalizedActivities,
          this.#socketConfirmedActionsStash.splice(0),
        ),
        pendingActivities,
      );

      this.#doesNeedToRestoreHistory = false;
    } finally {
      if (!this.#isDestroyed) {
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };

  async #loadNewFinalizedActivities() {
    while (!this.#isDestroyed) {
      try {
        return await fetchActions({
          network: this.#network,
          filter: { address: this.#address },
          walletAddress: this.#address,
          fromTimestamp: this.#newestConfirmedActivityTimestamp,
          limit: FIRST_TRANSACTIONS_LIMIT,
        });
      } catch (err) {
        logDebugError('loadNewFinalizedActivities', err);

        if (this.#isDestroyed || !this.#doesNeedToRestoreHistory) {
          break;
        }

        await focusAwareDelay(...periodToMs(this.#minPollDelay));
      }
    }

    return [];
  }

  /** The method expected one of `allPendingActivities` and `pendingUpdates`, not both at the same time */
  #handleNewActivities(
    finalizedActivities: ApiActivity[],
    allPendingActivities?: ApiActivity[],
    pendingUpdates?: ActivitiesUpdate[],
  ) {
    // If nothing new, do nothing
    if (!finalizedActivities.length && !(allPendingActivities || pendingUpdates?.length)) {
      return;
    }

    if (finalizedActivities.length) {
      // Track the newest finalized activity timestamp to know where to resume loading from
      this.#newestConfirmedActivityTimestamp = finalizedActivities[0].timestamp;
    }
    this.#pendingActivities.update(finalizedActivities, allPendingActivities, pendingUpdates);
    this.#updateListeners.runCallbacks(finalizedActivities, this.#pendingActivities.all);
  }
}

async function loadPendingActivities(network: ApiNetwork, address: string) {
  try {
    return await fetchPendingActions(network, address);
  } catch (err) {
    logDebugError('loadPendingActivities', err);
    return undefined;
  }
}

/**
 * Splits socket updates into two streams:
 * - finalizedActivities: activities with finality='finalized' that have actual content (immutable, won't change)
 * - pendingUpdates: all other updates including:
 *   - finality='pending'/'confirmed'/'signed' (can be updated or invalidated)
 *   - finality='finalized' with empty activities (invalidations that need to clear pending list)
 */
function splitSocketUpdates(updates: ActivitiesUpdate[]) {
  const pendingUpdates: ActivitiesUpdate[] = [];
  const finalizedActivities: ApiActivity[] = [];

  for (const update of updates) {
    if (update.finality === 'finalized' && update.activities.length) {
      finalizedActivities.push(...update.activities);
    } else {
      pendingUpdates.push(update);
    }
  }

  return { pendingUpdates, finalizedActivities: sortActivities(finalizedActivities) };
}

/**
 * Keeps the list of all current pending activities by merging the incoming updates.
 */
function managePendingActivities() {
  /** Sorted by timestamp descending */
  let pendingActivities: readonly ApiActivity[] = [];

  /**
   * External message hash normalized of the recently finalized activities.
   * Helps to avoid excessive pendings occurring because of race conditions that cause pendings to arrive after the
   * corresponding finalized activities. The race conditions can occur because of the socket and polling working together.
   *
   * There still can be situations where an older pending activity version replaces a newer one, but it is not a problem.
   */
  const finishedHashes = new Set<string>();

  function update(
    finalizedActivities: ApiActivity[],
    allPendingActivities?: readonly ApiActivity[],
    pendingUpdates?: ActivitiesUpdate[],
  ) {
    // All finalizedActivities have status='completed'/'failed' (set by resolveActivityStatus when finality='finalized'),
    // so we add all their hashes to finishedHashes to filter them out from pending list.
    rememberFinishedHashes(extractKey(finalizedActivities, 'externalMsgHashNorm'));

    if (allPendingActivities) {
      pendingActivities = sortActivities(allPendingActivities);
    } else if (pendingUpdates) {
      pendingActivities = mergePendingActivities(pendingActivities, pendingUpdates);
    }

    // Remove pending activities whose traces have been finalized
    pendingActivities = pendingActivities.filter(({ externalMsgHashNorm }) => !(
      externalMsgHashNorm && finishedHashes.has(externalMsgHashNorm)
    ));
  }

  function rememberFinishedHashes(messageHashNorms: Iterable<string | undefined>) {
    for (const hash of messageHashNorms) {
      if (hash !== undefined) {
        finishedHashes.add(hash);
      }
    }

    releaseFinishedHashesMemory();
  }

  function releaseFinishedHashesMemory() {
    // JS Set iterates the elements in the order of insertion.
    // Deleting elements from Set during iteration doesn't disrupt the iteration.
    // That is, this loop removes the oldest elements.
    for (const hash of finishedHashes) {
      if (finishedHashes.size <= FINISHED_HASH_MEMORY_SIZE) {
        break;
      }

      finishedHashes.delete(hash);
    }
  }

  return {
    get all() {
      return pendingActivities;
    },
    update,
  };
}

function mergePendingActivities(
  currentPendingActivities: readonly ApiActivity[], // Must be sorted by timestamp descending
  socketUpdates: ActivitiesUpdate[],
) {
  if (!socketUpdates.length) {
    return currentPendingActivities;
  }

  const hashesToRemove = new Set<string | undefined>(
    extractKey(socketUpdates, 'messageHashNormalized'),
  );

  return mergeSortedActivities(
    currentPendingActivities.filter(
      (activity) => !hashesToRemove.has(activity.externalMsgHashNorm),
    ),
    sortActivities(
      socketUpdates.flatMap((update) => update.finality !== 'finalized' ? update.activities : []),
    ),
  );
}
