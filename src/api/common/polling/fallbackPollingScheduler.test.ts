import type { FallbackPollingOptions } from './fallbackPollingScheduler';

import { CircuitOpenError } from '../../../util/circuitBreaker';
import Deferred from '../../../util/Deferred';
import { setIsAppFocused } from '../../../util/focusAwareDelay';
import { logDebugError } from '../../../util/logs';
import * as randomModule from '../../../util/random';
import { MINUTE, SEC } from '../../constants';
import { FallbackPollingScheduler } from './fallbackPollingScheduler';
import { activeWalletTiming, inactiveWalletTiming } from './utils';

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

const QUEUED_POLL_OPTIONS: FallbackPollingOptions = {
  pollOnStart: true,
  minPollDelay: 100,
  pollingStartDelay: 3000,
  pollingPeriod: 10_000,
  forcedPollingPeriod: 10_000,
};

const SCHEDULE_CHANGES = ['onSocketConnect', 'onSocketMessage', 'onSocketDisconnect'] as const;

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

describe.each([true, false])('Wallet polling timing (focused: %s)', (isFocused) => {
  let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

  beforeEach(() => {
    jest.useFakeTimers();
    setIsAppFocused(isFocused);
    randomSpy = jest.spyOn(randomModule, 'random').mockReturnValue(0);
  });

  afterEach(() => {
    jest.clearAllTimers();
    setIsAppFocused(true);
    randomSpy.mockRestore();
    jest.useRealTimers();
  });

  it.each([
    {
      name: 'active wallet with a connected socket and no messages',
      options: activeWalletTiming,
      isSocketConnected: true,
      initialPollCount: 1,
      firstDelay: 5 * MINUTE,
      nextDelay: 5 * MINUTE,
    },
    {
      name: 'active wallet with a disconnected socket',
      options: activeWalletTiming,
      isSocketConnected: false,
      initialPollCount: 1,
      firstDelay: 3 * SEC,
      nextDelay: isFocused ? 3 * SEC : 10 * SEC,
    },
    {
      name: 'inactive wallet with a connected socket and no messages',
      options: inactiveWalletTiming,
      isSocketConnected: true,
      initialPollCount: 0,
      firstDelay: isFocused ? 2 * MINUTE : 5 * MINUTE,
      nextDelay: isFocused ? 2 * MINUTE : 5 * MINUTE,
    },
    {
      name: 'inactive wallet with a disconnected socket',
      options: inactiveWalletTiming,
      isSocketConnected: false,
      initialPollCount: 0,
      firstDelay: 5 * SEC,
      nextDelay: isFocused ? 30 * SEC : MINUTE,
    },
  ])('preserves the start and recurring schedule for an $name', async ({
    options, isSocketConnected, initialPollCount, firstDelay, nextDelay,
  }) => {
    const poll = jest.fn();
    const scheduler = new FallbackPollingScheduler(poll, isSocketConnected, options);

    expect(poll).toHaveBeenCalledTimes(initialPollCount);
    if (initialPollCount) {
      expect(poll).toHaveBeenCalledWith(true);
    }

    await jest.advanceTimersByTimeAsync(firstDelay - 1);
    expect(poll).toHaveBeenCalledTimes(initialPollCount);

    // An unfocused delay can complete through a second zero-delay timer
    await jest.advanceTimersByTimeAsync(2);
    expect(poll).toHaveBeenCalledTimes(initialPollCount + 1);

    await jest.advanceTimersByTimeAsync(nextDelay - 2);
    expect(poll).toHaveBeenCalledTimes(initialPollCount + 1);

    await jest.advanceTimersByTimeAsync(3);
    expect(poll).toHaveBeenCalledTimes(initialPollCount + 2);

    scheduler.destroy();
  });
});

describe('FallbackPollingScheduler queued polls', () => {
  let randomSpy: jest.SpiedFunction<typeof randomModule.random>;

  beforeEach(() => {
    jest.useFakeTimers();
    randomSpy = jest.spyOn(randomModule, 'random').mockReturnValue(0);
  });

  afterEach(() => {
    randomSpy.mockRestore();
    jest.useRealTimers();
  });

  it.each(SCHEDULE_CHANGES)('drops an old timer queued during the initial poll after %s', async (changeSchedule) => {
    const firstPoll = new Deferred();
    const poll = jest.fn().mockReturnValueOnce(firstPoll.promise);
    const scheduler = new FallbackPollingScheduler(poll, false, QUEUED_POLL_OPTIONS);

    await jest.advanceTimersByTimeAsync(3001);
    expect(poll).toHaveBeenCalledTimes(1);

    scheduler[changeSchedule]();
    firstPoll.resolve();
    await jest.advanceTimersByTimeAsync(101);

    expect(poll).toHaveBeenCalledTimes(1);
    expect(poll).toHaveBeenCalledWith(true);

    scheduler.destroy();
  });

  describe.each([false, true])('with a later timer queued: %s', (hasLaterTimer) => {
    it.each(SCHEDULE_CHANGES)('preserves forceImmediatePoll after %s', async (changeSchedule) => {
      const firstPoll = new Deferred();
      const poll = jest.fn().mockReturnValueOnce(firstPoll.promise);
      const scheduler = new FallbackPollingScheduler(poll, false, QUEUED_POLL_OPTIONS);

      scheduler.forceImmediatePoll();
      if (hasLaterTimer) {
        await jest.advanceTimersByTimeAsync(3001);
      }
      scheduler[changeSchedule]();

      expect(poll).toHaveBeenCalledTimes(1);
      firstPoll.resolve();
      await jest.advanceTimersByTimeAsync(101);

      expect(poll.mock.calls).toEqual([[true], [undefined]]);

      scheduler.destroy();
    });
  });

  it.each([false, true])(
    'preserves a queued connect poll and its initial flag with pollOnEverySocketConnect=%s',
    async (pollOnEverySocketConnect) => {
      const firstPoll = new Deferred();
      const poll = jest.fn().mockReturnValueOnce(firstPoll.promise);
      const scheduler = new FallbackPollingScheduler(poll, false, {
        ...QUEUED_POLL_OPTIONS,
        pollOnEverySocketConnect,
      });

      scheduler.onSocketConnect();
      if (!pollOnEverySocketConnect) {
        scheduler.onSocketDisconnect();
        scheduler.onSocketConnect();
      }

      await jest.advanceTimersByTimeAsync(10_001);
      scheduler.onSocketMessage();
      expect(poll).toHaveBeenCalledTimes(1);

      firstPoll.resolve();
      await jest.advanceTimersByTimeAsync(101);

      expect(poll.mock.calls).toEqual([[true], [true]]);

      scheduler.destroy();
    },
  );

  it('runs a queued current-schedule timer and keeps polling', async () => {
    const firstPoll = new Deferred();
    const poll = jest.fn().mockReturnValueOnce(firstPoll.promise);
    const scheduler = new FallbackPollingScheduler(poll, false, QUEUED_POLL_OPTIONS);

    await jest.advanceTimersByTimeAsync(3001);
    expect(poll).toHaveBeenCalledTimes(1);

    firstPoll.resolve();
    await jest.advanceTimersByTimeAsync(101);
    expect(poll.mock.calls).toEqual([[true], [undefined]]);

    await jest.advanceTimersByTimeAsync(20_000);
    expect(poll.mock.calls).toEqual([[true], [undefined], [undefined], [undefined]]);

    scheduler.destroy();
  });

  it('lets a running timer poll finish after a schedule change', async () => {
    const timerPoll = new Deferred();
    const onComplete = jest.fn();
    const poll = jest.fn(() => timerPoll.promise.then(onComplete));
    const scheduler = new FallbackPollingScheduler(poll, false, {
      ...QUEUED_POLL_OPTIONS,
      pollOnStart: false,
    });

    await jest.advanceTimersByTimeAsync(3001);
    expect(poll).toHaveBeenCalledTimes(1);

    scheduler.onSocketMessage();
    timerPoll.resolve();
    await jest.advanceTimersByTimeAsync(101);

    expect(onComplete).toHaveBeenCalledTimes(1);
    expect(poll.mock.calls).toEqual([[undefined]]);

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
