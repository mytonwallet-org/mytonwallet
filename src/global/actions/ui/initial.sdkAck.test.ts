import '../apiUpdates/initial';

import type { ApiUpdate } from '../../../api/types';
import type { GlobalState } from '../../types';

import { initApi } from '../../../api';
import { enclave } from '../../../enclave';
import { persistCache } from '../../cache';
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
jest.mock('../../cache', () => ({ persistCache: jest.fn(() => true) }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(), getActions: jest.fn(),
}));

const MAIN = '0-ton-mainnet';
const OTHER = '2-ton-mainnet';
const TEST = '0-ton-testnet';
const update: ApiUpdate = {
  type: 'migrateLegacyCoreApplication', currentAccountId: TEST,
  accounts: [{ accountId: TEST, address: 'kQtest' }],
};
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
  jest.mocked(persistCache).mockClear().mockReturnValue(true);
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

it('persists the synchronous handoff without issuing a competing activation', async () => {
  setGlobal(makeGlobal([]));
  run('apiUpdate', update);
  expect(getGlobal()).toMatchObject({
    currentAccountId: TEST, isLegacyCoreMigrationCompleted: true, settings: { isTestnet: true },
  });
  expect(persistCache).toHaveBeenCalledTimes(1);
  expect(actions.afterSignIn).not.toHaveBeenCalled();
  await drain();
  expect(mockRequest).not.toHaveBeenCalled();
});

it('preserves SDK-backed OTHER and its settings while repairing the original row', async () => {
  setGlobal(makeGlobal([OTHER]));
  const selected = getGlobal().accounts!.byId[OTHER];
  run('apiUpdate', {
    ...update, accounts: [...update.accounts, { accountId: OTHER, address: selected.byChain.ton!.address }],
  });
  expect(getGlobal().currentAccountId).toBe(OTHER);
  expect(getGlobal().accounts!.byId[OTHER]).toBe(selected);
  expect(getGlobal().settings.byAccountId[OTHER]?.pinnedSlugs).toEqual([OTHER]);
  await drain();
  expect(mockRequest).not.toHaveBeenCalled();
});

it('preserves a UI-only row but selects the SDK-backed original synchronously', () => {
  setGlobal(makeGlobal([OTHER]));
  const selected = getGlobal().accounts!.byId[OTHER];
  run('apiUpdate', update);
  expect(getGlobal().currentAccountId).toBe(TEST);
  expect(getGlobal().accounts!.byId[OTHER]).toBe(selected);
  expect(getGlobal().settings.byAccountId[OTHER]?.pinnedSlugs).toEqual([OTHER]);
  expect(getGlobal().settings.isTestnet).toBe(true);
});

it('can retry a failed cache write with the selected ID already repaired', async () => {
  setGlobal(makeGlobal([]));
  jest.mocked(persistCache).mockReturnValueOnce(false);
  run('apiUpdate', update);
  expect(getGlobal().isLegacyCoreMigrationCompleted).toBeUndefined();
  expect(mockRequest).not.toHaveBeenCalled();
  run('apiUpdate', update);
  expect(getGlobal().isLegacyCoreMigrationCompleted).toBe(true);
  expect(persistCache).toHaveBeenCalledTimes(2);
  await drain();
  expect(mockRequest).not.toHaveBeenCalled();
});
