import { createUrgentFetchDemand, FetchDemand } from './fetchDemand';
import withCacheAsync, { withFetchDemandCacheAsync } from './withCacheAsync';

describe('withFetchDemandCacheAsync', () => {
  it('shares one call between callers with and without a demand', async () => {
    const fn = jest.fn((_demand: FetchDemand, address: string) => Promise.resolve(address));
    const cached = withFetchDemandCacheAsync(fn);

    const results = await Promise.all([
      cached('address'),
      cached('address', createUrgentFetchDemand()),
    ]);

    expect(results).toEqual(['address', 'address']);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('gives the work a demand of its own as the first argument', async () => {
    const fn = jest.fn((_demand: FetchDemand, address: string) => Promise.resolve(address));
    const cached = withFetchDemandCacheAsync(fn);
    const callerDemand = createUrgentFetchDemand();

    await cached('address', callerDemand);

    const [workDemand, address] = fn.mock.calls[0];
    expect(workDemand).toBeInstanceOf(FetchDemand);
    expect(workDemand).not.toBe(callerDemand);
    expect(address).toBe('address');
  });

  it('lends the urgency of a caller to work that another caller started, until the work ends', async () => {
    let workDemand!: FetchDemand;
    let finishWork!: NoneToVoidFunction;
    const cached = withFetchDemandCacheAsync((demand, address: string) => {
      workDemand = demand;
      return new Promise<string>((resolve) => {
        finishWork = () => resolve(address);
      });
    });

    const fromBackground = cached('address');
    expect(workDemand.isUrgent()).toBe(false);

    const fromUrgentCaller = cached('address', createUrgentFetchDemand());
    expect(workDemand.isUrgent()).toBe(true);

    finishWork();
    await Promise.all([fromBackground, fromUrgentCaller]);
    expect(workDemand.isUrgent()).toBe(false);
  });

  it('recognizes a demand created by another copy of the demand module', () => {
    let otherCopyDemand!: FetchDemand;
    jest.isolateModules(() => {
      const otherCopy = jest.requireActual<typeof import('./fetchDemand')>('./fetchDemand');
      otherCopyDemand = otherCopy.createUrgentFetchDemand();
    });
    expect(otherCopyDemand).not.toBeInstanceOf(FetchDemand);

    let workDemand!: FetchDemand;
    const fn = jest.fn((demand: FetchDemand, address: string) => {
      workDemand = demand;
      return new Promise<string>(() => {});
    });
    const cached = withFetchDemandCacheAsync(fn);

    void cached('address');
    void cached('address', otherCopyDemand);

    expect(fn).toHaveBeenCalledTimes(1);
    expect(workDemand.isUrgent()).toBe(true);
  });
});

describe('withCacheAsync', () => {
  it('passes the arguments as they are and treats a trailing undefined as an omitted argument', async () => {
    const fn = jest.fn((address: string, option?: string) => Promise.resolve(`${address}${option ?? ''}`));
    const cached = withCacheAsync(fn);

    await cached('address');
    await cached('address', undefined);

    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith('address');
  });
});
