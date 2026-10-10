import './initial';

import type { GlobalState } from '../../types';

import { callApi, initApi } from '../../../api';
import { enclave } from '../../../enclave';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { switchAccount } from '../api/auth';

const mockRequest = jest.fn();
const mockInit = jest.fn().mockResolvedValue(undefined);
jest.mock('../../../util/PostMessageConnector', () => ({
  createExtensionConnector: () => ({ init: mockInit, request: mockRequest }),
}));
jest.mock('../../../util/windowProvider', () => ({ createWindowProviderForExtension: jest.fn() }));
jest.mock('../../../util/chunkLoading', () => ({ reportApiChunkLoadError: jest.fn() }));
jest.mock('../../../util/logs', () => ({
  ...jest.requireActual('../../../util/logs'), logDebugError: jest.fn(), logDebugApi: jest.fn(),
}));
jest.mock('../../../enclave', () => ({
  enclave: { removeSecret: jest.fn(), reset: jest.fn(), importSecret: jest.fn(), duplicateSecret: jest.fn() },
}));
jest.mock('../../../util/agent/clearLegacyAgentStorage', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/notificationSound', () => ({ initializeSounds: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(), getActions: jest.fn(),
}));

const MAIN = '0-ton-mainnet';
const OTHER = '2-ton-mainnet';
const TEST = '0-ton-testnet';
const failure = new Error('SDK storage write rejected');
type Handler = (global: GlobalState, actions: AnyLiteral, payload?: any) => unknown;
const run = (name: string, payload?: any) => (
  jest.mocked(addActionHandler).mock.calls.find(([action]) => action === name)![1] as Handler
)(getGlobal(), actions, payload);
const drain = () => new Promise((resolve) => setTimeout(resolve, 0));
let actions: AnyLiteral;

function makeGlobal(ids: string[] = [MAIN, OTHER, TEST]): GlobalState {
  return {
    auth: {},
    currentAccountId: ids[0],
    accounts: { byId: Object.fromEntries(ids.map((id) => [id, {
      title: id, type: 'mnemonic', byChain: { ton: { address: id === TEST ? 'kQtest' : 'EQmain' } },
    }])) },
    byAccountId: Object.fromEntries(ids.map((id) => [id, {}])),
    settings: { isTestnet: false, byAccountId: Object.fromEntries(ids.map((id) => [id, { pinnedSlugs: [id] }])) },
    pushNotifications: { enabledAccounts: ids },
  } as unknown as GlobalState;
}

const previousExtensionFlag = process.env.IS_EXTENSION;
beforeAll(() => {
  process.env.IS_EXTENSION = '1';
});
afterAll(() => {
  if (previousExtensionFlag === undefined) delete process.env.IS_EXTENSION;
  else process.env.IS_EXTENSION = previousExtensionFlag;
});
beforeEach(() => {
  mockRequest.mockReset().mockResolvedValue(undefined);
  mockInit.mockReset().mockResolvedValue(undefined);
  jest.mocked(enclave.removeSecret).mockClear();
  jest.mocked(enclave.reset).mockClear();
  jest.mocked(enclave.importSecret).mockClear();
  jest.mocked(setGlobal).mockImplementation((global) => jest.mocked(getGlobal).mockReturnValue(global));
  jest.mocked(getGlobal).mockReturnValue(makeGlobal());
  actions = {
    showError: jest.fn(), afterSignIn: jest.fn(), afterSignOut: jest.fn(), init: jest.fn(),
    deleteAllNotificationAccounts: jest.fn(), deleteNotificationAccount: jest.fn(), closeSettings: jest.fn(),
    changeNetwork: jest.fn(), resetAuth: jest.fn(),
    switchAccount: jest.fn(({ accountId, newNetwork }) => switchAccount(getGlobal(), accountId, newNetwork)),
  };
  jest.mocked(getActions).mockReturnValue(actions as ReturnType<typeof getActions>);
  initApi(jest.fn(), {});
});

it.each(['account', 'network', 'all'])('preserves UI and secrets after rejected %s SDK removal', async (level) => {
  const before = getGlobal();
  mockRequest.mockRejectedValueOnce(failure);
  await expect(Promise.resolve(run('signOut', { level, accountId: MAIN }))).resolves.toBeUndefined();
  expect(getGlobal()).toBe(before);
  expect(enclave.removeSecret).not.toHaveBeenCalled();
  expect(enclave.reset).not.toHaveBeenCalled();
  expect(actions.deleteAllNotificationAccounts).not.toHaveBeenCalled();
  expect(actions.deleteNotificationAccount).not.toHaveBeenCalled();
  expect(actions.afterSignOut).not.toHaveBeenCalled();
  expect(actions.init).not.toHaveBeenCalled();
  expect(actions.showError).toHaveBeenCalledTimes(1);
});

it.each(['account', 'network', 'all'])('allows retrying %s removal after an SDK error', async (level) => {
  mockRequest.mockRejectedValueOnce(failure);
  await run('signOut', { level, accountId: MAIN });
  await run('signOut', { level, accountId: MAIN });
  const removedIds = level === 'account' ? [MAIN] : level === 'network' ? [MAIN, OTHER] : [MAIN, OTHER, TEST];
  expect(actions.deleteAllNotificationAccounts).toHaveBeenCalledTimes(1);
  expect(actions.deleteAllNotificationAccounts).toHaveBeenCalledWith({ accountIds: removedIds });
  expect(actions.deleteNotificationAccount).not.toHaveBeenCalled();
  expect(actions.afterSignOut).toHaveBeenCalledTimes(1);
  if (level === 'account') {
    expect(getGlobal().accounts!.byId[MAIN]).toBeUndefined();
    expect(getGlobal().accounts!.byId[OTHER]).toBeDefined();
    expect(getGlobal().accounts!.byId[TEST]).toBeDefined();
    expect(enclave.removeSecret).toHaveBeenCalledWith(MAIN);
  }
});

it('settles a failed SDK initialization without reporting logout success', async () => {
  const before = getGlobal();
  mockInit.mockRejectedValueOnce(failure);
  initApi(jest.fn(), {});
  await expect(Promise.resolve(run('signOut', { level: 'all' }))).resolves.toBeUndefined();
  expect(getGlobal()).toBe(before);
  expect(mockRequest).not.toHaveBeenCalled();
  expect(actions.afterSignOut).not.toHaveBeenCalled();
  expect(actions.showError).toHaveBeenCalledTimes(1);
});

it('full logout sends one reset and not a partial network deletion before its acknowledgment', async () => {
  let release!: () => void;
  mockRequest.mockReturnValueOnce(new Promise<void>((resolve) => {
    release = resolve;
  }));
  const signingOut = run('signOut', { level: 'all' });
  await drain();
  expect(mockRequest).toHaveBeenCalledTimes(1);
  expect(mockRequest).toHaveBeenCalledWith({ name: 'resetAccounts', args: [] });
  expect(actions.afterSignOut).not.toHaveBeenCalled();
  expect(actions.deleteAllNotificationAccounts).not.toHaveBeenCalled();
  release();
  await signingOut;
  expect(actions.deleteAllNotificationAccounts).toHaveBeenCalledWith({ accountIds: [MAIN, OTHER, TEST] });
  expect(actions.afterSignOut).toHaveBeenCalledWith({ shouldReset: true });
});

it('the worker tolerant facade really swallows the same void RPC failure', async () => {
  mockRequest.mockRejectedValueOnce(failure);
  await expect(callApi('resetAccounts')).resolves.toBeUndefined();
});
