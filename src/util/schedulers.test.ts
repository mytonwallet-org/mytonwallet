import { createTaskQueue, pause, throttle, withTimeout } from './schedulers';

import Deferred from './Deferred';

const ALLOWED_CLOCK_DRIFT = 2;

describe('throttle', () => {
  it.concurrent('executes fn only once if called multiple times during pause', async () => {
    const fn = jest.fn();
    const throttleMs = 10;
    const throttled = throttle(fn, throttleMs);
    throttled();
    await pause(1);
    fn.mockReset();
    throttled();
    throttled();
    throttled();
    await pause(throttleMs * 2.5);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it.concurrent('waits the given ms before executing fn again', async () => {
    const calls: number[] = [];
    const throttleMs = 10;
    const throttled = throttle(() => calls.push(Date.now()), throttleMs);
    throttled();
    await pause(5);
    throttled();
    await pause(30);
    const actualDuration = calls[1] - calls[0];
    expect(calls.length).toBeGreaterThanOrEqual(2);
    expect(actualDuration).toBeGreaterThanOrEqual(throttleMs - ALLOWED_CLOCK_DRIFT);
  });

  it.concurrent('does not allow parallel execution of async fn', async () => {
    let running = 0;
    let maxRunning = 0;
    const throttled = throttle(async () => {
      running++;
      maxRunning = Math.max(maxRunning, running);
      await pause(10);
      running--;
    }, 1);
    throttled();
    throttled();
    throttled();
    await pause(40);
    expect(maxRunning).toBe(1);
  });

  it.concurrent('respects shouldRunFirst = false', async () => {
    const calls: number[] = [];
    const throttleMs = 10;
    const throttled = throttle(() => calls.push(Date.now()), throttleMs, false);
    const start = Date.now();
    throttled();
    await pause(15);
    const actualDuration = calls[0] - start;
    expect(calls.length).toBe(1);
    expect(actualDuration).toBeGreaterThanOrEqual(throttleMs - ALLOWED_CLOCK_DRIFT);
  });

  it.concurrent('supports a custom pause scheduler (function ms)', async () => {
    const msDeferred = new Deferred();
    const ms = jest.fn().mockReturnValue(msDeferred.promise);
    const fn = jest.fn();
    const throttled = throttle(fn, ms, false);
    throttled();
    await pause(1);
    expect(fn).not.toHaveBeenCalled();
    msDeferred.resolve();
    await pause(1);
    expect(fn).toHaveBeenCalled();
  });
});

describe('createTaskQueue', () => {
  it.concurrent('limits the concurrency', async () => {
    let runningCount = 0;
    let maxRunningCount = 0;
    let runCount = 0;
    const maxConcurrency = 3;

    const taskQueue = createTaskQueue(maxConcurrency);

    const runTask = taskQueue.wrap(async (lengthMs: number) => {
      runCount++;
      runningCount++;
      maxRunningCount = Math.max(maxRunningCount, runningCount);
      await pause(lengthMs);
      runningCount--;
    });

    await Promise.all([
      runTask(1).then(() => runTask(3)),
      runTask(2).then(() => runTask(4)),
      runTask(3).then(() => runTask(5)),
      runTask(4).then(() => runTask(1)),
      runTask(5),
    ]);

    expect(maxRunningCount).toBe(maxConcurrency);
    expect(runCount).toBe(9);
  });

  it.concurrent('executes the tasks in the input order', async () => {
    const taskOrder: number[] = [];

    const taskQueue = createTaskQueue(2);

    const runTask = taskQueue.wrap(async (index: number, lengthMs: number) => {
      taskOrder.push(index);
      await pause(lengthMs);
    });

    await Promise.all([
      runTask(0, 3),
      runTask(1, 5),
      runTask(2, 6),
      runTask(3, 2),
      runTask(4, 4),
      runTask(5, 3),
      runTask(6, 1),
    ]);

    expect(taskOrder).toEqual([0, 1, 2, 3, 4, 5, 6]);
  });

  it.concurrent('returns the task results', async () => {
    const expectedResults: PromiseSettledResult<unknown>[] = [
      { status: 'fulfilled', value: 'result1' },
      { status: 'rejected', reason: new Error('error2') },
      { status: 'fulfilled', value: 'result3' },
    ];

    const taskQueue = createTaskQueue(2);

    const results = await Promise.allSettled(expectedResults.map((result) => {
      return taskQueue.run(async () => {
        await pause(1);
        if (result.status === 'fulfilled') {
          return result.value;
        } else {
          throw result.reason;
        }
      });
    }));

    expect(results).toEqual(expectedResults);
  });
});

describe('withTimeout', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('resolves with the value when the promise settles first', async () => {
    await expect(withTimeout(Promise.resolve('ok'), 1000, 'fallback')).resolves.toBe('ok');
  });

  it('resolves with fallback when the promise rejects', async () => {
    await expect(withTimeout(Promise.reject(new Error('x')), 1000, 'fallback')).resolves.toBe('fallback');
  });

  it('resolves with fallback when the timer fires first on a pending promise', async () => {
    const p = withTimeout(new Promise<string>(() => {}), 1000, 'fallback');
    await jest.advanceTimersByTimeAsync(1000);
    await expect(p).resolves.toBe('fallback');
  });

  it('calls onTimeout when the timer fires first', async () => {
    const onTimeout = jest.fn();
    const p = withTimeout(new Promise<string>(() => {}), 1000, 'fallback', onTimeout);
    await jest.advanceTimersByTimeAsync(1000);
    await expect(p).resolves.toBe('fallback');
    expect(onTimeout).toHaveBeenCalledTimes(1);
  });

  it('does not call onTimeout when the promise settles first', async () => {
    const onTimeout = jest.fn();
    await expect(withTimeout(Promise.resolve('ok'), 1000, 'fallback', onTimeout)).resolves.toBe('ok');
    expect(onTimeout).not.toHaveBeenCalled();
  });
});
