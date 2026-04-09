import type { ApiActivityTimestamps, ApiChain, OnApiUpdate } from '../types';

import { IS_EXTENSION } from '../../config';
import { SOLANA_DERIVATION_PATHS } from '../chains/solana/constants';
import { fetchStoredAccounts, getCurrentAccountId, loginResolve } from '../common/accounts';
import { sendUpdateTokens } from '../common/tokens';
import { callHook } from '../hooks';
import { storage } from '../storages';
import { setActivePollingAccount } from './polling';

let onUpdate: OnApiUpdate;

export function initAccounts(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function activateAccount(
  accountId: string,
  newestActivityTimestamps: ApiActivityTimestamps = {},
  shouldResetBalances?: boolean,
) {
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

  void setActivePollingAccount(accountId, newestActivityTimestamps, shouldResetBalances);
}

export async function loadAccountsDerivations() {
  const accounts = await fetchStoredAccounts();
  for (const [accountId, account] of Object.entries(accounts)) {
    for (const [chain, wallet] of Object.entries(account.byChain)) {
      if (wallet?.derivation) {
        const derivationLabel = Object.entries(SOLANA_DERIVATION_PATHS)
          .find(([_, path]) => path === wallet.derivation?.path)?.[0];

        onUpdate({
          type: 'updateAccount',
          accountId,
          chain: chain as ApiChain,
          derivation: {
            path: wallet.derivation.path,
            index: wallet.derivation.index,
            label: wallet.derivation.label || derivationLabel,
          },
        });
      }
    }
  }
}

export async function deactivateAllAccounts() {
  void setActivePollingAccount(undefined, {});
  await storage.removeItem('currentAccountId');

  if (IS_EXTENSION) {
    void callHook('onFullLogout');
  }
}
