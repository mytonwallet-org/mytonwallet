import type { FallbackPollingOptions } from './fallbackPollingScheduler';

import { CircuitOpenError } from '../../../util/circuit-breaker';
import { logDebugError } from '../../../util/logs';
import * as randomModule from '../../../util/random';
import { FallbackPollingScheduler } from './fallbackPollingScheduler';

jest.mock('../../../util/logs', () => ({
  logDebugError: jest.fn(),
}));

const JITTER_RATIO = 0.2;

// Plain numeric periods keep the focused/notFocused branches identical so the
// jitter math is the only variable under test.
const BASE_OPTIONS: FallbackPollingOptions = {
  pollOnStart: false,
  minPollDelay: 1,
  pollingStartDelay: 1000,
  pollingPeriod: 1000,
  forcedPollingPeriod: 1000,
};

describe('FallbackPollingScheduler', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.mocked(logDebugError).mockReset();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('suppresses circuit-open errors as transient polling failures', async () => {
    const poll = jest.fn().mockRejectedValue(new CircuitOpenError('https://toncenter.example'));
    const scheduler = new FallbackPollingScheduler(poll, false, {
      pollOnStart: true,
      minPollDelay: 1000,
      pollingStartDelay: 1000,
      pollingPeriod: 1000,
      forcedPollingPeriod: 1000,
    });

    await Promise.resolve();
    await Promise.resolve();

    expect(logDebugError).toHaveBeenCalledWith(
      'FallbackPollingScheduler poll failed (suppressed)',
      expect.any(CircuitOpenError),
    );

    scheduler.destroy();
  });
});

describe('FallbackPollingScheduler jitter', () => {
  let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

  beforeEach(() => {
    jest.useFakeTimers();
    randomSpy = jest.spyOn(randomModule, 'random');
  });

  afterEach(() => {
    randomSpy.mockRestore();
    jest.useRealTimers();
  });

  it('fires a forced recurring poll no earlier than the base period', async () => {
    randomSpy.mockReturnValue(0);
    const poll = jest.fn();
    const scheduler = new FallbackPollingScheduler(poll, true, BASE_OPTIONS);

    // A forced socket message resets the schedule in the "connected" branch.
    scheduler.onSocketMessage();

    await jest.advanceTimersByTimeAsync(999);
    expect(poll).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(1);
    expect(poll).toHaveBeenCalledTimes(1);

    scheduler.destroy();
  });

  it('fires a forced recurring poll no later than period * (1 + JITTER_RATIO)', async () => {
    // Drive `random` to its maximum argument so jitter is the full ratio.
    randomSpy.mockImplementation((_min, max) => max);
    const poll = jest.fn();
    const scheduler = new FallbackPollingScheduler(poll, true, BASE_OPTIONS);

    scheduler.onSocketMessage();

    const maxDelay = 1000 + Math.round(1000 * JITTER_RATIO);

    await jest.advanceTimersByTimeAsync(maxDelay - 1);
    expect(poll).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(1);
    expect(poll).toHaveBeenCalledTimes(1);

    scheduler.destroy();
  });

  it('fires the reconnect catch-up poll synchronously on connect', () => {
    // Zero schedule jitter and a large recurring period so the recurring poll stays out of the way;
    // the catch-up poll must run immediately on connect rather than waiting for any delay.
    randomSpy.mockReturnValue(0);
    const poll = jest.fn();
    // `pollOnStart: false` so the very first connect issues the catch-up poll
    // (with `pollOnStart: true` the first connect intentionally skips it).
    const scheduler = new FallbackPollingScheduler(poll, false, {
      ...BASE_OPTIONS,
      pollOnStart: false,
      pollingPeriod: 60_000,
      pollingStartDelay: 60_000,
      forcedPollingPeriod: 60_000,
    });

    scheduler.onSocketConnect();

    expect(poll).toHaveBeenCalledTimes(1);

    scheduler.destroy();
  });

  it('fires forceImmediatePoll synchronously, bypassing the schedule', () => {
    // Zero schedule jitter and a large recurring period so the recurring poll stays out of the way;
    // the forced poll must run immediately rather than waiting for any delay.
    randomSpy.mockReturnValue(0);
    const poll = jest.fn();
    const scheduler = new FallbackPollingScheduler(poll, true, {
      ...BASE_OPTIONS,
      pollingPeriod: 60_000,
      pollingStartDelay: 60_000,
      forcedPollingPeriod: 60_000,
    });

    scheduler.forceImmediatePoll();

    expect(poll).toHaveBeenCalledTimes(1);

    scheduler.destroy();
  });

  it('fires no further poll after destroy, including the pending recurring timer', async () => {
    randomSpy.mockReturnValue(0);
    const poll = jest.fn();
    const scheduler = new FallbackPollingScheduler(poll, true, BASE_OPTIONS);

    scheduler.onSocketMessage();

    scheduler.destroy();

    await jest.advanceTimersByTimeAsync(60_000);
    expect(poll).not.toHaveBeenCalled();
  });
});
