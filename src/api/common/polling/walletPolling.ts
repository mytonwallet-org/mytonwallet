import type { ApiChain, ApiNetwork } from '../../types';
import type { WalletWatcher } from '../backendSocket';
import type { Period } from './utils';

import { getChainConfig } from '../../../util/chain';
import { focusAwareDelay } from '../../../util/focusAwareDelay';
import { pause, throttle } from '../../../util/schedulers';
import { getBackendSocket } from '../backendSocket';
import { FallbackPollingScheduler } from './fallbackPollingScheduler';
import { periodToMs } from './utils';

const UPDATE_CALLBACK_DELAY = 10;

export interface WalletPollingOptions {
  chain: ApiChain;
  network: ApiNetwork;
  address: string;
  /** Whether an update should be triggerred when the polling object is created */
  updateOnStart?: boolean;
  /** The minimum delay between `onUpdate` calls */
  minUpdateDelay: Period;
  /**
   * How much time the fallback polling will start after the socket disconnects.
   * Also applies at the very beginning (until the socket is connected).
   */
  fallbackUpdateStartDelay: Period;
  /** Update periods when the socket is disconnected */
  fallbackUpdatePeriod: Period;
  /** Update periods when the socket is connected but there is no new activity coming */
  forceUpdatePeriod: Period;
  /**
   * Called whenever the wallet data should be updated.
   * The polling always waits until the returned promise resolves before running this callback again.
   *
   * @param isConfident `true` when the update was reported by the socket. `false` when the update is initiated by a
   *  timer. If `false`, the app should check a piece of wallet before refreshing the whole data (to avoid excessive
   *  network requests).
   */
  onUpdate(isConfident: boolean): MaybePromise<unknown>;
}

/**
 * Helps polling wallet balance and activity. Uses the backend websocket as the primary signal source and falls back
 * to simple time intervals if the websocket is unavailable. It doesn't provide the updated data, it provides signals
 * when the data should be fetched using the plain HTTP API.
 */
export class WalletPolling {
  #options: WalletPollingOptions;

  #walletWatcher?: WalletWatcher;

  #fallbackPollingScheduler: FallbackPollingScheduler;

  #isDestroyed = false;

  /** Undefined when no update is pending. Otherwise, holds the `isConfident` value (see `onUpdate` for more details) */
  #pendingUpdate?: boolean;

  constructor(options: WalletPollingOptions) {
    this.#options = options;
    const doesSupportSocket = getChainConfig(options.chain).doesBackendSocketSupport;

    if (doesSupportSocket) {
      this.#walletWatcher = getBackendSocket(options.network).watchWallets(
        [{
          chain: options.chain,
          events: ['activity'],
          address: options.address,
        }],
        {
          onNewActivity: this.#handleSocketNewActivity,
          onConnect: this.#handleSocketConnect,
          onDisconnect: this.#handleSocketDisconnect,
        },
      );
    }

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(this.#walletWatcher?.isConnected ?? false, {
      pollOnStart: options.updateOnStart,
      minPollDelay: options.minUpdateDelay,
      pollingStartDelay: doesSupportSocket ? options.fallbackUpdateStartDelay : undefined, // If the backend socket doesn't support this chain, the polling should start sooner
      pollingPeriod: options.fallbackUpdatePeriod,
      forcedPollingPeriod: options.forceUpdatePeriod,
      poll: this.#triggerBackupNotifications,
    });
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#walletWatcher?.destroy();
    this.#fallbackPollingScheduler.destroy();
  }

  #handleSocketNewActivity = () => {
    this.#pendingUpdate = true;
    this.#runUpdateCallback();
    this.#fallbackPollingScheduler.onSocketMessage();
  };

  #handleSocketConnect = () => {
    this.#triggerBackupNotifications();
    this.#fallbackPollingScheduler.onSocketConnect();
  };

  #handleSocketDisconnect = () => {
    this.#fallbackPollingScheduler.onSocketDisconnect();
  };

  #triggerBackupNotifications = () => {
    this.#pendingUpdate ??= false;
    this.#runUpdateCallback();
  };

  #runUpdateCallback = throttle(async () => {
    if (this.#pendingUpdate === undefined) {
      return;
    }

    // To let sneak in the updates arriving in short-time batches. Otherwise, they will cause another onUpdate call.
    await pause(UPDATE_CALLBACK_DELAY);
    if (this.#isDestroyed) return;

    const isConfident = this.#pendingUpdate;
    this.#pendingUpdate = undefined;
    await this.#options.onUpdate(isConfident);
  }, () => {
    const [ms, forceMs] = periodToMs(this.#options.minUpdateDelay);
    return focusAwareDelay(
      ms - UPDATE_CALLBACK_DELAY,
      forceMs - UPDATE_CALLBACK_DELAY,
    );
  });
}
