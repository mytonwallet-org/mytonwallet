import './initial';

import type { GlobalState } from '../../types';

import { getAgentV2LocalState } from '../../../util/agent/agentV2LocalState';
import { callApiWithThrow } from '../../../api';
import { enclave } from '../../../enclave';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../../api', () => ({ callApiWithThrow: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../../enclave', () => ({ enclave: { removeSecret: jest.fn(), reset: jest.fn() } }));
jest.mock('../../../util/agent/clearLegacyAgentStorage', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('../../../util/notificationSound', () => ({ initializeSounds: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(), getActions: jest.fn(() => ({})),
}));

const MAIN = '0-ton-mainnet';
const TEST = '0-ton-testnet';
type Handler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => Promise<void>;

function handler(name: string) {
  return jest.mocked(addActionHandler).mock.calls.find(([action]) => action === name)![1] as Handler;
}

function makeGlobal() {
  return {
    currentAccountId: MAIN,
    accounts: { byId: { [MAIN]: { type: 'mnemonic' }, [TEST]: { type: 'mnemonic', title: 'Existing testnet' } } },
    byAccountId: { [MAIN]: {}, [TEST]: { currentTokenSlug: 'testnet-token' } },
    settings: { isTestnet: false, byAccountId: { [MAIN]: {}, [TEST]: { pinnedSlugs: ['testnet-token'] } } },
  } as unknown as GlobalState;
}

beforeEach(() => {
  getAgentV2LocalState().draftOnMount = 'Private draft';
  localStorage.setItem('mytonwallet-agent-last-thread', 'old-thread');
  localStorage.setItem('mytonwallet-agent-thread-read-state', 'old-state');
  jest.mocked(callApiWithThrow).mockClear();
  jest.mocked(enclave.reset).mockClear();
  jest.mocked(enclave.removeSecret).mockClear();
  jest.mocked(setGlobal).mockImplementation((global) => jest.mocked(getGlobal).mockReturnValue(global));
  jest.mocked(getGlobal).mockReturnValue(makeGlobal());
});

function makeActions() {
  const actions = {
    deleteAllNotificationAccounts: jest.fn(), switchAccount: jest.fn(), closeSettings: jest.fn(),
    resetApiSettings: jest.fn(), init: jest.fn(), afterSignOut: jest.fn(),
  };
  actions.afterSignOut.mockImplementation((payload) => handler('afterSignOut')(getGlobal(), actions, payload));
  return actions;
}

it.each(['account', 'network'])('removing %s on mainnet preserves the existing other-network wallet', async (level) => {
  const actions = makeActions();
  await handler('signOut')(getGlobal(), actions, { level, accountId: MAIN });
  expect(callApiWithThrow).toHaveBeenCalledWith('removeNetworkAccounts', 'mainnet');
  expect(callApiWithThrow).not.toHaveBeenCalledWith('resetAccounts');
  expect(enclave.reset).not.toHaveBeenCalled();
  expect(getGlobal().accounts!.byId).toEqual({ [TEST]: { type: 'mnemonic', title: 'Existing testnet' } });
  expect(getGlobal().byAccountId[TEST].currentTokenSlug).toBe('testnet-token');
  expect(getGlobal().settings.byAccountId[TEST]?.pinnedSlugs).toEqual(['testnet-token']);
  expect(actions.switchAccount).toHaveBeenCalledWith({ accountId: TEST, newNetwork: 'testnet' });
  expect(localStorage.getItem('mytonwallet-agent-last-thread')).toBe('old-thread');
  expect(localStorage.getItem('mytonwallet-agent-thread-read-state')).toBe('old-state');
  expect(getAgentV2LocalState().draftOnMount).toBe('Private draft');
});

it('explicit all-account removal resets SDK once before clearing Enclave', async () => {
  const actions = makeActions();
  await handler('signOut')(getGlobal(), actions, { level: 'all' });
  expect(callApiWithThrow).toHaveBeenCalledTimes(1);
  expect(callApiWithThrow).toHaveBeenCalledWith('resetAccounts');
  expect(enclave.reset).toHaveBeenCalledTimes(1);
  expect(actions.afterSignOut).toHaveBeenCalledWith({ shouldReset: true });
  expect(actions.init).toHaveBeenCalledTimes(1);
  expect(localStorage.getItem('mytonwallet-agent-last-thread')).toBeNull();
  expect(localStorage.getItem('mytonwallet-agent-thread-read-state')).toBeNull();
  expect(getAgentV2LocalState().draftOnMount).toBe('');
});

it('clears Enclave when Agent storage cannot be removed', async () => {
  const removeItem = jest.spyOn(Storage.prototype, 'removeItem').mockImplementation(() => {
    throw new Error('Storage is unavailable');
  });

  try {
    await handler('afterSignOut')(getGlobal(), makeActions(), { shouldReset: true });
    expect(enclave.reset).toHaveBeenCalledTimes(1);
    expect(getAgentV2LocalState().draftOnMount).toBe('');
  } finally {
    removeItem.mockRestore();
  }
});
