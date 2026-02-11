import type { ApiActivityTimestamps, OnApiUpdate } from '../types';

import { IS_EXTENSION } from '../../config';
import { getCurrentAccountId, loginResolve } from '../common/accounts';
import { sendUpdateTokens } from '../common/tokens';
import { callHook } from '../hooks';
import { storage } from '../storages';
import { setActivePollingAccount } from './polling';

let onUpdate: OnApiUpdate;

export function initAccounts(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function activateAccount(accountId: string, newestActivityTimestamps: ApiActivityTimestamps = {}) {
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
