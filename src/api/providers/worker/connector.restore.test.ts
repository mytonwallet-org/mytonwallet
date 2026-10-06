import type { ApiUpdate } from '../../types';

const mockInit = jest.fn();
const mockRequest = jest.fn();
let mockUpdate: (update: ApiUpdate) => void;
let mockReconnect: () => void;
let mockIsGramWallet = true;
jest.mock('../../../config', () => ({
  ...jest.requireActual('../../../config'),
  get IS_GRAM_WALLET() { return mockIsGramWallet; },
}));
jest.mock('../../../util/PostMessageConnector', () => ({
  createConnector: () => ({ init: mockInit, request: mockRequest }),
  createExtensionConnector: (
    _port: string, onUpdate: typeof mockUpdate, _callback: unknown, onReconnect: () => void,
  ) => {
    mockUpdate = onUpdate;
    mockReconnect = onReconnect;
    return { init: mockInit, request: mockRequest };
  },
}));
jest.mock('../../../util/windowProvider', () => ({
  createWindowProvider: jest.fn(), createWindowProviderForExtension: jest.fn(),
}));
jest.mock('./provider?worker', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/logs', () => ({ logDebugError: jest.fn(), logDebugApi: jest.fn() }));
jest.mock('../../../util/chunkLoading', () => ({ reportApiChunkLoadError: jest.fn() }));

const descriptor = {
  accountId: '0-ton-mainnet', type: 'mnemonic' as const, addressByChain: { ton: 'EQpublic' },
};
const migration: ApiUpdate = {
  type: 'migrateLegacyCoreApplication', currentAccountId: descriptor.accountId,
  accounts: [{ accountId: descriptor.accountId, address: descriptor.addressByChain.ton }],
};
const drain = () => new Promise((resolve) => setTimeout(resolve, 0));
function deferred() {
  let resolve!: () => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<void>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
async function waitFor(predicate: () => boolean) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await drain();
  }
  throw new Error('Timed out');
}
function loadConnector() {
  let connector!: typeof import('./connector');
  jest.isolateModules(() => {
    connector = jest.requireActual('./connector');
  });
  return connector;
}
const previousExtensionFlag = process.env.IS_EXTENSION;
beforeEach(() => {
  process.env.IS_EXTENSION = '1';
  mockIsGramWallet = true;
  mockInit.mockReset().mockResolvedValue(undefined);
  mockRequest.mockReset().mockResolvedValue(undefined);
});
afterAll(() => {
  if (previousExtensionFlag === undefined) delete process.env.IS_EXTENSION;
  else process.env.IS_EXTENSION = previousExtensionFlag;
});

it('restores once, then awaits durable resume on every reconnect', async () => {
  const restore = deferred();
  mockRequest.mockImplementation(({ name }) => (
    name === 'restoreAccountAfterInitialization' ? restore.promise : Promise.resolve()
  ));
  const connector = loadConnector();
  connector.initApi(jest.fn(), {}, () => ({ current: descriptor }));
  const pending = connector.callApiWithThrow('resetAccounts');
  await drain();
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual(['restoreAccountAfterInitialization']);
  restore.resolve();
  await pending;
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual([
    'restoreAccountAfterInitialization', 'resetAccounts',
  ]);

  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.filter(([request]) => (
    request.name === 'resumeCurrentAccountAfterWorkerStart'
  ))).toHaveLength(1);
});

it('retries a lost resume acknowledgment and ignores the retired attempt', async () => {
  const connector = loadConnector();
  const firstResume = deferred();
  let resumeCalls = 0;
  mockRequest.mockImplementation(({ name }) => {
    if (name === 'resumeCurrentAccountAfterWorkerStart') {
      resumeCalls += 1;
      return resumeCalls === 1 ? firstResume.promise : Promise.resolve();
    }
    return Promise.resolve();
  });

  connector.initApi(jest.fn(), {}, () => ({ current: descriptor }));
  await connector.callApiWithThrow('resetAccounts');

  mockReconnect();
  const retiredCall = connector.callApiWithThrow('resetAccounts').catch((error: Error) => error);
  await waitFor(() => resumeCalls === 1);

  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  firstResume.resolve();
  expect(await retiredCall).toBeInstanceOf(Error);

  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(resumeCalls).toBe(3);
});

it('retries failed first restore and performs no restore after its first success', async () => {
  const connector = loadConnector();
  let shouldFail = true;
  mockRequest.mockImplementation(({ name }) => (
    name === 'restoreAccountAfterInitialization' && shouldFail
      ? Promise.reject(new Error('restore failed')) : Promise.resolve()
  ));
  connector.initApi(jest.fn(), {}, () => ({ current: descriptor }));
  await expect(connector.callApiWithThrow('resetAccounts')).rejects.toThrow('restore failed');
  shouldFail = false;
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.filter(([request]) => request.name === 'restoreAccountAfterInitialization')
    .map(([request]) => request.args)).toEqual([[descriptor, false], [descriptor, false]]);
});

it('does not restore or release APIs if migration completion is missing', async () => {
  const connector = loadConnector();
  let completed = true;
  connector.initApi(jest.fn(), {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: completed }));
  completed = false;
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockClear();
  mockReconnect();
  await expect(connector.callApiWithThrow('resetAccounts')).rejects.toThrow('migration');
  expect(mockRequest).not.toHaveBeenCalled();
});

it('reads the descriptor after the synchronous migration update has persisted', async () => {
  const connector = loadConnector();
  let completed = false;
  let current = undefined as typeof descriptor | undefined;
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  connector.initApi(() => {
    current = descriptor;
    completed = true;
  }, {}, () => ({
    current, isLegacyCoreMigrationCompleted: completed,
  }));
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls[0][0]).toEqual({ name: 'restoreAccountAfterInitialization', args: [descriptor, true] });
});

it('does not let an old initialization mark its replacement restored', async () => {
  const old = deferred();
  mockInit.mockReturnValueOnce(old.promise);
  const connector = loadConnector();
  connector.initApi(jest.fn(), {}, () => ({ current: descriptor }));
  const oldCall = connector.callApiWithThrow('resetAccounts');
  const oldResult = oldCall.catch((error: Error) => error);
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  old.resolve();
  expect(await oldResult).toBeInstanceOf(Error);
  expect(mockRequest.mock.calls.filter(([request]) => (
    request.name === 'restoreAccountAfterInitialization'
  ))).toHaveLength(1);
});

it('preserves My Wallet direct initialization without the Gram restore contract', async () => {
  mockIsGramWallet = false;
  const connector = loadConnector();
  connector.initApi(jest.fn(), {});
  await connector.callApiWithThrow('resetAccounts');
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual(['resetAccounts', 'resetAccounts']);
});

it('preserves non-extension initialization without the Gram restore contract', async () => {
  process.env.IS_EXTENSION = '';
  const connector = loadConnector();
  connector.initApi(jest.fn(), {});
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual(['resetAccounts']);
});

it('signals first migrated sign-in only after a successful strict restore and never on later reconnect', async () => {
  const connector = loadConnector();
  const restore = deferred();
  const onUpdate = jest.fn();
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockImplementation(({ name }) => (
    name === 'restoreAccountAfterInitialization' ? restore.promise : Promise.resolve()
  ));
  connector.initApi(onUpdate, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  const pending = connector.callApiWithThrow('resetAccounts');
  await drain();
  expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual(['migrateLegacyCoreApplication']);
  restore.resolve();
  await pending;
  expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual([
    'migrateLegacyCoreApplication', 'legacyCoreMigrationReady',
  ]);
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(onUpdate.mock.calls.filter(([update]) => update.type === 'legacyCoreMigrationReady')).toHaveLength(1);
});

it('retains first-restore authority if the local ready handler throws', async () => {
  const connector = loadConnector();
  let shouldThrow = true;
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  connector.initApi((update) => {
    if (update.type === 'legacyCoreMigrationReady' && shouldThrow) throw new Error('ready failed');
  }, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  await expect(connector.callApiWithThrow('resetAccounts')).rejects.toThrow('ready failed');
  shouldThrow = false;
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.filter(([request]) => request.name === 'restoreAccountAfterInitialization')
    .map(([request]) => request.args)).toEqual([[descriptor, true], [descriptor, true]]);
});

it('completes the first empty onboarding barrier without restoring on later reconnect', async () => {
  const connector = loadConnector();
  let current: typeof descriptor | undefined = undefined;
  connector.initApi(jest.fn(), {}, () => ({ current }));
  await connector.callApiWithThrow('resetAccounts');
  current = descriptor;
  mockReconnect();
  await connector.callApiWithThrow('resetAccounts');
  expect(mockRequest.mock.calls.filter(([request]) => request.name === 'restoreAccountAfterInitialization')
    .map(([request]) => request.args)).toEqual([[undefined, false]]);
});

it('holds public imports and migrated sign-in behind the terminal SDK acknowledgment', async () => {
  const confirmation = deferred();
  const onUpdate = jest.fn();
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockImplementation(({ name }) => (
    name === 'confirmLegacyCoreMigration' ? confirmation.promise : Promise.resolve()
  ));
  const connector = loadConnector();
  connector.initApi(onUpdate, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  const importing = connector.callApiWithThrow('importViewAccount', 'mainnet', { ton: 'EQwatch' });
  await drain();
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual([
    'restoreAccountAfterInitialization', 'confirmLegacyCoreMigration',
  ]);
  expect(onUpdate.mock.calls.map(([update]) => update.type)).toEqual(['migrateLegacyCoreApplication']);
  confirmation.resolve();
  await importing;
  expect(mockRequest.mock.calls.at(-1)![0].name).toBe('importViewAccount');
  expect(onUpdate.mock.calls.at(-1)![0].type).toBe('legacyCoreMigrationReady');
});

it('retries a rejected terminal write before admitting an import with an already durable UI cache', async () => {
  let shouldFail = true;
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockImplementation(({ name }) => (
    name === 'confirmLegacyCoreMigration' && shouldFail
      ? Promise.reject(new Error('completion write failed')) : Promise.resolve()
  ));
  const connector = loadConnector();
  const onUpdate = jest.fn();
  connector.initApi(onUpdate, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  await expect(connector.callApiWithThrow('importViewAccount', 'mainnet', { ton: 'EQwatch' }))
    .rejects.toThrow('completion write failed');
  expect(mockRequest.mock.calls.some(([request]) => request.name === 'importViewAccount')).toBe(false);
  expect(onUpdate.mock.calls.some(([update]) => update.type === 'legacyCoreMigrationReady')).toBe(false);
  shouldFail = false;
  mockReconnect();
  await connector.callApiWithThrow('importViewAccount', 'mainnet', { ton: 'EQwatch' });
  expect(mockRequest.mock.calls.filter(([request]) => request.name === 'confirmLegacyCoreMigration')).toHaveLength(2);
  expect(mockRequest.mock.calls.filter(([request]) => request.name === 'importViewAccount')).toHaveLength(1);
});

it('does not let an old terminal acknowledgment complete its replacement attempt', async () => {
  const old = deferred();
  mockInit.mockImplementation(() => {
    mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockImplementation(({ name }) => (
    name === 'confirmLegacyCoreMigration' ? old.promise : Promise.resolve()
  ));
  const connector = loadConnector();
  const onUpdate = jest.fn();
  connector.initApi(onUpdate, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  const oldResult = connector.callApiWithThrow('ping').catch((error: Error) => error);
  await drain();
  mockRequest.mockResolvedValue(undefined);
  mockReconnect();
  await connector.callApiWithThrow('ping');
  old.resolve();
  expect(await oldResult).toBeInstanceOf(Error);
  expect(onUpdate.mock.calls.filter(([update]) => update.type === 'legacyCoreMigrationReady')).toHaveLength(1);
});

it('retains pending sign-in when the completion write succeeds but its acknowledgment is lost', async () => {
  let sdkCompleted = false;
  mockInit.mockImplementation(() => {
    if (!sdkCompleted) mockUpdate(migration);
    return Promise.resolve();
  });
  mockRequest.mockImplementation(({ name }) => {
    if (name === 'confirmLegacyCoreMigration' && !sdkCompleted) {
      sdkCompleted = true;
      return Promise.reject(new Error('port disconnected after write'));
    }
    return Promise.resolve();
  });
  const connector = loadConnector();
  const onUpdate = jest.fn();
  connector.initApi(onUpdate, {}, () => ({ current: descriptor, isLegacyCoreMigrationCompleted: true }));
  await expect(connector.callApiWithThrow('ping')).rejects.toThrow('port disconnected after write');
  expect(onUpdate.mock.calls.some(([update]) => update.type === 'legacyCoreMigrationReady')).toBe(false);
  mockReconnect();
  await connector.callApiWithThrow('ping');
  expect(onUpdate.mock.calls.filter(([update]) => update.type === 'migrateLegacyCoreApplication')).toHaveLength(1);
  expect(onUpdate.mock.calls.filter(([update]) => update.type === 'legacyCoreMigrationReady')).toHaveLength(1);
});
