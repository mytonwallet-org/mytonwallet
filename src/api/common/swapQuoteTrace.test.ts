import Deferred from '../../util/Deferred';
import { addLog } from '../../util/logs';
import { traceSwapQuote } from './swapQuoteTrace';

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_AIR_APP: true,
}));

jest.mock('../../util/logs', () => ({ addLog: jest.fn() }));

describe('swap quote diagnostics', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.mocked(addLog).mockClear();
    jest.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  function lines() {
    return jest.mocked(addLog).mock.calls.map(([entry]) => entry.message);
  }

  it('distinguishes concurrent calls waiting for configuration and a response body', async () => {
    const config = new Deferred<void>();
    const body = new Deferred<string>();
    const first = traceSwapQuote('exactIn', async (stage) => {
      stage('config');
      await config.promise;
    });
    const second = traceSwapQuote('exactOut', async (stage) => {
      stage('http');
      stage('body', 200);
      return body.promise;
    });

    await jest.advanceTimersByTimeAsync(10000);
    const slow = lines().filter((line) => line.endsWith('slow'));
    expect(slow).toHaveLength(2);
    expect(slow[0]).toMatch(/elapsedMs=10000 stage=config slow$/);
    expect(slow[1]).toMatch(/elapsedMs=10000 stage=body slow$/);
    expect(slow[0].match(/call=\d+/)?.[0]).not.toBe(slow[1].match(/call=\d+/)?.[0]);
    expect(lines()).toEqual(expect.arrayContaining([expect.stringMatching(/stage=body begin status=200$/)]));

    body.resolve('quote');
    expect(await second).toBe('quote');
    config.resolve();
    await first;
    expect(lines().filter((line) => line.endsWith('returned'))).toHaveLength(2);
    // eslint-disable-next-line no-console
    expect(jest.mocked(console.log).mock.calls.map(([line]) => line)).toEqual(lines());
    expect(jest.getTimerCount()).toBe(0);
  });

  it('clears the watchdog on failure and logs only the error type', async () => {
    const error = new TypeError('wallet address and response data must not appear');
    const promise = traceSwapQuote('exactIn', (stage) => {
      stage('http');
      return Promise.reject(error);
    });
    await expect(promise).rejects.toBe(error);
    await jest.advanceTimersByTimeAsync(20000);
    expect(lines().at(-1)).toMatch(/stage=http failed type=TypeError$/);
    expect(lines().join('\n')).not.toContain(error.message);
    expect(lines().some((line) => line.endsWith('slow'))).toBe(false);
    expect(jest.getTimerCount()).toBe(0);
  });
});
