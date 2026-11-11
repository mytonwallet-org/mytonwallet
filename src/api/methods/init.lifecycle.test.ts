import type { OnApiUpdate } from '../types';

import { logDebugError } from '../../util/logs';
import { fetchBackendReferrer } from '../common/backend';
import { addHooks } from '../hooks';
import init, { destroy } from './init';
import { startWebFirstLaunchReporting, stopWebFirstLaunchReporting } from './webFunnel';
import * as methods from '.';

let mockUpdater: OnApiUpdate | undefined;
const mockSetItem = jest.fn();
const mockInitProtocolManager = jest.fn();
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));
jest.mock('../../util/windowProvider/connector', () => ({ initWindowConnector: jest.fn() }));
jest.mock('../common/backend', () => ({ fetchBackendReferrer: jest.fn() }));
jest.mock('../common/helpers', () => ({
  connectUpdater: (updater: OnApiUpdate) => { mockUpdater = updater; },
  disconnectUpdater: () => { mockUpdater = undefined; },
  isUpdaterAlive: (updater: OnApiUpdate) => mockUpdater === updater,
  tryMigrateStorage: jest.fn(),
}));
jest.mock('../common/other', () => ({ initClientId: jest.fn(), isWebFunnelClient: () => true }));
jest.mock('../dappProtocols', () => ({
  initProtocolManager: (...args: unknown[]) => mockInitProtocolManager(...args),
  getProtocolManager: () => ({ closeRemoteConnection: jest.fn(), resetupRemoteConnection: jest.fn() }),
}));
jest.mock('../environment', () => ({ setEnvironment: () => ({ isDappSupported: true, isAndroidApp: true }) }));
jest.mock('../hooks', () => ({ addHooks: jest.fn() }));
jest.mock('../storages', () => ({
  createStorage: () => ({ setItem: (...args: unknown[]) => mockSetItem(...args) }),
  configureStorage: jest.fn(),
  withStorage: (_storage: unknown, operation: NoneToVoidFunction) => operation(),
}));
jest.mock('./agentV2Lifecycle', () => ({ destroyAgentV2IfEnabled: jest.fn(), initAgentV2IfEnabled: jest.fn() }));
jest.mock('./attribution', () => ({ claimInstallAttribution: jest.fn() }));
jest.mock('./webFunnel', () => ({ startWebFirstLaunchReporting: jest.fn(), stopWebFirstLaunchReporting: jest.fn() }));
jest.mock('./extra', () => ({
  initMfa: jest.fn(), initStaking: jest.fn(), initSwap: jest.fn(), initPerps: jest.fn(), initPerpsTrading: jest.fn(),
}));
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
  jest.mocked(fetchBackendReferrer).mockReset();
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
  expect(startWebFirstLaunchReporting).toHaveBeenCalledTimes(1);
  expect(stopWebFirstLaunchReporting).toHaveBeenCalledTimes(1);
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
  expect(startWebFirstLaunchReporting).toHaveBeenCalledTimes(1);
  expect(stopWebFirstLaunchReporting).toHaveBeenCalledTimes(1);
});

it('completes the current init and installs its polling, dApp updater and hooks', async () => {
  const updater = jest.fn();
  await expect(init(updater, { langCode: 'en' })).resolves.toBeUndefined();
  expect(methods.initPolling).toHaveBeenCalledWith(updater);
  expect(methods.initDapps).toHaveBeenCalledWith(updater);
  expect(addHooks).toHaveBeenCalledTimes(1);
  expect(startWebFirstLaunchReporting).toHaveBeenCalledTimes(1);
});

it('handles a referrer request failing after initialization without interrupting the wallet', async () => {
  let rejectRequest!: (error: Error) => void;
  jest.mocked(fetchBackendReferrer).mockReturnValueOnce(new Promise((_, reject) => {
    rejectRequest = reject;
  }));
  const updater = jest.fn();
  await expect(init(updater, {})).resolves.toBeUndefined();

  const error = new Error('GET /referrer/get | attempts=3 | Load failed');
  rejectRequest(error);
  await new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

  expect(logDebugError).toHaveBeenCalledWith('saveReferrer', error);
  expect(mockSetItem).not.toHaveBeenCalledWith('referrer', expect.anything());
  expect(mockUpdater).toBe(updater);
  expect(methods.initPolling).toHaveBeenCalledWith(updater);
});

it('preserves an explicitly supplied referrer without a backend request', async () => {
  await init(jest.fn(), { referrer: 'test-campaign' });
  await new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

  expect(fetchBackendReferrer).not.toHaveBeenCalled();
  expect(mockSetItem).toHaveBeenCalledWith('referrer', 'test-campaign');
});
