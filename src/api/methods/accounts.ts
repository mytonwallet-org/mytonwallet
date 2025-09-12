import type { ApiActivityTimestamps, ApiTonWallet, OnApiUpdate } from '../types';

import { IS_EXTENSION } from '../../config';
import { fetchStoredAccount, fetchStoredWallet, getCurrentAccountId, loginResolve } from '../common/accounts';
import { waitStorageMigration } from '../common/helpers';
import { sendUpdateTokens } from '../common/tokens';
import { callHook } from '../hooks';
import { storage } from '../storages';
import { setActivePollingAccount } from './polling';

let onUpdate: OnApiUpdate;

export function initAccounts(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function activateAccount(accountId: string, newestActivityTimestamps: ApiActivityTimestamps = {}) {
  await waitStorageMigration();

  const prevAccountId = await getCurrentAccountId();
  const isFirstLogin = !prevAccountId;

  await storage.setItem('currentAccountId', accountId);
  loginResolve();

  if (IS_EXTENSION) {
    void callHook('onFirstLogin');
  }

  if (isFirstLogin) {
    sendUpdateTokens(onUpdate);
  }

  void setActivePollingAccount(accountId, newestActivityTimestamps);
}

export async function deactivateAllAccounts() {
  void setActivePollingAccount(undefined, {});
  await storage.removeItem('currentAccountId');

  if (IS_EXTENSION) {
    void callHook('onFullLogout');
  }
}

export function fetchTonWallet(accountId: string): Promise<ApiTonWallet> {
  return fetchStoredWallet(accountId, 'ton');
}

export async function fetchLedgerAccount(accountId: string) {
  const account = await fetchStoredAccount(accountId);
  if (account.type === 'ledger') return account;
  throw new Error(`Account ${accountId} is not a Ledger account`);
}
