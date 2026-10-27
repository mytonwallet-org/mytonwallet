import { createUrgentFetchDemand, FetchDemand, isFetchDemand } from './fetchDemand';

describe('FetchDemand', () => {
  it('is urgent only while an urgent demand waits for it', async () => {
    const shared = new FetchDemand();
    const urgent = createUrgentFetchDemand();
    let resolveWork!: NoneToVoidFunction;
    const work = new Promise<void>((resolve) => {
      resolveWork = resolve;
    });

    expect(shared.isUrgent()).toBe(false);

    const waiting = urgent.waitFor(shared, work);
    expect(shared.isUrgent()).toBe(true);

    resolveWork();
    await waiting;
    expect(shared.isUrgent()).toBe(false);
  });

  it('lends urgency through a chain of shared work', () => {
    const inner = new FetchDemand();
    const outer = new FetchDemand();
    const urgent = createUrgentFetchDemand();

    void outer.waitFor(inner, new Promise(() => {}));
    expect(inner.isUrgent()).toBe(false);

    void urgent.waitFor(outer, new Promise(() => {}));
    expect(inner.isUrgent()).toBe(true);
  });

  it('keeps the urgency until every wait of the same demand ends', async () => {
    const shared = new FetchDemand();
    const urgent = createUrgentFetchDemand();

    const first = urgent.waitFor(shared, Promise.resolve());
    const second = urgent.waitFor(shared, new Promise(() => {}));
    void second;
    await first;

    expect(shared.isUrgent()).toBe(true);
  });

  it('ends the wait when the work fails', async () => {
    const shared = new FetchDemand();
    const urgent = createUrgentFetchDemand();
    const reason = new Error('failed');

    await expect(urgent.waitFor(shared, Promise.reject(reason))).rejects.toBe(reason);
    expect(shared.isUrgent()).toBe(false);
  });

  it('answers for shared work that waits for itself', () => {
    const first = new FetchDemand();
    const second = new FetchDemand();

    void first.waitFor(second, new Promise(() => {}));
    void second.waitFor(first, new Promise(() => {}));

    expect(first.isUrgent()).toBe(false);
  });

  it('is recognized by its brand, including an instance from another copy of the module', () => {
    let otherCopyDemand: unknown;
    jest.isolateModules(() => {
      otherCopyDemand = jest.requireActual<typeof import('./fetchDemand')>('./fetchDemand').createUrgentFetchDemand();
    });

    expect(isFetchDemand(new FetchDemand())).toBe(true);
    expect(isFetchDemand(otherCopyDemand)).toBe(true);
    expect(isFetchDemand({ isUrgent: () => true })).toBe(false);
    expect(isFetchDemand(undefined)).toBe(false);
  });
});
