import type { LegacyAccountWithMnemonic, LegacyAuthConfig, MigrationOutcome } from './legacy';

import { authorize, importSecret, isAuthProvisioned, setupAuth } from './enclave';
import {
  getLegacyBiometricPassword,
  isLegacyBiometricAuth,
  migrateToEnclave,
  migrateToEnclaveBiometric,
} from './legacy';

/**
 * Performs full migration from legacy auth to Enclave.
 * This should be called when user enters their password for the first time after update.
 */
export async function migrateFromLegacy(
  legacyAccounts: LegacyAccountWithMnemonic[],
  password: string,
  isLongSession: boolean = false,
  usageCount?: number,
): Promise<MigrationOutcome> {
  return migrateToEnclave(legacyAccounts, password, isLongSession, {
    setupAuth,
    authorize,
    isAuthProvisioned,
    importSecret,
  }, usageCount);
}

/**
 * Performs full migration from legacy biometric auth to Enclave biometrics.
 */
export async function migrateFromLegacyBiometric(
  legacyAccounts: LegacyAccountWithMnemonic[],
  legacyPassword: string,
  usageCount?: number,
): Promise<MigrationOutcome> {
  return migrateToEnclaveBiometric(legacyAccounts, legacyPassword, {
    setupAuth,
    authorize,
    isAuthProvisioned,
    importSecret,
  }, usageCount);
}

/**
 * Retrieves password from legacy biometric storage for migration.
 * Should be called before `migrateFromLegacy` when user had biometrics enabled.
 */
export async function getPasswordFromLegacyBiometrics(
  authConfig: LegacyAuthConfig,
): Promise<string | undefined> {
  if (!isLegacyBiometricAuth(authConfig)) {
    return undefined;
  }

  return getLegacyBiometricPassword(authConfig);
}

export { type LegacyAuthConfig };
