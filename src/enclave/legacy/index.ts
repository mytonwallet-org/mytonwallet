export {
  getLegacyBiometricPassword,
  isLegacyBiometricAuth,
  type LegacyAuthConfig,
  type LegacyAuthPassword,
  type LegacyElectronSafeStorage,
  type LegacyNativeBiometrics,
  type LegacyWebAuthn,
} from './auth';

export {
  checkIsMigrationFailure,
  decryptLegacyMnemonic,
  migrateToEnclave,
  migrateToEnclaveBiometric,
  type LegacyAccountWithMnemonic,
  type MigrationErrorReason,
  type MigrationOutcome,
} from './migration';
