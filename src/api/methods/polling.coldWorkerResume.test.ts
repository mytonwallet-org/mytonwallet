import type { ApiAccountAny } from '../types';

const mockSetupActivePolling = jest.fn(() => jest.fn());
const mockSetupInactivePolling = jest.fn((_accountId: string) => jest.fn());
const mockGetItem = jest.fn();
const mockForgetAllHeldTokens = jest.fn();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'), NO_EXTRA_FEATURES: true,
}));
jest.mock('../chains', () => ({
  __esModule: true,
  default: { ton: { setupActivePolling: mockSetupActivePolling, setupInactivePolling: mockSetupInactivePolling } },
}));
jest.mock('../common/addresses', () => ({ tryUpdateKnownAddresses: jest.fn() }));
jest.mock('../common/backend', () => ({ callBackendGet: jest.fn(), callBackendPost: jest.fn() }));
jest.mock('../common/cache', () => ({ setBackendConfigCache: jest.fn() }));
jest.mock('../common/heldTokens', () => ({
  forgetAllHeldTokens: mockForgetAllHeldTokens, forgetHeldTokens: jest.fn(), forgetNetworkHeldTokens: jest.fn(),
  forgetOtherNetworksHeldTokens: jest.fn(), recordHeldTokens: jest.fn(),
}));
jest.mock('../common/polling/utils', () => ({ pollingLoop: () => ({ poll: jest.fn(), stop: jest.fn() }) }));
jest.mock('../common/tokens', () => ({
  fetchNonBackendTokenDetails: jest.fn().mockResolvedValue([]), loadTokensCache: jest.fn(),
  pauseTokenUpdates: jest.fn(), resumeTokenUpdates: jest.fn(), sendUpdateTokens: jest.fn(),
  tokensPreload: { promise: Promise.resolve() }, updateTokens: jest.fn(), updateTokensFromBackend: jest.fn(),
}));
jest.mock('../storages', () => ({
  storage: {
    getItem: (...args: unknown[]) => mockGetItem(...args),
  },
}));
jest.mock('./preload', () => ({ resolveDataPreloadPromise: jest.fn() }));

const ACCOUNT_ID = '0-ton-mainnet';
const account: ApiAccountAny = {
  type: 'mnemonic',
  byChain: { ton: { address: 'EQcold' } },
} as unknown as ApiAccountAny;

beforeEach(() => {
  mockGetItem.mockReset();
  mockForgetAllHeldTokens.mockClear();
  mockSetupActivePolling.mockClear();
  mockSetupInactivePolling.mockClear();
});

it('does not install polling after a disconnected port destroys an in-flight cold resume', async () => {
  const heldRead = deferred<Record<string, ApiAccountAny>>();
  let accountReads = 0;
  mockGetItem.mockImplementation((key: string) => {
    if (key !== 'accounts') return Promise.resolve(undefined);
    accountReads += 1;
    return accountReads === 1 ? heldRead.promise : Promise.resolve({ [ACCOUNT_ID]: account });
  });

  const { destroyPolling, initPolling, setActivePollingAccount } = await import('./polling');
  initPolling(jest.fn());
  const coldResume = setActivePollingAccount(ACCOUNT_ID, {});
  await waitFor(() => accountReads === 1);
  const cleanup = destroyPolling();
  heldRead.resolve({ [ACCOUNT_ID]: account });

  const [resumeResult] = await Promise.all([coldResume, cleanup]);
  expect(resumeResult).toBe(false);
  expect(mockSetupActivePolling).not.toHaveBeenCalled();
  expect(mockForgetAllHeldTokens).toHaveBeenCalledTimes(1);
});

it('owns the polling generation before reading the durable current account', async () => {
  const heldCurrentRead = deferred<string>();
  mockGetItem.mockImplementation((key: string) => {
    if (key === 'currentAccountId') return heldCurrentRead.promise;
    if (key === 'accounts') return Promise.resolve({ [ACCOUNT_ID]: account });
    return Promise.resolve(undefined);
  });

  const {
    destroyPolling, initPolling, resumeCurrentAccountPollingAfterWorkerStart,
  } = await import('./polling');
  initPolling(jest.fn());
  const coldResume = resumeCurrentAccountPollingAfterWorkerStart();
  await waitFor(() => mockGetItem.mock.calls.some(([key]) => key === 'currentAccountId'));
  const cleanup = destroyPolling();
  heldCurrentRead.resolve(ACCOUNT_ID);

  await expect(coldResume).resolves.toBe(false);
  await cleanup;
  expect(mockSetupActivePolling).not.toHaveBeenCalled();
});

it.each([
  ['missing current', undefined, {}],
  ['dangling current', ACCOUNT_ID, {}],
])('does not resume %s', async (_label, currentAccountId, accounts) => {
  mockGetItem.mockImplementation((key: string) => {
    if (key === 'currentAccountId') return Promise.resolve(currentAccountId);
    if (key === 'accounts') return Promise.resolve(accounts);
    return Promise.resolve(undefined);
  });

  const { initPolling, resumeCurrentAccountPollingAfterWorkerStart } = await import('./polling');
  initPolling(jest.fn());

  await expect(resumeCurrentAccountPollingAfterWorkerStart()).resolves.toBeUndefined();
  expect(mockSetupActivePolling).not.toHaveBeenCalled();
});

it('does not let delayed cleanup stop a successor cold resume', async () => {
  const heldInactiveRead = deferred<Record<string, ApiAccountAny>>();
  const otherId = '2-ton-mainnet';
  let accountReads = 0;
  mockGetItem.mockImplementation((key: string) => {
    if (key === 'currentAccountId') return Promise.resolve(ACCOUNT_ID);
    if (key !== 'accounts') return Promise.resolve(undefined);
    accountReads += 1;
    return accountReads === 2
      ? heldInactiveRead.promise
      : Promise.resolve({ [ACCOUNT_ID]: account, [otherId]: account });
  });

  const {
    destroyPolling, initPolling, resumeCurrentAccountPollingAfterWorkerStart,
  } = await import('./polling');
  initPolling(jest.fn());
  const retiredResume = resumeCurrentAccountPollingAfterWorkerStart();
  await waitFor(() => accountReads === 2);
  const cleanup = destroyPolling();
  const liveResume = resumeCurrentAccountPollingAfterWorkerStart();
  await waitFor(() => accountReads === 3);
  heldInactiveRead.resolve({ [ACCOUNT_ID]: account, [otherId]: account });

  await expect(retiredResume).resolves.toBe(false);
  await cleanup;
  await expect(liveResume).resolves.toBe(true);
  expect(mockSetupActivePolling).toHaveBeenCalledTimes(2);
  expect(mockSetupActivePolling.mock.results.map(({ value }) => value.mock.calls.length)).toEqual([1, 0]);
  expect(mockSetupInactivePolling.mock.calls.map(([id]) => id)).toEqual([otherId, otherId]);
  expect(mockSetupInactivePolling.mock.results.map(({ value }) => value.mock.calls.length)).toEqual([1, 0]);
  expect(mockForgetAllHeldTokens).not.toHaveBeenCalled();
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

async function waitFor(predicate: () => boolean) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error('Timed out');
}
