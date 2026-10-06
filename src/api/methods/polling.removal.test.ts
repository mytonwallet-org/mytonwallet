import type { ApiAccountAny } from '../types';

const mockActive = new Set<string>();
const mockInactive = new Set<string>();
const mockStorage = {
  getItem: jest.fn(), setItem: jest.fn(), removeItem: jest.fn(), mutateItem: jest.fn(),
};
const mockRemoveDapps = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'), NO_EXTRA_FEATURES: true, IS_GRAM_WALLET: false,
}));
jest.mock('../chains', () => ({
  __esModule: true,
  default: { ton: {
    setupActivePolling: (id: string) => {
      mockActive.add(id);
      return () => mockActive.delete(id);
    },
    setupInactivePolling: (id: string) => {
      mockInactive.add(id);
      return () => mockInactive.delete(id);
    },
  } },
}));
jest.mock('../chains/ton', () => ({}));
jest.mock('../common/mnemonic', () => ({}));
jest.mock('../common/addresses', () => ({ tryUpdateKnownAddresses: jest.fn() }));
jest.mock('../common/backend', () => ({ callBackendGet: jest.fn(), callBackendPost: jest.fn() }));
jest.mock('../common/cache', () => ({ setBackendConfigCache: jest.fn() }));
jest.mock('../common/heldTokens', () => ({
  forgetAllHeldTokens: jest.fn(), forgetHeldTokens: jest.fn(), forgetNetworkHeldTokens: jest.fn(),
  forgetOtherNetworksHeldTokens: jest.fn(), recordHeldTokens: jest.fn(),
}));
jest.mock('../common/polling/utils', () => ({ pollingLoop: () => ({ poll: jest.fn(), stop: jest.fn() }) }));
jest.mock('../common/tokens', () => ({
  fetchNonBackendTokenDetails: jest.fn().mockResolvedValue([]), loadTokensCache: jest.fn(),
  pauseTokenUpdates: jest.fn(), resumeTokenUpdates: jest.fn(), sendUpdateTokens: jest.fn(),
  tokensPreload: { promise: Promise.resolve() }, updateTokens: jest.fn(), updateTokensFromBackend: jest.fn(),
}));
jest.mock('../db', () => ({ tokenRepository: { clear: jest.fn() } }));
jest.mock('../environment', () => ({ getEnvironment: () => ({ isDappSupported: true }) }));
jest.mock('../hooks', () => ({ callHook: jest.fn() }));
jest.mock('../storages', () => ({ storage: mockStorage, getCurrentStorage: () => mockStorage }));
jest.mock('./dapps', () => ({
  removeAccountDapps: (...args: unknown[]) => mockRemoveDapps(...args),
  removeNetworkDapps: (...args: unknown[]) => mockRemoveDapps(...args),
  removeAllDapps: (...args: unknown[]) => mockRemoveDapps(...args),
}));
jest.mock('./agentV2Lifecycle', () => ({ resetAgentV2: jest.fn() }));
jest.mock('./preload', () => ({ resolveDataPreloadPromise: jest.fn() }));
jest.mock('../../util/logs', () => ({
  ...jest.requireActual('../../util/logs'), logDebugError: jest.fn(), logDebug: jest.fn(),
}));

const A = '0-ton-mainnet';
const B = '1-ton-mainnet';
const TEST = '0-ton-testnet';
const account = (address: string): ApiAccountAny => ({ type: 'ton', byChain: { ton: { address } } }) as ApiAccountAny;
let values: Map<string, any>;
let polling: typeof import('./polling');
let accounts: typeof import('./accounts');
let stored: typeof import('../common/accounts');
let auth: typeof import('./auth');

beforeEach(async () => {
  jest.resetModules();
  mockActive.clear();
  mockInactive.clear();
  mockRemoveDapps.mockReset().mockResolvedValue(undefined);
  values = new Map([
    ['accounts', { [A]: account('EQa'), [B]: account('EQb'), [TEST]: account('kQt') }],
    ['currentAccountId', A],
  ] as [string, any][]);
  mockStorage.getItem.mockReset().mockImplementation((key: string) => {
    const value = values.get(key);
    return Promise.resolve(value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
  });
  mockStorage.setItem.mockReset().mockImplementation((key: string, value: unknown) => {
    values.set(key, value);
    return Promise.resolve();
  });
  mockStorage.removeItem.mockReset().mockImplementation((key: string) => {
    values.delete(key);
    return Promise.resolve();
  });
  mockStorage.mutateItem.mockReset().mockImplementation((key: string, mutate: AnyFunction) => {
    const result = mutate(values.get(key));
    values.set(key, result);
    return Promise.resolve(result);
  });
  polling = await import('./polling');
  accounts = await import('./accounts');
  stored = await import('../common/accounts');
  auth = await import('./auth');
  polling.initPolling(jest.fn());
  accounts.initAccounts(jest.fn());
});

afterEach(() => jest.restoreAllMocks());

it.each(['account', 'network', 'all'] as const)(
  'retires a delayed previous-account poller during %s removal',
  async (scope) => {
    await polling.setActivePollingAccount(A, {});
    const held = holdRead(stored, 'fetchMaybeStoredAccount', A);
    await accounts.activateAccount(B);
    await waitFor(() => held.entered);

    const removal = scope === 'all' ? auth.resetAccounts()
      : scope === 'network' ? auth.removeNetworkAccounts('mainnet') : auth.removeAccount(A, B);
    await waitFor(() => !values.get('accounts')?.[A]);
    held.release();
    await removal;
    await drain();

    expect(mockInactive.has(A)).toBe(false);
    expect(values.get('accounts')?.[A]).toBeUndefined();
    expect(values.get('currentAccountId')).toBe(scope === 'account' ? B : undefined);
    expect([...mockActive]).toEqual(scope === 'account' ? [B] : []);
  },
);

it('removes an inactive wallet while cold resume is reading an older account map', async () => {
  const held = holdRead(stored, 'fetchStoredAccounts');
  const resume = polling.resumeCurrentAccountPollingAfterWorkerStart();
  await waitFor(() => held.entered);
  const removal = auth.removeAccount(B, A);
  await waitFor(() => !values.get('accounts')?.[B]);
  held.release();
  await Promise.all([resume, removal]);
  await drain();

  expect(mockInactive.has(B)).toBe(false);
  expect(values.get('accounts')?.[B]).toBeUndefined();
  expect(values.get('currentAccountId')).toBe(A);
  expect([...mockActive]).toEqual([A]);
});

it('keeps a valid inactive wallet polling when its storage deletion fails', async () => {
  await polling.setActivePollingAccount(A, {});
  mockStorage.mutateItem.mockRejectedValueOnce(new Error('Storage write failed'));

  await expect(auth.removeAccount(B, A)).rejects.toThrow('Storage write failed');
  await drain();

  expect(values.get('accounts')[B]).toBeDefined();
  expect([...mockInactive]).toEqual([B]);
  expect([...mockActive]).toEqual([A]);
});

it('keeps the removed wallet absent when another activation follows cleanup', async () => {
  await polling.setActivePollingAccount(A, {});
  await auth.removeAccount(B, A);
  await polling.setActivePollingAccount(TEST, {});
  await polling.setActivePollingAccount(A, {});

  expect(values.get('accounts')[B]).toBeUndefined();
  expect(mockInactive.has(B)).toBe(false);
  expect([...mockActive]).toEqual([A]);
});

it('cleans a poller recreated while SDK deletion is pending', async () => {
  await polling.setActivePollingAccount(A, {});
  const mutate = mockStorage.mutateItem.getMockImplementation()!;
  let release!: VoidFunction;
  const write = new Promise<void>((resolve) => {
    release = resolve;
  });
  let isWriting = false;
  mockStorage.mutateItem.mockImplementationOnce(async (...args) => {
    isWriting = true;
    await write;
    return mutate(...args);
  });
  const removal = auth.removeAccount(A, B);
  await waitFor(() => isWriting);
  await accounts.activateAccount(B);
  await waitFor(() => mockInactive.has(A));
  release();
  await removal;
  await drain();

  expect(values.get('accounts')[A]).toBeUndefined();
  expect(mockInactive.has(A)).toBe(false);
  expect([...mockActive]).toEqual([B]);
});

it('cleans the deleted account even when its parallel dApp cleanup fails', async () => {
  await polling.setActivePollingAccount(A, {});
  const held = holdRead(stored, 'fetchMaybeStoredAccount', A);
  await accounts.activateAccount(B);
  await waitFor(() => held.entered);
  mockRemoveDapps.mockRejectedValueOnce(new Error('dApp cleanup failed'));
  const removal = auth.removeAccount(A, B).catch((error: unknown) => error);
  await waitFor(() => !values.get('accounts')?.[A]);
  held.release();
  expect(await removal).toEqual(new Error('dApp cleanup failed'));
  await drain();

  expect(values.get('accounts')[A]).toBeUndefined();
  expect(mockInactive.has(A)).toBe(false);
});

it('does not restart active polling after a delayed activation loses its removed account', async () => {
  const held = holdRead(stored, 'fetchStoredAccount', A);
  const activation = polling.setActivePollingAccount(A, {});
  await waitFor(() => held.entered);
  await auth.removeAccount(A, B);
  held.release();

  await expect(activation).resolves.toBe(false);
  await drain();
  expect(values.get('accounts')[A]).toBeUndefined();
  expect([...mockActive]).toEqual([B]);
  expect(mockInactive.has(A)).toBe(false);
});

it('preserves the active other-network wallet when removing a network', async () => {
  await accounts.activateAccount(TEST);
  await drain();
  await auth.removeNetworkAccounts('mainnet');

  expect(Object.keys(values.get('accounts'))).toEqual([TEST]);
  expect(values.get('currentAccountId')).toBe(TEST);
  expect([...mockActive]).toEqual([TEST]);
  expect(mockInactive.size).toBe(0);
});

function holdRead(
  target: typeof stored,
  name: 'fetchMaybeStoredAccount' | 'fetchStoredAccounts' | 'fetchStoredAccount',
  id?: string,
) {
  let release!: VoidFunction;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const original = target[name];
  const held = { entered: false, release };
  jest.spyOn(target, name).mockImplementation((async (...args: any[]) => {
    const result = await (original as AnyFunction)(...args);
    if (!held.entered && (id === undefined || args[0] === id)) {
      held.entered = true;
      await gate;
    }
    return result;
  }) as any);
  return held;
}

async function drain() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

async function waitFor(predicate: () => boolean) {
  for (let i = 0; i < 100; i++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error('Timed out waiting for the test boundary');
}
