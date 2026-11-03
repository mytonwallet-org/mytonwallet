import type { AccountType } from '../global/types';

const mockLogDebugError = jest.fn();

jest.mock('./logs', () => ({
  logDebugError: (...args: unknown[]) => mockLogDebugError(...args),
}));

const LOSS_MESSAGE = 'IndexedDB: wallet storage was found missing';

function mockDatabases(...listings: string[][]) {
  const databases = jest.fn();
  for (const names of listings) {
    databases.mockResolvedValueOnce(names.map((name) => ({ name, version: 1 })));
  }
  Object.defineProperty(globalThis, 'indexedDB', { value: { databases }, configurable: true });
}

function mockStorageManager() {
  Object.defineProperty(navigator, 'storage', {
    value: {
      persisted: () => Promise.resolve(false),
      estimate: () => Promise.resolve({ usage: 1024, quota: 4096 }),
    },
    configurable: true,
  });
}

// The probe keeps what it saw at boot in module scope, so every test boots its own module instance
async function boot(restoreStorage?: () => Promise<unknown>) {
  jest.resetModules();
  const module = await import('./indexedDbLoss');
  await module.probeIndexedDb(restoreStorage);

  return module;
}

const MNEMONIC_AND_VIEW: AccountType[] = ['mnemonic', 'mnemonic', 'view'];

describe('indexedDbLoss', () => {
  beforeEach(() => {
    localStorage.clear();
    mockStorageManager();
  });

  afterEach(() => {
    mockLogDebugError.mockReset();
  });

  it('reports both stores absent at boot with what the frontend still holds', async () => {
    mockDatabases([]);
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).toHaveBeenCalledTimes(1);
    expect(mockLogDebugError).toHaveBeenCalledWith(LOSS_MESSAGE, expect.objectContaining({
      atThisBoot: { keyvalStore: 'absent', enclave: 'absent' },
      accountCount: 3,
      accountTypes: { mnemonic: 2, view: 1 },
      authTypes: ['passcode'],
      storage: { isPersisted: false, usage: 1024, quota: 4096 },
    }));
  });

  // An Electron origin switch carries keyval-store over and leaves the Enclave behind
  it('tells a store the shell restored apart from one that stayed absent', async () => {
    mockDatabases([], ['keyval-store']);
    const restoreStorage = jest.fn(() => Promise.resolve());
    const { reportIndexedDbLoss } = await boot(restoreStorage);

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(restoreStorage).toHaveBeenCalledTimes(1);
    expect(mockLogDebugError).toHaveBeenCalledWith(LOSS_MESSAGE, expect.objectContaining({
      atThisBoot: { keyvalStore: 'absent', keyvalStoreAfterRestore: 'present', enclave: 'absent' },
    }));
  });

  it('does not count a store the shell restored as lost', async () => {
    mockDatabases(['enclave'], ['enclave', 'keyval-store']);
    const { reportIndexedDbLoss } = await boot(() => Promise.resolve());

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  it('does not count a store as lost when the listing after the restore cannot be read', async () => {
    const databases = jest.fn()
      .mockResolvedValueOnce([{ name: 'enclave', version: 1 }])
      .mockRejectedValueOnce(new Error('UnknownError'));
    Object.defineProperty(globalThis, 'indexedDB', { value: { databases }, configurable: true });
    const { reportIndexedDbLoss, getIndexedDbLossEvidence } = await boot(() => Promise.resolve());

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).not.toHaveBeenCalled();
    expect(getIndexedDbLossEvidence()).toBeUndefined();
  });

  it('reports once however many times the API is initialized', async () => {
    mockDatabases([]);
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);
    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).toHaveBeenCalledTimes(1);
  });

  it('forgets the boot that found a store absent once every wallet is gone', async () => {
    mockDatabases([]);
    const { reportIndexedDbLoss, clearIndexedDbLossEvidence } = await boot();
    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);
    clearIndexedDbLossEvidence();
    mockLogDebugError.mockReset();

    mockDatabases(['keyval-store', 'enclave']);
    await (await boot()).reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  it('keeps the first finding readable apart from the log buffer', async () => {
    jest.useFakeTimers({ now: new Date('2026-10-10T08:00:00Z'), doNotFake: ['setTimeout', 'setImmediate'] });
    mockDatabases([]);
    const { reportIndexedDbLoss, getIndexedDbLossEvidence } = await boot();
    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);
    jest.useRealTimers();

    expect(getIndexedDbLossEvidence()).toEqual({
      at: '2026-10-10T08:00:00.000Z', keyvalStore: 'absent', enclave: 'absent',
    });
  });

  it('stays silent while every store the frontend relies on is present', async () => {
    mockDatabases(['keyval-store', 'enclave']);
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  it('stays silent on a profile with no accounts', async () => {
    mockDatabases([]);
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss([], undefined);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  // Until a password or biometrics is set up nothing has been written to the Enclave, so its database
  // has never existed: a legacy profile awaiting migration or one holding only view wallets
  it('does not count an Enclave as lost before any auth was set up', async () => {
    mockDatabases(['keyval-store']);
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, undefined);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  it('says nothing about a browser that cannot list its databases', async () => {
    Object.defineProperty(globalThis, 'indexedDB', { value: {}, configurable: true });
    const { reportIndexedDbLoss } = await boot();

    await reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).not.toHaveBeenCalled();
  });

  // The first open after a loss recreates the database empty, so a later boot finds it present and
  // only the record kept at the boot that saw it absent still says it was gone
  it('keeps reporting the boot that found a store absent', async () => {
    jest.useFakeTimers({ now: new Date('2026-10-10T08:00:00Z'), doNotFake: ['setTimeout', 'setImmediate'] });
    mockDatabases([]);
    await (await boot()).reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);
    jest.useRealTimers();
    mockLogDebugError.mockReset();

    mockDatabases(['keyval-store', 'enclave']);
    await (await boot()).reportIndexedDbLoss(MNEMONIC_AND_VIEW, ['passcode']);

    expect(mockLogDebugError).toHaveBeenCalledWith(LOSS_MESSAGE, expect.objectContaining({
      atThisBoot: { keyvalStore: 'present', enclave: 'present' },
      firstFound: { at: '2026-10-10T08:00:00.000Z', keyvalStore: 'absent', enclave: 'absent' },
    }));
  });
});
