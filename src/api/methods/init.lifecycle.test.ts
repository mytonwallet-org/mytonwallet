import type { OnApiUpdate } from '../types';

import { addHooks } from '../hooks';
import init, { destroy } from './init';
import * as methods from '.';

let mockUpdater: OnApiUpdate | undefined;
const mockSetItem = jest.fn();
const mockInitProtocolManager = jest.fn();
jest.mock('../../util/windowProvider/connector', () => ({ initWindowConnector: jest.fn() }));
jest.mock('../common/backend', () => ({ fetchBackendReferrer: jest.fn() }));
jest.mock('../common/helpers', () => ({
  connectUpdater: (updater: OnApiUpdate) => { mockUpdater = updater; },
  disconnectUpdater: () => { mockUpdater = undefined; },
  isUpdaterAlive: (updater: OnApiUpdate) => mockUpdater === updater,
  tryMigrateStorage: jest.fn(),
}));
jest.mock('../common/other', () => ({ initClientId: jest.fn() }));
jest.mock('../dappProtocols', () => ({
  initProtocolManager: (...args: unknown[]) => mockInitProtocolManager(...args),
  getProtocolManager: () => ({ closeRemoteConnection: jest.fn(), resetupRemoteConnection: jest.fn() }),
}));
jest.mock('../environment', () => ({ setEnvironment: () => ({ isDappSupported: true }) }));
jest.mock('../hooks', () => ({ addHooks: jest.fn() }));
jest.mock('../storages', () => ({
  createStorage: () => ({ setItem: (...args: unknown[]) => mockSetItem(...args) }),
  configureStorage: jest.fn(),
  withStorage: (_storage: unknown, operation: NoneToVoidFunction) => operation(),
}));
jest.mock('./agentV2Lifecycle', () => ({ destroyAgentV2IfEnabled: jest.fn(), initAgentV2IfEnabled: jest.fn() }));
jest.mock('./attribution', () => ({ claimInstallAttribution: jest.fn() }));
jest.mock('./extra', () => ({ initMfa: jest.fn(), initStaking: jest.fn(), initSwap: jest.fn() }));
jest.mock('./polling', () => ({ destroyPolling: jest.fn() }));
jest.mock('.', () => ({
  initAccounts: jest.fn(), initAuth: jest.fn(), initPolling: jest.fn(), initTransfer: jest.fn(),
  initTokens: jest.fn(), initNfts: jest.fn(), initDapps: jest.fn(),
}));

const previousExtraFlag = process.env.NO_EXTRA_FEATURES;
beforeEach(() => {
  process.env.NO_EXTRA_FEATURES = '1';
  mockUpdater = undefined;
  jest.clearAllMocks();
  mockSetItem.mockReset().mockResolvedValue(undefined);
  mockInitProtocolManager.mockReset().mockResolvedValue(undefined);
});
afterAll(() => {
  if (previousExtraFlag === undefined) delete process.env.NO_EXTRA_FEATURES;
  else process.env.NO_EXTRA_FEATURES = previousExtraFlag;
});

function deferred() {
  let resolve!: NoneToVoidFunction;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

it('rejects an old init delayed before migration without replacing the newer polling updater', async () => {
  const held = deferred();
  mockSetItem.mockReturnValueOnce(held.promise);
  const oldResult = init(jest.fn(), { langCode: 'en' }).catch((error: Error) => error);
  expect(methods.initPolling).not.toHaveBeenCalled();
  destroy();
  const currentUpdater = jest.fn();
  await init(currentUpdater, { langCode: 'ru' });

  held.resolve();
  expect(await oldResult).toBeInstanceOf(Error);
  expect(methods.initPolling).toHaveBeenCalledTimes(1);
  expect(methods.initPolling).toHaveBeenCalledWith(currentUpdater);
  expect(mockUpdater).toBe(currentUpdater);
});

it('rejects an old protocol init without replacing the newer dApp updater or hooks', async () => {
  const entered = deferred();
  const held = deferred();
  mockInitProtocolManager.mockImplementationOnce(() => {
    entered.resolve();
    return held.promise;
  });
  const oldResult = init(jest.fn(), {}).catch((error: Error) => error);
  await entered.promise;
  destroy();
  const currentUpdater = jest.fn();
  await init(currentUpdater, {});

  held.resolve();
  expect(await oldResult).toBeInstanceOf(Error);
  expect(methods.initDapps).toHaveBeenCalledTimes(1);
  expect(methods.initDapps).toHaveBeenCalledWith(currentUpdater);
  expect(addHooks).toHaveBeenCalledTimes(1);
  expect(mockUpdater).toBe(currentUpdater);
});

it('completes the current init and installs its polling, dApp updater and hooks', async () => {
  const updater = jest.fn();
  await expect(init(updater, { langCode: 'en' })).resolves.toBeUndefined();
  expect(methods.initPolling).toHaveBeenCalledWith(updater);
  expect(methods.initDapps).toHaveBeenCalledWith(updater);
  expect(addHooks).toHaveBeenCalledTimes(1);
});
