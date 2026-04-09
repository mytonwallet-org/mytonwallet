import type { ApiAccountAny } from '../types';

import { TON_BIP39_PATH } from '../chains/ton/constants';
import { storage } from '../storages';

export async function start() {
  const accounts: Record<string, ApiAccountAny> | undefined = await storage.getItem('accounts');

  if (!accounts) {
    return;
  }

  let hasChanges = false;

  Object.values(accounts).forEach((account) => {
    if (account.type !== 'bip39') {
      return;
    }

    const tonWallet = account.byChain.ton;
    if (!tonWallet || tonWallet.derivation) {
      return;
    }

    tonWallet.derivation = {
      path: TON_BIP39_PATH,
      index: 0,
    };

    hasChanges = true;
  });

  if (!hasChanges) {
    return;
  }

  await storage.setItem('accounts' as any, accounts);
}
