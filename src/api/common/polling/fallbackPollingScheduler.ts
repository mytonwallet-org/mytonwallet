import type { Period } from './utils';

import { CircuitOpenError } from '../../../util/circuit-breaker';
import { focusAwareDelay, onFocusAwareDelay } from '../../../util/focusAwareDelay';
import { logDebugError } from '../../../util/logs';
import { random } from '../../../util/random';
import { throttle } from '../../../util/schedulers';
import { ApiServerError } from '../../errors';
import { periodToMs } from './utils';

export type PollCallback = (isInitial?: boolean) => MaybePromise<void>;

/**
 * The maximum fraction by which a scheduled delay can be randomly extended.
 * Many clients schedule the same periods in unison, so a positive per-delay
 * jitter de-phases their polls and flattens the resulting load waves.
 */
const JITTER_RATIO = 0.2;

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

  /**
   * Stays `false` until the socket connects for the first time.
   * On the very first connection, `pollOnStart` (if set) has already issued a fresh HTTP
   * request — there is nothing to catch up on, so `onSocketConnect` must not trigger a
   * second poll regardless of whether that initial request has finished.
   * After the first connect this becomes `true`, so every subsequent reconnect re-polls
   * as expected (to pick up balance changes that arrived while the socket was gone).
   */
  #hasEverConnected = false;

  /** `poll` is never executed in parallel */
  constructor(poll: PollCallback, isSocketConnected: boolean, options: FallbackPollingOptions) {
    this.#rawPoll = poll;
    this.#options = options;

    this.#schedulePolling(isSocketConnected);

    if (options.pollOnStart) {
      this.#poll(true);
    }
  }

  /** Call this method when the socket source of data becomes available */
  public onSocketConnect() {
    if (this.#isDestroyed) return;
    this.#schedulePolling(true);
    // On the very first connect, skip the poll when pollOnStart already issued one.
    // On every reconnect, poll immediately to catch updates missed during the outage.
    if (this.#hasEverConnected || !this.#options.pollOnStart) {
      this.#poll(true);
    }
    this.#hasEverConnected = true;
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
  #poll = throttle(async (isInitial?: boolean) => {
    if (this.#isDestroyed) return;

    try {
      await this.#rawPoll(isInitial);
    } catch (err: unknown) {
      // Polling re-issues requests, so transient HTTP failures are suppressed -
      // alerting on each cycle just creates user-visible noise scaled by poller count.
      if (err instanceof ApiServerError || err instanceof CircuitOpenError) {
        logDebugError('FallbackPollingScheduler poll failed (suppressed)', err);
        return;
      }
      throw err;
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
      const delay = jitterPeriodMs(periodToMs(isFirst ? firstPause : nextPause));
      this.#cancelScheduledPoll = onFocusAwareDelay(...delay, () => {
        schedule();
        this.#poll();
      });
    };

    schedule(true);
  }
}

/**
 * Extends a `periodToMs` tuple by a single shared random ratio up to `JITTER_RATIO`, keeping every
 * delay within `[period, period * (1 + JITTER_RATIO)]`. Both elements are scaled by the same factor,
 * so each gets a spread proportional to its own period (a shared absolute offset would under-jitter
 * the larger `forceMs`), and `forceMs >= ms` is preserved because the factor is identical and `>= 1`
 * and `Math.round` is monotonic (`onFocusAwareDelay` relies on `forceMs - ms` being non-negative).
 */
function jitterPeriodMs([ms, forceMs]: [number, number]): [number, number] {
  // A single shared multiplier keeps both delays jittered by the same fraction (so `forceMs >= ms`
  // is preserved) while giving each its own period-proportional spread, unlike a shared absolute
  // offset which under-jitters the larger (notFocused) period.
  const factor = 1 + random(0, Math.round(JITTER_RATIO * 1000)) / 1000;
  return [Math.round(ms * factor), Math.round(forceMs * factor)];
}
