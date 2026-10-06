import type { OnApiUpdate } from '../../types';

import { installTestExtensionPorts } from '../../../../tests/helpers/extensionPorts';

let mockCurrentUpdater: OnApiUpdate | undefined;
let mockIsPolling: boolean;
const mockRestore = jest.fn(() => {
  mockIsPolling = true;
  return Promise.resolve();
});
const mockResume = jest.fn(() => {
  mockIsPolling = true;
  return Promise.resolve();
});
const mockPublicCall = jest.fn();
const mockDestroy = jest.fn(() => {
  mockCurrentUpdater = undefined;
  mockIsPolling = false;
});
jest.mock('../../../config', () => ({ ...jest.requireActual('../../../config'), IS_GRAM_WALLET: true }));
jest.mock('../../common/helpers', () => ({
  isUpdaterAlive: (onUpdate: OnApiUpdate) => mockCurrentUpdater === onUpdate,
}));
jest.mock('../../methods/init', () => ({
  __esModule: true,
  default: (onUpdate: OnApiUpdate) => { mockCurrentUpdater = onUpdate; },
  destroy: () => mockDestroy(),
}));
jest.mock('../../methods/registry', () => ({ methods: {
  restoreAccountAfterInitialization: () => mockRestore(),
  resumeCurrentAccountAfterWorkerStart: () => mockResume(),
  resetAccounts: () => mockPublicCall(),
} }));
jest.mock('../../extensionMethods', () => ({}));
jest.mock('../../extensionMethods/init', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/windowProvider/connector', () => ({ initWindowConnector: jest.fn() }));
jest.mock('../../../util/windowProvider', () => ({
  createWindowProvider: jest.fn(), createWindowProviderForExtension: jest.fn(),
}));
jest.mock('../worker/provider?worker', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/logs', () => ({ logDebugError: jest.fn(), logDebugApi: jest.fn() }));
jest.mock('../../../util/chunkLoading', () => ({ reportApiChunkLoadError: jest.fn() }));

let ports: ReturnType<typeof installTestExtensionPorts>;
let api: typeof import('../worker/connector');
let transport: typeof import('../../../util/PostMessageConnector');
const previousExtensionFlag = process.env.IS_EXTENSION;
beforeEach(() => {
  process.env.IS_EXTENSION = '1';
  ports = installTestExtensionPorts();
  mockCurrentUpdater = undefined;
  mockIsPolling = false;
  jest.clearAllMocks();
  jest.isolateModules(() => {
    jest.requireActual('./providerForPopup');
    api = jest.requireActual('../worker/connector');
    transport = jest.requireActual('../../../util/PostMessageConnector');
  });
});
afterEach(() => {
  ports.restore();
});
afterAll(() => {
  if (previousExtensionFlag === undefined) delete process.env.IS_EXTENSION;
  else process.env.IS_EXTENSION = previousExtensionFlag;
});

it('resumes polling after disconnect and reconnect within the same worker', async () => {
  api.initApi(jest.fn(), {}, () => ({ current: {
    accountId: '0-ton-mainnet', type: 'mnemonic', addressByChain: { ton: 'EQfixture' },
  } }));
  await api.callApiWithThrow('resetAccounts');
  expect(mockIsPolling).toBe(true);

  ports.pairs[0].disconnect(true);
  expect(mockIsPolling).toBe(false);
  await api.callApiWithThrow('resetAccounts');

  expect(mockIsPolling).toBe(true);
  expect(mockRestore).toHaveBeenCalledTimes(1);
  expect(mockResume).toHaveBeenCalledTimes(1);
  expect(mockPublicCall).toHaveBeenCalledTimes(2);
});

it('keeps the newer popup alive when an older port disconnects', async () => {
  const oldPopup = transport.createExtensionConnector('GramWallet_popup');
  await oldPopup.init({});
  const currentPopup = transport.createExtensionConnector('GramWallet_popup');
  await currentPopup.init({});
  const currentUpdater = mockCurrentUpdater;
  ports.pairs[0].disconnect();

  expect(mockCurrentUpdater).toBe(currentUpdater);
  expect(mockDestroy).not.toHaveBeenCalled();
  await currentPopup.request({ name: 'resetAccounts', args: [] });
  expect(mockPublicCall).toHaveBeenCalledTimes(1);

  ports.pairs[1].disconnect();
  expect(mockDestroy).toHaveBeenCalledTimes(1);
  expect(mockCurrentUpdater).toBeUndefined();
});
