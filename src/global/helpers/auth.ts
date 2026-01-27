import type { ApiAuthImportViewAccountResult, ApiChain, ApiNetwork } from '../../api/types';
import type { getActions } from '../index';
import type { GlobalState } from '../types';
import { AppState } from '../types';

import { TEMPORARY_ACCOUNT_NAME } from '../../config';
import { omit } from '../../util/iteratees';
import { getTranslation } from '../../util/langProvider';
import { callApi } from '../../api';
import { getGlobal, setGlobal } from '../index';
import { createAccount, updateAccounts } from '../reducers';
import { selectNetworkAccounts } from '../selectors';

export async function removeTemporaryAccount(accountId: string) {
  const { currentAccountId } = getGlobal();
  // Don't pass the same accountId as nextAccountId - it will be deleted and can't be activated
  const nextAccountId = currentAccountId !== accountId ? currentAccountId : undefined;

  await callApi('removeAccount', accountId, nextAccountId);

  const global = getGlobal();
  const updatedGlobal = cleanupTemporaryAccountState(global, accountId);
  setGlobal(updatedGlobal);
}

function cleanupTemporaryAccountState(global: GlobalState, accountId: string): GlobalState {
  const { accounts, byAccountId, settings, currentAccountId } = global;

  const newAccountsById = accounts ? omit(accounts.byId, [accountId]) : undefined;
  const newByAccountId = omit(byAccountId, [accountId]);
  const newSettingsByAccountId = omit(settings.byAccountId, [accountId]);
  const orderedAccountIds = settings.orderedAccountIds?.filter((id) => id !== accountId);

  return {
    ...global,
    currentTemporaryViewAccountId: undefined,
    // Clear currentAccountId if it points to the removed account
    currentAccountId: currentAccountId === accountId ? undefined : currentAccountId,
    accounts: accounts && newAccountsById ? { ...accounts, byId: newAccountsById } : accounts,
    byAccountId: newByAccountId,
    settings: {
      ...settings,
      byAccountId: newSettingsByAccountId,
      orderedAccountIds,
    },
  };
}

export async function importTemporaryViewAccount(
  network: ApiNetwork,
  addressByChain: Partial<Record<ApiChain, string>>,
) {
  let global = getGlobal();
  global = updateAccounts(global, { isLoading: true });
  setGlobal(global);

  const result = await callApi('importViewAccount', network, addressByChain, true);

  global = getGlobal();
  global = updateAccounts(global, { isLoading: undefined });
  setGlobal(global);

  return result;
}

export function createAndSetTemporaryAccount(
  result: ApiAuthImportViewAccountResult,
  additionalUpdates?: Partial<GlobalState>,
): void {
  let global = getGlobal();
  global = createAccount({
    global,
    accountId: result.accountId,
    byChain: result.byChain,
    type: 'view',
    partial: {
      title: result.title || getTranslation(TEMPORARY_ACCOUNT_NAME),
      isTemporary: true,
    },
  });

  global = {
    ...global,
    currentTemporaryViewAccountId: result.accountId,
    ...additionalUpdates,
  };

  setGlobal(global);
}

export function finalizeAccountCreation(
  actions: ReturnType<typeof getActions>,
  shouldSwitchToWallet: boolean | undefined,
  switchingDuration: number,
): void {
  if (getGlobal().areSettingsOpen) {
    actions.closeSettings(undefined, { forceOnHeavyAnimation: true });
  }

  if (shouldSwitchToWallet) {
    window.setTimeout(() => {
      actions.switchToWallet();
    }, switchingDuration);
  }
}

export function findExistingAccountByAddresses(
  global: GlobalState,
  addressByChain: Partial<Record<ApiChain, string>>,
): string | undefined {
  const accounts = selectNetworkAccounts(global);
  if (!accounts) return undefined;

  return Object.keys(accounts).find((accountId) => {
    const account = accounts[accountId];
    if (account.isTemporary) return false;

    return (Object.keys(addressByChain) as ApiChain[]).every(
      (chain) => account.byChain[chain]?.address === addressByChain[chain],
    );
  });
}

export async function handleExplorerMode(
  global: GlobalState,
  actions: ReturnType<typeof getActions>,
  network: ApiNetwork,
  addressByChain: Partial<Record<ApiChain, string>>,
  switchingDuration: number,
) {
  if (global.currentTemporaryViewAccountId) {
    await removeTemporaryAccount(global.currentTemporaryViewAccountId);
  }

  const result = await importTemporaryViewAccount(network, addressByChain);

  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  createAndSetTemporaryAccount(result, {
    currentAccountId: result.accountId,
    appState: AppState.Main,
  });

  finalizeAccountCreation(actions, true, switchingDuration);
}

export async function handleStandardMode(
  global: GlobalState,
  actions: ReturnType<typeof getActions>,
  network: ApiNetwork,
  addressByChain: Partial<Record<ApiChain, string>>,
  switchingDuration: number,
  getIsPortrait: () => boolean | undefined,
) {
  const existingAccountId = findExistingAccountByAddresses(global, addressByChain);

  if (global.currentTemporaryViewAccountId) {
    await removeTemporaryAccount(global.currentTemporaryViewAccountId);
  }

  if (existingAccountId) {
    actions.switchAccount({ accountId: existingAccountId });
    return;
  }

  const result = await importTemporaryViewAccount(network, addressByChain);

  if (!result || 'error' in result) {
    actions.showError({ error: result?.error });
    return;
  }

  createAndSetTemporaryAccount(result);

  finalizeAccountCreation(actions, getIsPortrait(), switchingDuration);
}
