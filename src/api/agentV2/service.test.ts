import type { OnApiUpdate } from '../types';
import type { AgentV2RuntimeDependencies } from './runtime';
import type { AgentV2WalletToolDispatcherDependencies } from './walletTools';

import { AgentV2CompatibilityError, AgentV2ContractError } from './protocol/wireReader';
import { AgentV2HttpError } from './identity';
import { clearAgentV2PersistentState } from './persistentState';
import {
  createAgentV2Thread,
  destroyAgentV2,
  getAgentV2CachedMessages,
  getAgentV2CachedThreads,
  getAgentV2DefaultThread,
  getAgentV2NewsFeed,
  getAgentV2Runtime,
  initAgentV2,
  updateAgentV2HostContext,
} from './service';

type MockRuntime = jest.Mocked<Pick<
  import('./runtime').AgentV2Runtime,
    'createThread' | 'getDefaultThread' | 'getNewsFeed' | 'destroy' | 'getConsent' | 'getRunLifecycleGeneration'
    | 'setToolExecutor' | 'updateHostContext' | 'getCachedThreads' | 'getCachedMessages'
>> & {
  dependencies: AgentV2RuntimeDependencies;
};

const mockRuntimeInstances: MockRuntime[] = [];
const mockDispatcherDependencies: AgentV2WalletToolDispatcherDependencies[] = [];
const originalFetch = globalThis.fetch;

jest.mock('./runtime', () => ({
  AgentV2Runtime: jest.fn().mockImplementation((dependencies: AgentV2RuntimeDependencies) => {
    const instance: MockRuntime = {
      dependencies,
      createThread: jest.fn(),
      getDefaultThread: jest.fn(),
      getNewsFeed: jest.fn(),
      getCachedThreads: jest.fn(),
      getCachedMessages: jest.fn(),
      destroy: jest.fn(() => Promise.resolve()),
      getConsent: jest.fn(() => Promise.resolve(true)),
      getRunLifecycleGeneration: jest.fn(() => 0),
      setToolExecutor: jest.fn(),
      updateHostContext: jest.fn(() => Promise.resolve(false)),
    };
    mockRuntimeInstances.push(instance);
    return instance;
  }),
}));

jest.mock('./persistentState', () => ({
  clearAgentV2PersistentState: jest.fn(() => Promise.resolve()),
}));

jest.mock('./walletTools', () => ({
  AgentV2WalletToolDispatcher: jest.fn().mockImplementation((
    dependencies: AgentV2WalletToolDispatcherDependencies,
  ) => {
    mockDispatcherDependencies.push(dependencies);
    return { dependencies };
  }),
}));

describe('Agent V2 service lifecycle', () => {
  beforeAll(() => {
    globalThis.fetch = jest.fn() as unknown as typeof fetch;
  });

  beforeEach(async () => {
    await destroyAgentV2().catch(() => undefined);
    mockRuntimeInstances.length = 0;
    mockDispatcherDependencies.length = 0;
    jest.clearAllMocks();
  });

  afterEach(async () => {
    mockRuntimeInstances.forEach(({ destroy }) => destroy.mockResolvedValue());
    await destroyAgentV2().catch(() => undefined);
  });

  afterAll(() => {
    globalThis.fetch = originalFetch;
  });

  it('returns missing cache without an active runtime and forwards cache reads to the active runtime', async () => {
    await expect(getAgentV2CachedThreads()).resolves.toBeUndefined();
    await expect(getAgentV2CachedMessages('thread-id')).resolves.toBeUndefined();
    await initAgentV2(jest.fn());
    mockRuntimeInstances[0].getCachedThreads.mockResolvedValue([]);
    mockRuntimeInstances[0].getCachedMessages.mockResolvedValue(undefined);

    await expect(getAgentV2CachedThreads()).resolves.toEqual([]);
    await expect(getAgentV2CachedMessages('thread-id')).resolves.toBeUndefined();
    expect(mockRuntimeInstances[0].getCachedThreads).toHaveBeenCalledWith();
    expect(mockRuntimeInstances[0].getCachedMessages).toHaveBeenCalledWith('thread-id');
  });

  it.each([
    [new AgentV2ContractError('$.thread.revision'), 'invalid_event'],
    [new AgentV2CompatibilityError('$.protocolVersion', undefined, 3), 'client_update_required'],
    [new TypeError('Failed to fetch'), 'network_error'],
  ])('preserves default-thread failure across the worker boundary: %s', async (error, code) => {
    await initAgentV2(jest.fn());
    mockRuntimeInstances[0].getDefaultThread.mockRejectedValue(error);
    await expect(getAgentV2DefaultThread()).resolves.toMatchObject({ ok: false, error: { code } });
  });

  it('returns the news feed through the worker result envelope and forwards app language and cursor', async () => {
    await initAgentV2(jest.fn());
    const page = { locale: 'ru' as const, items: [], nextCursor: 'next-page' };
    mockRuntimeInstances[0].getNewsFeed.mockResolvedValue(page);

    const params = { lang: 'ru-RU', cursor: 'current-page', digestHour: 21, timeZone: 'Europe/Moscow' };

    await expect(getAgentV2NewsFeed(params)).resolves.toEqual({
      ok: true,
      value: page,
    });
    expect(mockRuntimeInstances[0].getNewsFeed).toHaveBeenCalledWith(params);
  });

  it('passes news binding and default parameters to thread creation', async () => {
    await initAgentV2(jest.fn());
    const result = {
      protocolVersion: 3 as const,
      thread: {
        id: '11111111-1111-4111-8111-111111111111',
        revision: 1,
        createdAt: '2026-10-19T00:00:00.000Z',
        updatedAt: '2026-10-19T00:00:00.000Z',
        lastActivityAt: '2026-10-19T00:00:00.000Z',
        messageCount: 0,
        news: { eventId: 42, headline: 'Thread headline', publishedAt: '2026-10-19T00:00:00.000Z' },
      },
      created: true,
    };
    mockRuntimeInstances[0].createThread.mockResolvedValue(result);
    const news = { eventId: 42, locale: 'ru' as const };

    await expect(createAgentV2Thread({ news })).resolves.toEqual({ ok: true, value: result });
    await expect(createAgentV2Thread()).resolves.toEqual({ ok: true, value: result });
    expect(mockRuntimeInstances[0].createThread).toHaveBeenNthCalledWith(1, { news });
    expect(mockRuntimeInstances[0].createThread).toHaveBeenNthCalledWith(2, {});
  });

  it('preserves retryable news failures across the worker boundary', async () => {
    await initAgentV2(jest.fn());
    const failure = new AgentV2HttpError(503, 'news_unavailable', 'Private server details', true, 2_000);
    mockRuntimeInstances[0].getNewsFeed.mockRejectedValue(failure);
    mockRuntimeInstances[0].createThread.mockRejectedValue(failure);
    const expected = {
      ok: false,
      error: { code: 'news_unavailable', retryable: true, retryAfterMs: 2_000 },
    };

    await expect(getAgentV2NewsFeed({ lang: 'ru-RU', cursor: 'next-page' })).resolves.toEqual(expected);
    await expect(createAgentV2Thread({ news: { eventId: 42, locale: 'ru' } })).resolves.toEqual(expected);
  });

  it('preserves digest_unavailable from digest thread creation across the worker boundary', async () => {
    await initAgentV2(jest.fn());
    mockRuntimeInstances[0].createThread.mockRejectedValue(
      new AgentV2HttpError(404, 'digest_unavailable', 'Private server details', false),
    );

    await expect(createAgentV2Thread({ digest: { id: 'ru:2026-11-04T08:00:00.000Z' } })).resolves.toEqual({
      ok: false,
      error: { code: 'digest_unavailable', retryable: false },
    });
  });

  it('tears down the current runtime before activating its replacement', async () => {
    await initAgentV2(jest.fn());
    const firstRuntime = mockRuntimeInstances[0];
    const teardown = createDeferred<void>();
    firstRuntime.destroy.mockReturnValueOnce(teardown.promise);

    const replacement = initAgentV2(jest.fn());

    expect(firstRuntime.destroy).toHaveBeenCalledWith();
    expect(() => getAgentV2Runtime()).toThrow('Agent V2 SDK is not initialized');
    expect(mockRuntimeInstances).toHaveLength(1);

    teardown.resolve();
    await replacement;

    expect(mockRuntimeInstances).toHaveLength(2);
    expect(getAgentV2Runtime()).toBe(mockRuntimeInstances[1]);
  });

  it('serializes concurrent init calls in invocation order', async () => {
    const firstOnUpdate = jest.fn();
    const secondOnUpdate = jest.fn();
    const firstInit = initAgentV2(firstOnUpdate);
    const secondInit = initAgentV2(secondOnUpdate);

    await Promise.all([firstInit, secondInit]);

    expect(mockRuntimeInstances).toHaveLength(2);
    expect(mockRuntimeInstances[0].destroy).toHaveBeenCalledWith();
    expect(getAgentV2Runtime()).toBe(mockRuntimeInstances[1]);
    expect(firstOnUpdate).not.toHaveBeenCalled();
    expect(secondOnUpdate).toHaveBeenCalledWith({
      type: 'agentV2',
      update: { kind: 'runtimeReady', generation: expect.any(Number) },
    });
  });

  it('serializes destroy followed by init in invocation order', async () => {
    await initAgentV2(jest.fn());
    const firstRuntime = mockRuntimeInstances[0];
    const teardown = createDeferred<void>();
    firstRuntime.destroy.mockReturnValueOnce(teardown.promise);

    const destroy = destroyAgentV2();
    const init = initAgentV2(jest.fn());
    expect(mockRuntimeInstances).toHaveLength(1);

    teardown.resolve();
    await Promise.all([destroy, init]);

    expect(mockRuntimeInstances).toHaveLength(2);
    expect(getAgentV2Runtime()).toBe(mockRuntimeInstances[1]);
  });

  it('serializes init followed by destroy in invocation order', async () => {
    await initAgentV2(jest.fn());
    const firstRuntime = mockRuntimeInstances[0];
    const teardown = createDeferred<void>();
    firstRuntime.destroy.mockReturnValueOnce(teardown.promise);

    const init = initAgentV2(jest.fn());
    const destroy = destroyAgentV2();
    teardown.resolve();
    await Promise.all([init, destroy]);

    expect(mockRuntimeInstances).toHaveLength(2);
    expect(mockRuntimeInstances[1].destroy).toHaveBeenCalledWith({ shouldClearPersistentIdentity: false });
    expect(() => getAgentV2Runtime()).toThrow('Agent V2 SDK is not initialized');
  });

  it('keeps the lifecycle queue usable after teardown failure', async () => {
    await initAgentV2(jest.fn());
    mockRuntimeInstances[0].destroy.mockRejectedValueOnce(new Error('teardown failed'));

    await expect(initAgentV2(jest.fn())).rejects.toThrow('teardown failed');
    expect(() => getAgentV2Runtime()).toThrow('Agent V2 SDK is not initialized');

    await expect(initAgentV2(jest.fn())).resolves.toBeUndefined();
    expect(getAgentV2Runtime()).toBe(mockRuntimeInstances[1]);
  });

  it('guards callbacks by active instance and binds dispatcher consent locally', async () => {
    const firstOnUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(firstOnUpdate);
    const firstRuntime = mockRuntimeInstances[0];
    const firstRuntimeDependencies = firstRuntime.dependencies;
    const firstDispatcherDependencies = mockDispatcherDependencies[0];

    const secondOnUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(secondOnUpdate);
    const secondRuntimeDependencies = mockRuntimeInstances[1].dependencies;
    firstOnUpdate.mockClear();
    secondOnUpdate.mockClear();

    firstRuntimeDependencies.onUpdate({ kind: 'userQuotaChanged' });
    await firstDispatcherDependencies.getConsent();
    secondRuntimeDependencies.onUpdate({ kind: 'userQuotaChanged' });

    expect(firstOnUpdate).not.toHaveBeenCalled();
    expect(firstRuntime.getConsent).toHaveBeenCalledTimes(1);
    expect(mockRuntimeInstances[1].getConsent).not.toHaveBeenCalled();
    expect(secondOnUpdate).toHaveBeenNthCalledWith(1, {
      type: 'agentV2',
      update: { kind: 'userQuotaChanged' },
    });
    expect(secondOnUpdate).toHaveBeenCalledTimes(1);
  });

  it('publishes a new runtime generation after every successful activation', async () => {
    const firstOnUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(firstOnUpdate);
    const firstReady = firstOnUpdate.mock.calls.at(-1)![0];

    const secondOnUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(secondOnUpdate);
    const secondReady = secondOnUpdate.mock.calls.at(-1)![0];

    expect(firstReady).toMatchObject({ type: 'agentV2', update: { kind: 'runtimeReady' } });
    expect(secondReady).toMatchObject({ type: 'agentV2', update: { kind: 'runtimeReady' } });
    if (firstReady.type !== 'agentV2' || secondReady.type !== 'agentV2') throw new Error('Invalid update type');
    if (firstReady.update.kind !== 'runtimeReady' || secondReady.update.kind !== 'runtimeReady') {
      throw new Error('Invalid Agent V2 update');
    }
    expect(secondReady.update.generation).toBeGreaterThan(firstReady.update.generation);
  });

  it('acknowledges host context only for the runtime generation that received it', async () => {
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(onUpdate);
    const ready = onUpdate.mock.calls.at(-1)![0];
    if (ready.type !== 'agentV2' || ready.update.kind !== 'runtimeReady') {
      throw new Error('Invalid Agent V2 update');
    }
    mockRuntimeInstances[0].updateHostContext.mockResolvedValueOnce(true);
    mockRuntimeInstances[0].getRunLifecycleGeneration.mockReturnValueOnce(0).mockReturnValueOnce(1);

    await expect(updateAgentV2HostContext()).resolves.toEqual({
      ok: true,
      value: { authorityChanged: true, generation: ready.update.generation },
    });

    const pendingUpdate = createDeferred<boolean>();
    mockRuntimeInstances[0].updateHostContext.mockReturnValueOnce(pendingUpdate.promise);
    const staleDelivery = updateAgentV2HostContext();
    await initAgentV2(jest.fn());
    pendingUpdate.resolve(false);

    await expect(staleDelivery).resolves.toEqual({
      ok: false,
      error: { code: 'internal_error', retryable: false },
    });
  });

  it('preserves active runs when a wallet authority update leaves their lifecycle current', async () => {
    const onUpdate = jest.fn() as jest.MockedFunction<OnApiUpdate>;
    await initAgentV2(onUpdate);
    const ready = onUpdate.mock.calls.at(-1)![0];
    if (ready.type !== 'agentV2' || ready.update.kind !== 'runtimeReady') {
      throw new Error('Invalid Agent V2 update');
    }
    mockRuntimeInstances[0].updateHostContext.mockResolvedValueOnce(true);

    await expect(updateAgentV2HostContext()).resolves.toEqual({
      ok: true,
      value: { authorityChanged: true, generation: ready.update.generation, preservesActiveRuns: true },
    });
  });

  it('removes the runtime from service access before destroy settles', async () => {
    await initAgentV2(jest.fn());
    const teardown = createDeferred<void>();
    mockRuntimeInstances[0].destroy.mockReturnValueOnce(teardown.promise);

    const destroy = destroyAgentV2({ shouldClearPersistentIdentity: true });

    expect(() => getAgentV2Runtime()).toThrow('Agent V2 SDK is not initialized');
    expect(mockRuntimeInstances[0].destroy).toHaveBeenCalledWith({ shouldClearPersistentIdentity: true });
    teardown.resolve();
    await destroy;
    expect(clearAgentV2PersistentState).toHaveBeenCalledTimes(1);
  });

  it('clears persistent state when no runtime is active', async () => {
    await destroyAgentV2({ shouldClearPersistentIdentity: true });

    expect(clearAgentV2PersistentState).toHaveBeenCalledTimes(1);
  });
});

function createDeferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}
