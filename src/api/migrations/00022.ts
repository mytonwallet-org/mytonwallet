import type { ApiAccountAny } from '../types';

import { SOLANA_DERIVATION_VERSION } from '../chains/solana/derivation';
import { storage } from '../storages';

/**
 * Stamps existing Solana wallets with `derivationVersion = SOLANA_DERIVATION_VERSION`.
 *
 * Wallets created before this migration have no version field. The chain-upgrade detector
 * treats `derivationVersion === undefined` as "needs upgrade", which would wrongly target
 * already-derived wallets. This migration marks them as up-to-date so only accounts
 * without Solana data will be picked up by the upgrade pipeline.
 */
export async function start() {
  const accounts: Record<string, ApiAccountAny> | undefined = await storage.getItem('accounts');

  if (!accounts) return;

  let hasChanges = false;

  Object.values(accounts).forEach((account) => {
    if (account.type !== 'bip39') return;

    const solanaWallet = account.byChain.solana;
    if (!solanaWallet || solanaWallet.derivationVersion !== undefined) return;

    solanaWallet.derivationVersion = SOLANA_DERIVATION_VERSION;

    hasChanges = true;
  });

  if (!hasChanges) return;

  await storage.setItem('accounts' as any, accounts);
}
