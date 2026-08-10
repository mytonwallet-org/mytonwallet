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
 * Drops the legacy mnemonic of every account the Enclave took over. The list names what to erase rather
 * than what to spare, so a caller that passes nothing erases nothing: for any account left out, the
 * ciphertext is the only copy of that wallet still in existence.
 */
export async function cleanupLegacyAuthAfterMigration(migratedAccountIds: string[]): Promise<void> {
  const accounts = await storage.getItem('accounts') as Record<string, any> | undefined;
  if (!accounts) return;

  const migrated = new Set(migratedAccountIds);

  // Android hands out the cached object itself, so the stripped copy is built beside it and only
  // becomes the stored state once the write goes through
  const nextAccounts: Record<string, any> = {};
  let hasChanges = false;

  for (const [accountId, account] of Object.entries(accounts)) {
    if (account.mnemonicEncrypted && migrated.has(accountId)) {
      const { mnemonicEncrypted, ...rest } = account;
      nextAccounts[accountId] = rest;
      hasChanges = true;
    } else {
      nextAccounts[accountId] = account;
    }
  }

  if (hasChanges) {
    await storage.setItem('accounts', nextAccounts);
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
