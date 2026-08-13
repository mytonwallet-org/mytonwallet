import type * as EnclaveApi from './enclave';
import type * as LegacyMigrationApi from './legacyMigration';

import directEnclave from './providers/direct/connector';
import * as legacyMigration from './legacyMigration';

export type { LegacyAuthConfig } from './legacyMigration';
export {
  checkIsMigrationFailure,
  describeThrownError,
  type MigrationErrorCause,
  type MigrationFailureReason,
  type MigrationOutcome,
  type MigrationStep,
} from './legacy';
export { getTokenAuthType } from './enclave';

const enclave: typeof EnclaveApi = directEnclave;
const legacyAuth: typeof LegacyMigrationApi = legacyMigration;

export { enclave, legacyAuth };
