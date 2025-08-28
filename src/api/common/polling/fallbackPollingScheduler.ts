import type { Period } from './utils';

import { focusAwareDelay, onFocusAwareDelay } from '../../../util/focusAwareDelay';
import { handleError } from '../../../util/handleError';
import { setCancellableTimeout, throttle } from '../../../util/schedulers';
import { periodToMs } from './utils';

export type PollCallback = () => MaybePromise<void>;

export interface FallbackPollingOptions {
  /** Whether `poll` should be called when the polling object is created */
  pollOnStart?: boolean;
  /** The minimum delay between `poll` calls */
  minPollDelay: Period;
  /**
   * How much time the polling will start after the socket disconnects.
   * Also applies at the very beginning (until the socket is connected).
   */
  pollingStartDelay: number;
  /** Update periods when the socket is disconnected */
  pollingPeriod: Period;
  /** Update periods when the socket is connected but there are no messages */
  forcedPollingPeriod: Period;
  /** Never executed in parallel */
  poll: PollCallback;
}

/**
 * Schedules regular polling when the socket is disconnected.
 */
export class FallbackPollingScheduler {
  #options: FallbackPollingOptions;

  #cancelScheduledPoll?: NoneToVoidFunction;

  #isDestroyed = false;

  constructor(isSocketConnected: boolean, options: FallbackPollingOptions) {
    this.#options = options;

    if (isSocketConnected) {
      this.#scheduleForcedPolling();
    } else {
      this.#schedulePolling();
    }

    if (options.pollOnStart) {
      this.#poll();
    }
  }

  /** Call this method when the socket source of data becomes available */
  public onSocketConnect() {
    if (this.#isDestroyed) return;
    this.#scheduleForcedPolling();
    this.#poll();
  }

  /** Call this method when the socket source of data becomes unavailable */
  public onSocketDisconnect() {
    if (this.#isDestroyed) return;
    this.#schedulePolling();
  }

  /** Call this method when the socket shows that it's alive */
  public onSocketMessage() {
    if (this.#isDestroyed) return;
    this.#scheduleForcedPolling();
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#cancelScheduledPoll?.();
  }

  // Using `throttle` to avoid parallel execution.
  #poll = throttle(async () => {
    if (this.#isDestroyed) return;

    try {
      await this.#options.poll();
    } catch (err: any) {
      handleError(err);
    }
  }, () => {
    return focusAwareDelay(...periodToMs(this.#options.minPollDelay));
  });

  /** Sets up a polling running when the socket is disconnected */
  #schedulePolling() {
    this.#cancelScheduledPoll?.();

    const { pollingStartDelay, pollingPeriod } = this.#options;

    const handleTimeout = () => {
      this.#cancelScheduledPoll = onFocusAwareDelay(...periodToMs(pollingPeriod), handleTimeout);
      this.#poll();
    };

    this.#cancelScheduledPoll = setCancellableTimeout(pollingStartDelay, handleTimeout);
  }

  /** Sets up a polling running when the socket is connected (to mitigate network and backend problems) */
  #scheduleForcedPolling() {
    this.#cancelScheduledPoll?.();

    const schedule = () => {
      const { forcedPollingPeriod } = this.#options;
      this.#cancelScheduledPoll = onFocusAwareDelay(...periodToMs(forcedPollingPeriod), () => {
        schedule();
        this.#poll();
      });
    };

    schedule();
  }
}
