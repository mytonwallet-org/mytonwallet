import { enclave, legacyAuth } from '../../../enclave';

export const importSecret = enclave.importSecret;
export const exportSecret = enclave.exportSecret;
export const resetEnclave = enclave.reset;

// Migration methods
export const migrateAuth = enclave.migrateAuth;
export const migrateFromLegacy = legacyAuth.migrateFromLegacy;
export const migrateFromLegacyBiometric = legacyAuth.migrateFromLegacyBiometric;
export const getPasswordFromLegacyBiometrics = legacyAuth.getPasswordFromLegacyBiometrics;
