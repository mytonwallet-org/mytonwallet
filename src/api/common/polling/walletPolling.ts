import type { ApiChain, ApiNetwork } from '../../types';
import type { WalletWatcher } from '../websocket/abstractWsClient';
import type { FallbackPollingOptions } from './fallbackPollingScheduler';
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
  pollingOptions: FallbackPollingOptions;
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
  #minPollDelay: Period;
  #onUpdate: WalletPollingOptions['onUpdate'];

  #walletWatcher?: WalletWatcher;

  #fallbackPollingScheduler: FallbackPollingScheduler;

  #isDestroyed = false;

  /** Undefined when no update is pending. Otherwise, holds the `isConfident` value (see `onUpdate` for more details) */
  #pendingUpdate?: boolean;

  constructor(options: WalletPollingOptions) {
    this.#minPollDelay = options.pollingOptions.minPollDelay;
    this.#onUpdate = options.onUpdate;

    const doesSupportSocket = getChainConfig(options.chain).doesBackendSocketSupport;

    if (doesSupportSocket) {
      this.#walletWatcher = getBackendSocket(options.network).watchWallets(
        [{
          chain: options.chain,
          events: ['activity'],
          address: options.address,
        }],
        {
          onNewActivities: this.#handleSocketNewActivity,
          onConnect: this.#handleSocketConnect,
          onDisconnect: this.#handleSocketDisconnect,
        },
      );
    }

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(
      this.#triggerBackupNotifications,
      this.#walletWatcher?.isConnected ?? false,
      {
        ...options.pollingOptions,
        pollingStartDelay: doesSupportSocket ? options.pollingOptions.pollingStartDelay : undefined, // If the backend socket doesn't support this chain, the polling should start sooner
      },
    );
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
    await this.#onUpdate(isConfident);
  }, () => {
    const [ms, forceMs] = periodToMs(this.#minPollDelay);
    return focusAwareDelay(
      ms - UPDATE_CALLBACK_DELAY,
      forceMs - UPDATE_CALLBACK_DELAY,
    );
  });
}
