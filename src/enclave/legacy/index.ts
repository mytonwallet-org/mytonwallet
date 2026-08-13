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
  describeThrownError,
  migrateToEnclave,
  migrateToEnclaveBiometric,
  type LegacyAccountWithMnemonic,
  type MigrationErrorCause,
  type MigrationFailureReason,
  type MigrationOutcome,
  type MigrationStep,
} from './migration';
