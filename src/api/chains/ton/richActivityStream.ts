import type { ApiActivity } from '../../types';
import type { ActivityStream, OnActivityUpdate, OnLoadingChange } from './toncenter';

import { parseAccountId } from '../../../util/account';
import { mergeSortedActivities } from '../../../util/activities/order';
import { createCallbackManager } from '../../../util/callbacks';
import { areSortedArraysEqual, extractKey } from '../../../util/iteratees';
import { OrGate } from '../../../util/orGate';
import { throttle } from '../../../util/schedulers';
import { fetchStoredWallet } from '../../common/accounts';
import { swapReplaceActivities } from '../../common/swap';
import { reloadIncompleteActivities } from './activities';

/**
 * Like `ActivityStream` but applies `enrichActivities` to the confirmed activities.
 *
 * @see enrichActivities
 */
export class RichActivityStream {
  #accountId: string;

  /** Sorted by timestamp descending */
  #confirmedActivitiesToReport: ApiActivity[] = [];

  #pendingActivities = managePendingActivities();

  #isLoading = new OrGate<'raw' | 'enrich'>((isLoading) => this.#loadingListeners.runCallbacks(isLoading));

  #updateListeners = createCallbackManager<OnActivityUpdate>();
  #triggerUpdateListeners = deduplicateActivityUpdates(this.#updateListeners.runCallbacks);
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #isDestroyed = false;

  #onDestroy: NoneToVoidFunction[];

  constructor(
    accountId: string,
    rawActivityStream: ActivityStream,
  ) {
    this.#accountId = accountId;

    this.#onDestroy = [
      rawActivityStream.onUpdate(this.#handleRawActivitiesUpdate),
      rawActivityStream.onLoadingChange((isLoading) => this.#isLoading.toggle('raw', isLoading)),
    ];
  }

  /**
   * Registers a callback firing then new activities arrive.
   * The callback is throttled under the hood.
   */
  public onUpdate(callback: OnActivityUpdate) {
    return this.#updateListeners.addCallback(callback);
  }

  /**
   * Registers a callback firing when the data from HTTP endpoints starts of finishes loading.
   * The "loading" state includes the time when `rawActivityStream` is polling.
   */
  public onLoadingChange(callback: OnLoadingChange) {
    return this.#loadingListeners.addCallback(callback);
  }

  public destroy() {
    this.#isDestroyed = true;

    for (const unsubscribe of this.#onDestroy) {
      unsubscribe();
    }
  }

  #handleRawActivitiesUpdate: OnActivityUpdate = (confirmedActivities, pendingActivities) => {
    this.#pendingActivities.updateAfterRawUpdate(confirmedActivities, pendingActivities);
    this.#reportActivities([]);

    if (confirmedActivities.length) {
      this.#confirmedActivitiesToReport.unshift(...confirmedActivities);
      this.#enrichAndReportActivities();
    }
  };

  // Using `throttle` to batch the new activities and ensure that they are reported in the order they were received
  #enrichAndReportActivities = throttle(async () => {
    if (this.#isDestroyed) return;

    try {
      this.#isLoading.on('enrich');

      const rawConfirmedActivities = this.#confirmedActivitiesToReport;
      this.#confirmedActivitiesToReport = [];
      const richConfirmedActivities = await enrichActivities(this.#accountId, rawConfirmedActivities);

      this.#pendingActivities.updateAfterEnrichment(rawConfirmedActivities);
      this.#reportActivities(richConfirmedActivities);
    } finally {
      this.#isLoading.off('enrich');
    }
  }, 0);

  #reportActivities(confirmedActivities: ApiActivity[]) {
    if (!this.#isDestroyed) {
      this.#triggerUpdateListeners(confirmedActivities, this.#pendingActivities.all);
    }
  }
}

/**
 * Manages pending activities to ensure that switching activities from pending to confirmed is seamless.
 * If not used, the pending activities received from `ActivityStream` will disappear temporarily while the confirmed
 * activities are being enriched.
 */
function managePendingActivities() {
  /** The latest pending activities provided by `rawActivityStream` */
  let pendingActivities: readonly ApiActivity[] = [];
  /** Pending activities that no longer exist but their corresponding confirmed activities are being enriched */
  let zombiePendingActivities: ApiActivity[] = [];

  const updateAfterRawUpdate: OnActivityUpdate = (confirmedActivities, newPendingActivities) => {
    const confirmedHashes = new Set(extractKey(confirmedActivities, 'externalMsgHashNorm'));

    zombiePendingActivities = mergeSortedActivities(
      zombiePendingActivities,
      pendingActivities.filter((activity) => confirmedHashes.has(activity.externalMsgHashNorm)),
    );

    pendingActivities = newPendingActivities;
  };

  const updateAfterEnrichment = (rawConfirmedActivities: ApiActivity[]) => {
    const confirmedHashes = new Set(extractKey(rawConfirmedActivities, 'externalMsgHashNorm'));

    zombiePendingActivities = zombiePendingActivities
      .filter((activity) => !confirmedHashes.has(activity.externalMsgHashNorm));
  };

  return {
    /** Sorted by timestamp descending */
    get all() {
      return mergeSortedActivities(pendingActivities, zombiePendingActivities);
    },
    updateAfterRawUpdate,
    updateAfterEnrichment,
  };
}

/**
 * Makes sure the update callback is not called uselessly. For example, with no confirmed activities and with the
 * same pending activities.
 */
function deduplicateActivityUpdates(onUpdate: OnActivityUpdate): OnActivityUpdate {
  let lastPendingActivities: readonly ApiActivity[] = [];

  return (newConfirmedActivities, pendingActivities) => {
    if (newConfirmedActivities.length || !areSortedArraysEqual(lastPendingActivities, pendingActivities)) {
      onUpdate(newConfirmedActivities, pendingActivities);
    }

    lastPendingActivities = pendingActivities;
  };
}

async function enrichActivities(accountId: string, activities: ApiActivity[]) {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'ton');

  activities = await reloadIncompleteActivities(network, address, activities);
  activities = await swapReplaceActivities(accountId, activities, undefined, true);

  return activities;
}
