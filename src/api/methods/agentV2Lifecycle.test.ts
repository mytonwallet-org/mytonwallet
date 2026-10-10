import { destroyAgentV2, initAgentV2 } from '../agentV2/service';
import { getEnvironment, setIsAgentV2Enabled } from '../environment';
import {
  destroyAgentV2IfEnabled,
  initAgentV2IfEnabled,
  reconcileAgentV2ProtocolVersion,
  resetAgentV2,
  resolveAgentV2ProtocolVersionForRouting,
} from './agentV2Lifecycle';

jest.mock('../agentV2/service', () => ({
  destroyAgentV2: jest.fn(),
  initAgentV2: jest.fn(),
}));
jest.mock('../environment', () => ({
  getEnvironment: jest.fn(),
  resolveIsAgentV2Enabled: jest.requireActual('../environment').resolveIsAgentV2Enabled,
  setIsAgentV2Enabled: jest.fn(),
}));

const destroyAgentV2Mock = jest.mocked(destroyAgentV2);
const getEnvironmentMock = jest.mocked(getEnvironment);
const initAgentV2Mock = jest.mocked(initAgentV2);
const setIsAgentV2EnabledMock = jest.mocked(setIsAgentV2Enabled);
let environment: ReturnType<typeof getEnvironment>;

beforeEach(() => {
  environment = {
    agentOverride: 'no_override',
    isAgentV2Enabled: false,
  } as ReturnType<typeof getEnvironment>;
  getEnvironmentMock.mockImplementation(() => environment);
  destroyAgentV2Mock.mockReset();
  initAgentV2Mock.mockReset();
  setIsAgentV2EnabledMock.mockReset();
  setIsAgentV2EnabledMock.mockImplementation((isAgentV2Enabled) => {
    environment.isAgentV2Enabled = isAgentV2Enabled;
  });
});

describe('Agent V2 lifecycle', () => {
  it('does not initialize or destroy the runtime for ordinary disabled lifecycle calls', async () => {
    await initAgentV2IfEnabled(jest.fn());
    await destroyAgentV2IfEnabled();
    await destroyAgentV2IfEnabled({ shouldClearPersistentIdentity: true });

    expect(initAgentV2Mock).not.toHaveBeenCalled();
    expect(destroyAgentV2Mock).not.toHaveBeenCalled();
  });

  it('clears persistent state without initializing the runtime when disabled', async () => {
    await resetAgentV2();

    expect(destroyAgentV2Mock).toHaveBeenCalledWith({ shouldClearPersistentIdentity: true });
    expect(initAgentV2Mock).not.toHaveBeenCalled();
  });

  it('preserves lifecycle calls when enabled', async () => {
    environment = {
      agentOverride: 'v2',
      isAgentV2Enabled: true,
    } as ReturnType<typeof getEnvironment>;
    const onUpdate = jest.fn();

    await initAgentV2IfEnabled(onUpdate);
    await destroyAgentV2IfEnabled({ shouldClearPersistentIdentity: true });

    expect(initAgentV2Mock).toHaveBeenCalledWith(onUpdate);
    expect(destroyAgentV2Mock).toHaveBeenCalledWith({ shouldClearPersistentIdentity: true });
  });

  it('waits for runtime initialization when enabled', async () => {
    environment = {
      agentOverride: 'v2',
      isAgentV2Enabled: true,
    } as ReturnType<typeof getEnvironment>;
    const initialization = createDeferred<void>();
    initAgentV2Mock.mockReturnValueOnce(initialization.promise);
    let isSettled = false;

    const lifecycle = initAgentV2IfEnabled(jest.fn()).finally(() => {
      isSettled = true;
    });
    await Promise.resolve();

    expect(isSettled).toBe(false);
    initialization.resolve();
    await lifecycle;
    expect(isSettled).toBe(true);
  });

  it('reinitializes the runtime after clearing its persistent identity', async () => {
    environment = {
      agentOverride: 'v2',
      isAgentV2Enabled: true,
    } as ReturnType<typeof getEnvironment>;
    const onUpdate = jest.fn();
    await initAgentV2IfEnabled(onUpdate);
    initAgentV2Mock.mockClear();

    await resetAgentV2();

    expect(destroyAgentV2Mock).toHaveBeenCalledWith({ shouldClearPersistentIdentity: true });
    expect(initAgentV2Mock).toHaveBeenCalledWith(onUpdate);
  });

  it('does not reactivate the runtime when persistent-state cleanup fails', async () => {
    environment = {
      agentOverride: 'v2',
      isAgentV2Enabled: true,
    } as ReturnType<typeof getEnvironment>;
    await initAgentV2IfEnabled(jest.fn());
    initAgentV2Mock.mockClear();
    destroyAgentV2Mock.mockRejectedValueOnce(new Error('cleanup failed'));

    await expect(resetAgentV2()).rejects.toThrow('cleanup failed');

    expect(initAgentV2Mock).not.toHaveBeenCalled();
  });

  it('initializes V2 when the backend enables it without a build override', async () => {
    const onUpdate = jest.fn();
    await initAgentV2IfEnabled(onUpdate);

    await reconcileAgentV2ProtocolVersion('v2');

    expect(initAgentV2Mock).toHaveBeenCalledWith(onUpdate);
    expect(setIsAgentV2EnabledMock).toHaveBeenCalledWith(true);
  });

  it('destroys V2 when the backend switches back to V1', async () => {
    environment = {
      agentOverride: 'no_override',
      isAgentV2Enabled: true,
    } as ReturnType<typeof getEnvironment>;
    await initAgentV2IfEnabled(jest.fn());
    initAgentV2Mock.mockClear();

    await reconcileAgentV2ProtocolVersion('v1');

    expect(destroyAgentV2Mock).toHaveBeenCalledWith({ shouldClearPersistentIdentity: false });
    expect(setIsAgentV2EnabledMock).toHaveBeenCalledWith(false);
  });

  it('keeps a forced V1 override when the backend enables V2', async () => {
    environment = {
      agentOverride: 'v1',
      isAgentV2Enabled: false,
    } as ReturnType<typeof getEnvironment>;
    await initAgentV2IfEnabled(jest.fn());

    await reconcileAgentV2ProtocolVersion('v2');

    expect(initAgentV2Mock).not.toHaveBeenCalled();
    expect(setIsAgentV2EnabledMock).not.toHaveBeenCalled();
  });

  it('initializes V2 on Android despite a forced V1 override', async () => {
    environment = {
      agentOverride: 'v1',
      isAgentV2Enabled: true,
      isAndroidApp: true,
    } as ReturnType<typeof getEnvironment>;
    const onUpdate = jest.fn();

    await initAgentV2IfEnabled(onUpdate);

    expect(initAgentV2Mock).toHaveBeenCalledWith(onUpdate);
    expect(resolveAgentV2ProtocolVersionForRouting('v1')).toBe('v2');
  });

  it('applies the latest protocol while an older transition is pending', async () => {
    const initialization = createDeferred<void>();
    initAgentV2Mock.mockReturnValueOnce(initialization.promise);
    await initAgentV2IfEnabled(jest.fn());

    const enable = reconcileAgentV2ProtocolVersion('v2');
    const disable = reconcileAgentV2ProtocolVersion('v1');
    expect(initAgentV2Mock).toHaveBeenCalledTimes(1);
    expect(destroyAgentV2Mock).not.toHaveBeenCalled();

    initialization.resolve();
    await Promise.all([enable, disable]);

    expect(destroyAgentV2Mock).toHaveBeenCalledTimes(1);
    expect(environment.isAgentV2Enabled).toBe(false);
  });

  it('serializes a reset after an in-flight protocol enablement', async () => {
    const initialization = createDeferred<void>();
    initAgentV2Mock.mockReturnValueOnce(initialization.promise);
    const onUpdate = jest.fn();
    await initAgentV2IfEnabled(onUpdate);

    const enable = reconcileAgentV2ProtocolVersion('v2');
    const reset = resetAgentV2();
    expect(destroyAgentV2Mock).not.toHaveBeenCalled();

    initialization.resolve();
    await Promise.all([enable, reset]);

    expect(destroyAgentV2Mock).toHaveBeenCalledWith({ shouldClearPersistentIdentity: true });
    expect(initAgentV2Mock).toHaveBeenLastCalledWith(onUpdate);
    expect(environment.isAgentV2Enabled).toBe(true);
  });

  it('keeps routing on V1 until V2 initialization succeeds', async () => {
    const initialization = createDeferred<void>();
    initAgentV2Mock.mockReturnValueOnce(initialization.promise);
    await initAgentV2IfEnabled(jest.fn());

    const reconciliation = reconcileAgentV2ProtocolVersion('v2');
    expect(resolveAgentV2ProtocolVersionForRouting('v2')).toBe('v1');

    initialization.resolve();
    await reconciliation;
    expect(resolveAgentV2ProtocolVersionForRouting('v2')).toBe('v2');
  });

  it('destroys a runtime that finishes initializing during shutdown', async () => {
    const initialization = createDeferred<void>();
    initAgentV2Mock.mockReturnValueOnce(initialization.promise);
    await initAgentV2IfEnabled(jest.fn());

    const enable = reconcileAgentV2ProtocolVersion('v2');
    const destroy = destroyAgentV2IfEnabled();
    initialization.resolve();
    await Promise.all([enable, destroy]);

    expect(destroyAgentV2Mock).toHaveBeenCalledTimes(1);
    expect(environment.isAgentV2Enabled).toBe(false);
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
