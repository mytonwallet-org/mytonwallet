import { callWindow } from '../../util/windowProvider/connector';
import { storage } from '../storages';

export interface LegacyAccountWithMnemonic {
  accountId: string;
  mnemonicEncrypted: string;
}

/**
 * Fetches all accounts that have `mnemonicEncrypted` field (legacy format).
 * Used to detect if migration is needed and to perform the migration.
 */
export async function fetchLegacyAccountsWithMnemonic(): Promise<LegacyAccountWithMnemonic[]> {
  const accounts = await storage.getItem('accounts') as Record<string, any> | undefined;
  if (!accounts) return [];

  const result: LegacyAccountWithMnemonic[] = [];

  for (const [accountId, account] of Object.entries(accounts)) {
    if (account.mnemonicEncrypted) {
      result.push({
        accountId,
        mnemonicEncrypted: account.mnemonicEncrypted,
      });
    }
  }

  return result;
}

/**
 * Cleans up legacy mnemonics after successful migration.
 * Removes `mnemonicEncrypted` from all accounts in storage.
 */
export async function cleanupLegacyAuthAfterMigration(): Promise<void> {
  const accounts = await storage.getItem('accounts') as Record<string, any> | undefined;
  if (!accounts) return;

  let hasChanges = false;
  for (const accountId of Object.keys(accounts)) {
    if (accounts[accountId].mnemonicEncrypted) {
      delete accounts[accountId].mnemonicEncrypted;
      hasChanges = true;
    }
  }

  if (hasChanges) {
    await storage.setItem('accounts', accounts);
  }
}

/**
 * Checks if legacy migration data exists (`mnemonicEncrypted` in accounts).
 * Used to determine if rollback is possible.
 */
export async function hasLegacyData(): Promise<boolean> {
  const accounts = await storage.getItem('accounts') as Record<string, any> | undefined;
  if (!accounts) return false;

  return Object.values(accounts).some((account) => Boolean(account.mnemonicEncrypted));
}

/**
 * Rolls back migration by clearing enclave storage data.
 * Global state (`authTypes`, `enclaveSession`) should be cleared by the UI.
 */
export async function rollbackEnclaveMigration(): Promise<void> {
  // The Enclave keeps its secrets and master keys in its own storage, which is only reachable
  // through the window provider
  await callWindow('resetEnclave');
}
