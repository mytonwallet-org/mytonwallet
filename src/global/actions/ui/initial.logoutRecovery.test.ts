import './initial';

import type { ApiAccountAny, ApiUpdate } from '../../../api/types';
import type { SimpleStorage, StorageKey as EnclaveStorageKey, StorageValue } from '../../../enclave/types';
import type { GlobalState } from '../../types';

import { fetchStoredAccount } from '../../../api/common/accounts';
import { tokenRepository } from '../../../api/db';
import * as accountMethods from '../../../api/methods/accounts';
import { resetAgentV2 } from '../../../api/methods/agentV2Lifecycle';
import * as authMethods from '../../../api/methods/auth';
import { storage } from '../../../api/storages';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

let mockConnector: typeof import('../../../api/providers/worker/connector');
let mockEnclave: typeof import('../../../enclave/enclave');
let mockUpdate: (update: ApiUpdate) => void;
const mockRequest = jest.fn();
const mockInit = jest.fn();
jest.mock('../../../config', () => ({
  ...jest.requireActual('../../../config'), IS_GRAM_WALLET: true, IS_EXTENSION: true,
}));
jest.mock('../../../api', () => ({
  callApi: (...args: any[]) => (mockConnector.callApi as AnyFunction)(...args),
  callApiWithThrow: (...args: any[]) => (mockConnector.callApiWithThrow as AnyFunction)(...args),
}));
jest.mock('../../../enclave', () => ({
  get enclave() {
    return mockEnclave;
  },
}));
jest.mock('../../../api/chains', () => ({ __esModule: true, default: {} }));
jest.mock('../../../api/chains/ton', () => ({}));
jest.mock('../../../api/common/mnemonic', () => ({}));
jest.mock('../../../api/common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../../../api/db', () => ({ tokenRepository: { clear: jest.fn() } }));
jest.mock('../../../api/environment', () => ({ getEnvironment: () => ({ isDappSupported: true }) }));
jest.mock('../../../api/hooks', () => ({ callHook: jest.fn() }));
jest.mock('../../../api/methods/agentV2Lifecycle', () => ({ resetAgentV2: jest.fn() }));
jest.mock('../../../api/methods/polling', () => ({
  addPollingAccount: jest.fn(), removePollingAccount: jest.fn(), removeAllPollingAccounts: jest.fn(),
  removeNetworkPollingAccounts: jest.fn(), setActivePollingAccount: jest.fn(),
}));
jest.mock('../../../api/storages', () => {
  const mockStorage = {
    getItem: jest.fn(), setItem: jest.fn(), mutateItem: jest.fn(), removeItem: jest.fn(), getMany: jest.fn(),
  };
  return { storage: mockStorage, getCurrentStorage: () => mockStorage };
});
jest.mock('../../../util/PostMessageConnector', () => ({
  createExtensionConnector: (_port: string, onUpdate: typeof mockUpdate) => {
    mockUpdate = onUpdate;
    return { init: mockInit, request: mockRequest };
  },
}));
jest.mock('../../../util/windowProvider', () => ({ createWindowProviderForExtension: jest.fn() }));
jest.mock('../../../util/chunkLoading', () => ({ reportApiChunkLoadError: jest.fn() }));
jest.mock('../../../util/logs', () => ({
  ...jest.requireActual('../../../util/logs'), logDebugError: jest.fn(), logDebugApi: jest.fn(),
}));
jest.mock('../../../util/agent/clearLegacyAgentStorage', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/notificationSound', () => ({ initializeSounds: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(), getActions: jest.fn(),
}));

const MAIN = '0-ton-mainnet';
const OTHER = '1-ton-mainnet';
const TEST = '0-ton-testnet';
const PASSCODE = '123456';
const SECRET = 'angry calm sad';
const IDS = [MAIN, OTHER, TEST] as const;
const METHODS = { ...accountMethods, ...authMethods, ping: () => undefined };
const addresses = { [MAIN]: 'EQmain', [OTHER]: 'EQother', [TEST]: 'kQtest' };
type Level = 'account' | 'network' | 'all';
type Handler = (global: GlobalState, actions: AnyLiteral, payload?: any) => unknown;
let values: Map<string, any>;
let secrets: Map<string, StorageValue>;
let enclaveStorage: SimpleStorage;
let fault: string | undefined;
let didDropResponse: boolean;
let actions: AnyLiteral;
const drain = () => new Promise((resolve) => setTimeout(resolve, 0));
const run = (name: string, payload?: any) => (
  jest.mocked(addActionHandler).mock.calls.find(([action]) => action === name)![1] as Handler
)(getGlobal(), actions, payload);

async function beforeWrite(operation: string) {
  if (operation === fault) {
    await drain();
    throw new Error(`Failed ${operation}`);
  }
}

function reopenEnclave() {
  jest.isolateModules(() => {
    mockEnclave = jest.requireActual('../../../enclave/enclave');
  });
  return mockEnclave.setupStorage(enclaveStorage);
}

function reopenPopup(isMigration = false) {
  jest.isolateModules(() => {
    mockConnector = jest.requireActual('../../../api/providers/worker/connector');
  });
  mockInit.mockImplementation(() => {
    if (isMigration) mockUpdate({ type: 'migrateLegacyCoreApplication', currentAccountId: MAIN, accounts: [] });
    return Promise.resolve();
  });
  mockConnector.initApi(jest.fn(), {}, () => {
    const global = getGlobal();
    const id = global.currentAccountId;
    const account = id && global.accounts?.byId[id];
    return {
      current: id && account ? {
        accountId: id, type: account.type, addressByChain: { ton: account.byChain.ton!.address },
      } : undefined,
      isLegacyCoreMigrationCompleted: true,
    };
  });
  return mockConnector.callApiWithThrow('ping');
}

const previousExtensionFlag = process.env.IS_EXTENSION;
const previousExtraFeaturesFlag = process.env.NO_EXTRA_FEATURES;
beforeAll(() => {
  process.env.IS_EXTENSION = '1';
  delete process.env.NO_EXTRA_FEATURES;
});
afterAll(() => {
  if (previousExtensionFlag === undefined) delete process.env.IS_EXTENSION;
  else process.env.IS_EXTENSION = previousExtensionFlag;
  if (previousExtraFeaturesFlag === undefined) delete process.env.NO_EXTRA_FEATURES;
  else process.env.NO_EXTRA_FEATURES = previousExtraFeaturesFlag;
});
beforeEach(async () => {
  fault = undefined;
  didDropResponse = false;
  const accounts = Object.fromEntries(IDS.map((id) => [id, {
    type: 'ton', byChain: { ton: { address: addresses[id], index: 0 } },
  }])) as Record<string, ApiAccountAny>;
  values = new Map<string, any>([
    ['accounts', accounts], ['currentAccountId', MAIN], ['dapps', Object.fromEntries(IDS.map((id) => [id, {}]))],
  ]);
  jest.mocked(storage.getItem).mockImplementation((key) => Promise.resolve(values.get(key)));
  jest.mocked(storage.getMany!).mockImplementation((keys) => Promise.resolve(
    Object.fromEntries(keys.map((key) => [key, values.get(key)])),
  ));
  jest.mocked(storage.setItem).mockImplementation(async (key, value) => {
    await beforeWrite(`set:${key}`);
    values.set(key, value);
  });
  jest.mocked(storage.mutateItem!).mockImplementation(async (key, mutate) => {
    await beforeWrite(`mutate:${key}`);
    const value = mutate(values.get(key));
    values.set(key, value);
    return value;
  });
  jest.mocked(storage.removeItem).mockImplementation(async (key) => {
    await beforeWrite(`remove:${key}`);
    values.delete(key);
  });
  jest.mocked(tokenRepository.clear).mockImplementation(() => beforeWrite('tokens'));
  jest.mocked(resetAgentV2).mockImplementation(() => beforeWrite('agent'));
  secrets = new Map();
  enclaveStorage = {
    getItem: (name) => Promise.resolve(secrets.get(name)),
    setItem: (name, value) => {
      secrets.set(name, value);
      return Promise.resolve();
    },
    removeItem: (name) => {
      secrets.delete(name);
      return Promise.resolve();
    },
    clear: () => {
      secrets.clear();
      return Promise.resolve();
    },
    getAllKeys: () => Promise.resolve([...secrets.keys()] as EnclaveStorageKey[]),
  };
  await reopenEnclave();
  await mockEnclave.setupAuth('passcode', PASSCODE);
  for (const id of IDS) {
    const session = await mockEnclave.authorize('passcode', false, PASSCODE);
    await mockEnclave.importSecret(id, SECRET, session!.token);
  }
  jest.mocked(setGlobal).mockImplementation((global) => jest.mocked(getGlobal).mockReturnValue(global));
  jest.mocked(getGlobal).mockReturnValue({
    auth: {}, currentAccountId: MAIN,
    accounts: { byId: Object.fromEntries(IDS.map((id) => [id, {
      type: 'mnemonic', byChain: { ton: { address: addresses[id] } },
    }])) },
    byAccountId: Object.fromEntries(IDS.map((id) => [id, {}])),
    settings: { isTestnet: false, byAccountId: Object.fromEntries(IDS.map((id) => [id, {}])) },
  } as unknown as GlobalState);
  actions = {
    showError: jest.fn(), deleteAllNotificationAccounts: jest.fn(), closeSettings: jest.fn(),
    afterSignOut: (payload: any) => run('afterSignOut', payload), resetApiSettings: jest.fn(), init: jest.fn(),
    switchAccount: jest.fn(),
  };
  mockRequest.mockReset().mockImplementation(async ({ name, args }) => {
    const result = await (METHODS[name as keyof typeof METHODS] as AnyFunction)(...args);
    if (fault === 'response' && ['removeAccount', 'removeNetworkAccounts', 'resetAccounts'].includes(name)) {
      didDropResponse = true;
      return new Promise(() => undefined);
    }
    return result;
  });
  await reopenPopup();
});

it.each<[Level, string]>([
  ['account', 'set:currentAccountId'], ['network', 'mutate:dapps'],
  ['all', 'remove:dapps'], ['all', 'tokens'], ['all', 'agent'],
  ['account', 'response'], ['network', 'response'], ['all', 'response'],
])('reopens and retries %s removal after %s with surviving secrets intact', async (level, failedOperation) => {
  const beforeUi = getGlobal();
  const beforeSecrets = new Map(secrets);
  fault = failedOperation;
  const removal = run('signOut', { level, accountId: MAIN });
  if (failedOperation === 'response') {
    for (let i = 0; i < 30 && !didDropResponse; i++) await drain();
    expect(didDropResponse).toBe(true);
  } else {
    await removal;
    expect(actions.showError).toHaveBeenCalledTimes(1);
  }
  expect(getGlobal()).toBe(beforeUi);
  expect(secrets).toEqual(beforeSecrets);
  await expect(fetchStoredAccount(MAIN)).rejects.toThrow('doesn\'t exist');

  fault = undefined;
  await reopenEnclave();
  await reopenPopup();
  expect(values.get('currentAccountId')).toBeUndefined();
  expect(getGlobal()).toBe(beforeUi);
  expect(secrets).toEqual(beforeSecrets);
  const removedSession = await mockEnclave.authorize('passcode', false, PASSCODE);
  await expect(mockEnclave.exportSecret(MAIN, removedSession!.token)).resolves.toBe(SECRET);

  await run('signOut', { level, accountId: MAIN });
  const survivingIds = level === 'account' ? [OTHER, TEST] : level === 'network' ? [TEST] : [];
  expect(Object.keys(values.get('accounts') ?? {})).toEqual(survivingIds);
  if (level === 'all') {
    await drain();
    expect(secrets.size).toBe(0);
    expect(actions.init).toHaveBeenCalledTimes(1);
  } else {
    expect(Object.keys(getGlobal().accounts!.byId)).toEqual(survivingIds);
    await reopenEnclave();
    await reopenPopup();
    expect(values.get('currentAccountId')).toBe(survivingIds[0]);
    for (const id of survivingIds) {
      expect(secrets.get(`encryptedSecret#${id}`)).toEqual(beforeSecrets.get(`encryptedSecret#${id}`));
      const session = await mockEnclave.authorize('passcode', false, PASSCODE);
      await expect(mockEnclave.exportSecret(id, session!.token)).resolves.toBe(SECRET);
    }
  }
});

it('keeps the migration barrier closed when a migrated SDK account is missing', async () => {
  values.set('accounts', {});
  const beforeSecrets = new Map(secrets);
  await expect(reopenPopup(true)).rejects.toThrow('account');
  await expect(mockConnector.callApiWithThrow('resetAccounts')).rejects.toThrow('account');
  expect(secrets).toEqual(beforeSecrets);
});

it('keeps API mutations blocked when ordinary recovery cannot deactivate the missing account', async () => {
  values.set('accounts', {});
  fault = 'remove:currentAccountId';
  const beforeSecrets = new Map(secrets);
  const beforeUi = getGlobal();
  mockRequest.mockClear();
  await expect(reopenPopup()).rejects.toThrow('Failed remove:currentAccountId');
  await expect(mockConnector.callApiWithThrow('resetAccounts')).rejects.toThrow('Failed remove:currentAccountId');
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual(['restoreAccountAfterInitialization']);
  expect(secrets).toEqual(beforeSecrets);
  expect(getGlobal()).toBe(beforeUi);
});

it('keeps API mutations blocked when a reused account ID belongs to another identity', async () => {
  values.set('accounts', { [MAIN]: { type: 'ton', byChain: { ton: { address: 'EQdifferent' } } } });
  const beforeSecrets = new Map(secrets);
  mockRequest.mockClear();
  await expect(reopenPopup()).rejects.toThrow('account');
  await expect(mockConnector.callApiWithThrow('resetAccounts')).rejects.toThrow('account');
  expect(mockRequest.mock.calls.map(([request]) => request.name)).toEqual(['restoreAccountAfterInitialization']);
  expect(secrets).toEqual(beforeSecrets);
});
