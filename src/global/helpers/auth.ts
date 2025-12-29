import type { GlobalState } from '../types';

import { omit } from '../../util/iteratees';
import { callApi } from '../../api';
import { getGlobal, setGlobal } from '../index';

export async function removeTemporaryAccount(accountId: string) {
  const { currentAccountId: nextAccountId } = getGlobal();

  await callApi('removeAccount', accountId, nextAccountId);

  const global = getGlobal();
  const updatedGlobal = cleanupTemporaryAccountState(global, accountId);
  setGlobal(updatedGlobal);
}

function cleanupTemporaryAccountState(global: GlobalState, accountId: string): GlobalState {
  const { accounts, byAccountId, settings } = global;

  const newAccountsById = accounts ? omit(accounts.byId, [accountId]) : undefined;
  const newByAccountId = omit(byAccountId, [accountId]);
  const newSettingsByAccountId = omit(settings.byAccountId, [accountId]);
  const orderedAccountIds = settings.orderedAccountIds?.filter((id) => id !== accountId);

  return {
    ...global,
    currentTemporaryViewAccountId: undefined,
    accounts: accounts && newAccountsById ? { ...accounts, byId: newAccountsById } : accounts,
    byAccountId: newByAccountId,
    settings: {
      ...settings,
      byAccountId: newSettingsByAccountId,
      orderedAccountIds,
    },
  };
}
