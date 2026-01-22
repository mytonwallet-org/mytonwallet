import type { Period } from './utils';

import { focusAwareDelay, onFocusAwareDelay } from '../../../util/focusAwareDelay';
import { handleError } from '../../../util/handleError';
import { throttle } from '../../../util/schedulers';
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
   * If omitted, will be the same as `pollingPeriod`.
   */
  pollingStartDelay?: Period;
  /** Update periods when the socket is disconnected */
  pollingPeriod: Period;
  /** Update periods when the socket is connected but there are no messages */
  forcedPollingPeriod: Period;
}

/**
 * Schedules regular polling when the socket is disconnected.
 */
export class FallbackPollingScheduler {
  #rawPoll: PollCallback;
  #options: FallbackPollingOptions;

  #cancelScheduledPoll?: NoneToVoidFunction;

  #isDestroyed = false;

  /** `poll` is never executed in parallel */
  constructor(poll: PollCallback, isSocketConnected: boolean, options: FallbackPollingOptions) {
    this.#rawPoll = poll;
    this.#options = options;

    this.#schedulePolling(isSocketConnected);

    if (options.pollOnStart) {
      this.#poll();
    }
  }

  /** Call this method when the socket source of data becomes available */
  public onSocketConnect() {
    if (this.#isDestroyed) return;
    this.#schedulePolling(true);
    this.#poll();
  }

  /** Call this method when the socket source of data becomes unavailable */
  public onSocketDisconnect() {
    if (this.#isDestroyed) return;
    this.#schedulePolling(false);
  }

  /** Call this method when the socket shows that it's alive */
  public onSocketMessage() {
    if (this.#isDestroyed) return;
    this.#schedulePolling(true);
  }

  /** Forces an immediate poll, bypassing the normal schedule. Useful for error recovery. */
  public forceImmediatePoll() {
    if (this.#isDestroyed) return;
    this.#poll();
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#cancelScheduledPoll?.();
  }

  // Using `throttle` to avoid parallel execution.
  #poll = throttle(async () => {
    if (this.#isDestroyed) return;

    try {
      await this.#rawPoll();
    } catch (err: any) {
      handleError(err);
    }
  }, () => {
    return focusAwareDelay(...periodToMs(this.#options.minPollDelay));
  });

  #schedulePolling(isSocketConnected: boolean) {
    this.#cancelScheduledPoll?.();

    const { pollingPeriod, pollingStartDelay = pollingPeriod, forcedPollingPeriod } = this.#options;
    const firstPause = isSocketConnected ? forcedPollingPeriod : pollingStartDelay;
    const nextPause = isSocketConnected ? forcedPollingPeriod : pollingPeriod;

    const schedule = (isFirst?: boolean) => {
      this.#cancelScheduledPoll = onFocusAwareDelay(...periodToMs(isFirst ? firstPause : nextPause), () => {
        schedule();
        this.#poll();
      });
    };

    schedule(true);
  }
}
