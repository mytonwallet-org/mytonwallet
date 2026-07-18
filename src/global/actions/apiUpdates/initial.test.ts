import './initial';

import type { ApiUpdateRemoveAccounts } from '../../../api/types/updates';
import type { GlobalState } from '../../types';

import { addActionHandler, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

type ApiUpdateHandler = (
  global: GlobalState,
  actions: AnyLiteral,
  update: ApiUpdateRemoveAccounts,
) => void;

function getApiUpdateHandler() {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([name]) => name === 'apiUpdate');
  return call![1] as ApiUpdateHandler;
}

function makeGlobal(currentAccountId: string): GlobalState {
  const account = { title: 'Test', type: 'mnemonic', byChain: {} };
  const accountIds = ['0-ton-mainnet', '0-ton-testnet'];
  return {
    currentAccountId,
    accounts: { byId: Object.fromEntries(accountIds.map((id) => [id, account])) },
    byAccountId: Object.fromEntries(accountIds.map((id) => [id, {}])),
    settings: {
      byAccountId: Object.fromEntries(accountIds.map((id) => [id, {}])),
      orderedAccountIds: accountIds,
    },
    pushNotifications: { enabledAccounts: [] },
  } as unknown as GlobalState;
}

describe('removeAccounts api update', () => {
  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
  });

  function dispatchRemoveAccounts(global: GlobalState, accountIds: string[]) {
    const actions = { switchAccount: jest.fn() };
    getApiUpdateHandler()(global, actions, { type: 'removeAccounts', accountIds });
    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    return { actions, updatedGlobal: updatedGlobal as GlobalState };
  }

  it('re-selects a surviving account when the removed one was current', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(makeGlobal('0-ton-testnet'), ['0-ton-testnet']);

    expect(updatedGlobal.byAccountId).not.toHaveProperty('0-ton-testnet');
    expect(actions.switchAccount).toHaveBeenCalledWith({ accountId: '0-ton-mainnet', newNetwork: 'mainnet' });
  });

  it('skips a stale ordered id that no longer has an account when picking the survivor', () => {
    const global = makeGlobal('0-ton-testnet');
    // `orderedAccountIds` retains a ghost id from an account removed in an earlier session (never cleaned there).
    global.settings.orderedAccountIds = ['9-ton-mainnet', '0-ton-mainnet', '0-ton-testnet'];

    const { actions } = dispatchRemoveAccounts(global, ['0-ton-testnet']);

    expect(actions.switchAccount).toHaveBeenCalledWith({ accountId: '0-ton-mainnet', newNetwork: 'mainnet' });
  });

  it('does not switch when the current account survives', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(makeGlobal('0-ton-mainnet'), ['0-ton-testnet']);

    expect(updatedGlobal.currentAccountId).toBe('0-ton-mainnet');
    expect(actions.switchAccount).not.toHaveBeenCalled();
  });

  it('leaves no account selected after a full wipe', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(
      makeGlobal('0-ton-testnet'),
      ['0-ton-mainnet', '0-ton-testnet'],
    );

    expect(updatedGlobal.currentAccountId).toBeUndefined();
    expect(actions.switchAccount).not.toHaveBeenCalled();
  });
});
