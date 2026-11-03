import type { AccountType, AuthType } from '../global/types';

import { INDEXED_DB_NAME, IS_AIR_APP, IS_EXPLORER, IS_EXTENSION } from '../config';
import { INDEXED_DB_NAME as ENCLAVE_INDEXED_DB_NAME } from '../enclave/config';
import { logDebugError } from './logs';
import { pause } from './schedulers';

type Presence = 'present' | 'absent' | 'unknown';

interface BootPresence {
  keyvalStore: Presence;
  /** Only where the Electron shell can restore storage, which writes the store when it carries a copy */
  keyvalStoreAfterRestore?: Presence;
  enclave: Presence;
}

const EVIDENCE_STORAGE_KEY = 'mtw-idb-loss-evidence';
const LISTING_TIMEOUT_MS = 1000;
// The extension and Air keep the API storage outside IndexedDB, and Explorer clears it on every visit
const IS_KEYVAL_STORE_EXPECTED = !IS_EXTENSION && !IS_AIR_APP && !IS_EXPLORER;

let bootPresence: Promise<BootPresence> | undefined;

/**
 * idb-keyval creates a database on its first open, so this runs before anything reads either store:
 * a moment later the absence it looks for is already gone.
 */
export function probeIndexedDb(restoreStorage?: () => Promise<unknown>) {
  bootPresence = (async () => {
    const atBoot = describePresence(await listDatabases());
    if (!restoreStorage) return atBoot;

    await restoreStorage();

    return { ...atBoot, keyvalStoreAfterRestore: getPresence(await listDatabases(), INDEXED_DB_NAME) };
  })();

  return bootPresence;
}

export async function reportIndexedDbLoss(accountTypes: AccountType[], authTypes: AuthType[] | undefined) {
  // Taken before the first await, so an API reconnect that runs this again finds nothing left to report
  const probe = bootPresence;
  bootPresence = undefined;

  const atThisBoot = await probe?.catch(() => undefined);
  if (!atThisBoot || !accountTypes.length) return;

  // The Electron shell writes the store from a copy when it switches the origin the bundle loads from, and
  // only a listing taken after that restore can confirm the store is still gone
  const isKeyvalStoreLost = IS_KEYVAL_STORE_EXPECTED && atThisBoot.keyvalStore === 'absent'
    && (atThisBoot.keyvalStoreAfterRestore ?? 'absent') === 'absent';
  // Nothing is written to the Enclave before an auth is set up, so until then its database never existed
  const isEnclaveLost = Boolean(authTypes?.length) && atThisBoot.enclave === 'absent';
  const firstFound = getIndexedDbLossEvidence()
    ?? (isKeyvalStoreLost || isEnclaveLost ? writeEvidence(atThisBoot) : undefined);
  if (!firstFound) return;

  logDebugError('IndexedDB: wallet storage was found missing', {
    atThisBoot,
    firstFound,
    accountCount: accountTypes.length,
    accountTypes: countTypes(accountTypes),
    authTypes: authTypes ?? 'none',
    storage: await describeStorage(),
  });
}

export function clearIndexedDbLossEvidence() {
  try {
    localStorage.removeItem(EVIDENCE_STORAGE_KEY);
  } catch {
    // Nothing to clear where the storage cannot be reached
  }
}

async function listDatabases() {
  try {
    const databases = await Promise.race([
      indexedDB.databases(),
      pause(LISTING_TIMEOUT_MS).then(() => undefined),
    ]);

    return databases && new Set(databases.map(({ name }) => name));
  } catch {
    return undefined;
  }
}

function describePresence(names: Set<string | undefined> | undefined): BootPresence {
  return {
    keyvalStore: getPresence(names, INDEXED_DB_NAME),
    enclave: getPresence(names, ENCLAVE_INDEXED_DB_NAME),
  };
}

function getPresence(names: Set<string | undefined> | undefined, name: string): Presence {
  return !names ? 'unknown' : names.has(name) ? 'present' : 'absent';
}

function countTypes(accountTypes: AccountType[]) {
  return accountTypes.reduce<Partial<Record<AccountType, number>>>((counts, type) => {
    counts[type] = (counts[type] ?? 0) + 1;
    return counts;
  }, {});
}

async function describeStorage() {
  try {
    const [isPersisted, { usage, quota }] = await Promise.all([
      navigator.storage.persisted(),
      navigator.storage.estimate(),
    ]);

    return { isPersisted, usage, quota };
  } catch (err) {
    return { error: String(err) };
  }
}

/**
 * The first open after a loss recreates the database empty, so only the boot that saw it absent can say
 * it was gone. That boot is kept for every later log export, which is when support gets to read it.
 */
export function getIndexedDbLossEvidence(): (BootPresence & { at: string }) | undefined {
  try {
    const json = localStorage.getItem(EVIDENCE_STORAGE_KEY);

    return json ? JSON.parse(json) : undefined;
  } catch {
    return undefined;
  }
}

function writeEvidence(presence: BootPresence) {
  const evidence = { at: new Date().toISOString(), ...presence };

  try {
    localStorage.setItem(EVIDENCE_STORAGE_KEY, JSON.stringify(evidence));
  } catch {
    // This boot still reports it, only later ones will not
  }

  return evidence;
}
