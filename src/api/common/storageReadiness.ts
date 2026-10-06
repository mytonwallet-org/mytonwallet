import { storage } from '../storages';
import { actualStateVersion } from './helpers';

const LEGACY_CREDENTIAL_KEYS = ['address', 'words', 'publicKey'] as const;
const READINESS_KEYS = [
  'stateVersion',
  ...LEGACY_CREDENTIAL_KEYS,
  'legacyCoreAccountsConverted',
  'legacyCoreMigrationCompleted',
];

export async function isStorageMigrationReady() {
  try {
    const values = await storage.getMany!(READINESS_KEYS);
    if (Number(values.stateVersion) !== actualStateVersion) return false;

    const hasLegacyCredentials = LEGACY_CREDENTIAL_KEYS.some((key) => values[key] !== undefined);
    const hasPendingLegacyHandoff = hasLegacyCredentials || values.legacyCoreAccountsConverted === true;
    return !hasPendingLegacyHandoff || values.legacyCoreMigrationCompleted === true;
  } catch {
    return false;
  }
}
