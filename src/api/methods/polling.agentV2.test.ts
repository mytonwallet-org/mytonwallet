import type { ApiUpdateConfig } from '../types';

const mockCallBackendGet = jest.fn();
const mockReconcileAgentV2ProtocolVersion = jest.fn();
const mockResolveAgentV2ProtocolVersionForRouting = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  NO_EXTRA_FEATURES: false,
}));

jest.mock('../chains', () => ({
  __esModule: true,
  default: {},
}));

jest.mock('../common/addresses', () => ({
  tryUpdateKnownAddresses: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../common/backend', () => ({
  callBackendGet: (...args: unknown[]) => mockCallBackendGet(...args),
  callBackendPost: jest.fn(),
}));

jest.mock('../common/cache', () => ({
  setBackendConfigCache: jest.fn(),
}));

jest.mock('../common/polling/utils', () => ({
  pollingLoop: () => ({ stop: jest.fn() }),
}));

jest.mock('../common/tokens', () => ({
  fetchNonBackendTokenDetails: jest.fn().mockResolvedValue([]),
  loadTokensCache: jest.fn().mockResolvedValue(undefined),
  pauseTokenUpdates: jest.fn(),
  resumeTokenUpdates: jest.fn(),
  sendUpdateTokens: jest.fn(),
  tokensPreload: { promise: Promise.resolve() },
  updateTokens: jest.fn(),
  updateTokensFromBackend: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn().mockResolvedValue(undefined),
  },
}));

jest.mock('./agentV2Lifecycle', () => ({
  reconcileAgentV2ProtocolVersion: (...args: unknown[]) => mockReconcileAgentV2ProtocolVersion(...args),
  resolveAgentV2ProtocolVersionForRouting: (...args: unknown[]) => (
    mockResolveAgentV2ProtocolVersionForRouting(...args)
  ),
}));

jest.mock('./preload', () => ({
  resolveDataPreloadPromise: jest.fn(),
}));

jest.mock('./staking', () => ({
  tryUpdateStakingCommonData: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('./swap', () => ({
  swapGetAssetsText: jest.fn().mockResolvedValue('[]'),
}));

describe('Agent V2 config polling', () => {
  beforeEach(() => {
    mockCallBackendGet.mockImplementation((path: string) => {
      if (path === '/utils/get-config') return Promise.resolve(makeConfig('v2'));
      if (path === '/currency-rates') return Promise.resolve({ rates: {} });
      return Promise.resolve({});
    });
    mockReconcileAgentV2ProtocolVersion.mockResolvedValue(undefined);
    mockResolveAgentV2ProtocolVersionForRouting.mockReturnValue('v2');
  });

  afterEach(async () => {
    const { destroyPolling } = await import('./polling');
    await destroyPolling();
    jest.clearAllMocks();
  });

  it('publishes non-Agent config while V2 initialization is pending', async () => {
    const initialization = createDeferred<void>();
    mockReconcileAgentV2ProtocolVersion.mockReturnValueOnce(initialization.promise);
    mockResolveAgentV2ProtocolVersionForRouting.mockReturnValue('v1');
    const { initPolling } = await import('./polling');
    const updatePromise = new Promise<ApiUpdateConfig>((resolve) => {
      initPolling((update) => {
        if (update.type === 'updateConfig') resolve(update);
      });
    });

    await expect(updatePromise).resolves.toMatchObject({
      type: 'updateConfig',
      isLimited: true,
      isAppUpdateRequired: true,
      agentProtocolVersion: 'v1',
      allowedOnOffRampCurrencies: ['EUR'],
    });

    initialization.resolve();
  });

  it('promotes routing to V2 only after initialization succeeds', async () => {
    const initialization = createDeferred<void>();
    let isInitialized = false;
    mockReconcileAgentV2ProtocolVersion.mockImplementationOnce(async () => {
      await initialization.promise;
      isInitialized = true;
    });
    mockResolveAgentV2ProtocolVersionForRouting.mockImplementation(() => (isInitialized ? 'v2' : 'v1'));
    const { initPolling } = await import('./polling');
    const updates: ApiUpdateConfig[] = [];
    const v2Update = new Promise<ApiUpdateConfig>((resolve) => {
      initPolling((update) => {
        if (update.type !== 'updateConfig') return;
        updates.push(update);
        if (update.agentProtocolVersion === 'v2') resolve(update);
      });
    });

    await waitFor(() => updates.length === 1);
    expect(updates[0].agentProtocolVersion).toBe('v1');
    initialization.resolve();
    await expect(v2Update).resolves.toMatchObject({
      isLimited: true,
      agentProtocolVersion: 'v2',
    });
  });

  it('ignores an older config response that finishes last', async () => {
    const olderConfig = createDeferred<ReturnType<typeof makeConfig>>();
    const newerConfig = createDeferred<ReturnType<typeof makeConfig>>();
    let configRequestCount = 0;
    mockCallBackendGet.mockImplementation((path: string) => {
      if (path === '/utils/get-config') {
        configRequestCount += 1;
        return configRequestCount === 1 ? olderConfig.promise : newerConfig.promise;
      }
      if (path === '/currency-rates') return Promise.resolve({ rates: {} });
      return Promise.resolve({});
    });
    mockResolveAgentV2ProtocolVersionForRouting.mockImplementation((version) => version ?? 'v1');
    const { initPolling, tryUpdateConfig } = await import('./polling');
    const updates: ApiUpdateConfig[] = [];
    initPolling((update) => {
      if (update.type === 'updateConfig') updates.push(update);
    });
    await waitFor(() => configRequestCount === 1);

    const newerRequest = tryUpdateConfig();
    newerConfig.resolve(makeConfig('v1'));
    await newerRequest;
    olderConfig.resolve(makeConfig('v2'));
    await waitFor(() => updates.length === 1);

    expect(updates.map((update) => update.agentProtocolVersion)).toEqual(['v1']);
    expect(mockReconcileAgentV2ProtocolVersion).toHaveBeenCalledTimes(1);
    expect(mockReconcileAgentV2ProtocolVersion).toHaveBeenCalledWith('v1');
  });
});

function makeConfig(agentProtocolVersion: 'v1' | 'v2') {
  return {
    agentProtocolVersion,
    allowedOnOffRampCurrencies: ['EUR'],
    country: 'DE',
    isLimited: true,
    isUpdateRequired: true,
    now: Date.now(),
  };
}

function createDeferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}

async function waitFor(predicate: () => boolean) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Promise.resolve();
  }
  throw new Error('Condition was not met');
}
