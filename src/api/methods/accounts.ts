import type { ApiActivityTimestamps, OnApiUpdate } from '../types';

import { IS_EXTENSION } from '../../config';
import { getOrderedAccountChains } from '../../util/chain';
import { SOLANA_DERIVATION_PATHS } from '../chains/solana/constants';
import { TRON_BIP39_PATH } from '../chains/tron/constants';
import {
  fetchStoredAccount,
  fetchStoredAccounts,
  getAccountChains,
  getCurrentAccountId,
  loginResolve,
  updateStoredWallet,
} from '../common/accounts';
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
    let byChain = account.byChain;

    if (account.type === 'bip39' && account.byChain.tron?.address && !account.byChain.tron.derivation) {
      await updateStoredWallet(accountId, 'tron', {
        derivation: { path: TRON_BIP39_PATH, index: 0 },
      });

      byChain = {
        ...account.byChain,
        tron: { ...account.byChain.tron, derivation: { path: TRON_BIP39_PATH, index: 0 } },
      };
    }

    // `getOrderedAccountChains` filters out stored keys that are no longer in CHAIN_CONFIG,
    // so they don't propagate into global state via `updateAccount`.
    for (const chain of getOrderedAccountChains(byChain)) {
      const wallet = byChain[chain];
      if (!wallet?.derivation) continue;

      const derivationLabel = Object.entries(SOLANA_DERIVATION_PATHS)
        .find(([_, path]) => path === wallet.derivation?.path)?.[0];

      onUpdate({
        type: 'updateAccount',
        accountId,
        chain,
        derivation: {
          path: wallet.derivation.path,
          index: wallet.derivation.index,
          label: wallet.derivation.label || derivationLabel,
        },
      });
    }
  }
}

export async function fetchStoredAccountSummary(accountId: string) {
  const account = await fetchStoredAccount(accountId);
  return {
    byChain: getAccountChains(account),
  };
}

export async function deactivateAllAccounts() {
  void setActivePollingAccount(undefined, {});
  await storage.removeItem('currentAccountId');

  if (IS_EXTENSION) {
    void callHook('onFullLogout');
  }
}
