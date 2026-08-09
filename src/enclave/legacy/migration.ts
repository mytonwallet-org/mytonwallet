import type { EnclaveSession } from '../../global/types';

import { PRIVATE_KEY_HEX_LENGTH } from '../../config';
import { logDebugError } from '../../util/logs';
import { EnclaveError } from '../errors';

export interface LegacyAccountWithMnemonic {
  accountId: string;
  mnemonicEncrypted: string;
}

interface EnclavePasscodeInterface {
  setupAuth: (authType: 'passcode', passcode: string) => Promise<EnclaveSession | undefined>;
  authorize: (
    authType: 'passcode',
    isLong: boolean,
    passcode: string,
    usageCount?: number,
  ) => Promise<EnclaveSession | undefined>;
  isAuthProvisioned: (authType: 'passcode') => Promise<boolean>;
  importSecret: (id: string, secret: string, token: string) => Promise<void>;
}

interface EnclaveBiometricInterface {
  setupAuth: (
    authType: 'biometric',
    isLong?: boolean,
    usageCount?: number,
  ) => Promise<EnclaveSession | undefined>;
  authorize: (
    authType: 'biometric',
    isLong?: boolean,
    passcode?: undefined,
    usageCount?: number,
  ) => Promise<EnclaveSession | undefined>;
  isAuthProvisioned: (authType: 'biometric') => Promise<boolean>;
  importSecret: (id: string, secret: string, token: string) => Promise<void>;
}

export interface MigrationResult {
  session: EnclaveSession;
  privateKeyAccountIds: string[];
  /** Accounts whose stored mnemonic stayed unreadable, so the Enclave holds no secret for them */
  unreadableAccountIds: string[];
}

interface ReadableAccount {
  accountId: string;
  mnemonic: string[];
}

/**
 * Why a migration stopped, in the terms the caller has to act on. Only a total failure stops one, so
 * these describe a password that opened nothing: from the passcode screen that is indistinguishable
 * from a typo, while a password taken from a platform store leaves the stored ciphertext to blame.
 */
export type MigrationErrorReason =
  | 'wrongPassword'
  | 'damagedData'
  | 'interrupted'
  | 'storageFailure';

export interface MigrationFailure {
  error: MigrationErrorReason;
}

export type MigrationOutcome = MigrationResult | MigrationFailure;

const PBKDF2_IMPORT_KEY_ARGS = [
  { name: 'PBKDF2' },
  false,
  ['deriveBits', 'deriveKey'],
] as const;

const PBKDF2_DERIVE_KEY_ARGS = {
  name: 'PBKDF2',
  iterations: 100000,
  hash: 'SHA-256',
};

const PBKDF2_DERIVE_KEY_TYPE = { name: 'AES-GCM', length: 256 };

export function checkIsMigrationFailure(outcome: MigrationOutcome): outcome is MigrationFailure {
  return 'error' in outcome;
}

/**
 * A retry resumes onto an already provisioned auth of the same type, so this code now escapes only
 * when a master key exists under a different one, which no attempt from the password screen gets past.
 */
function classifyThrownError(err: unknown): MigrationErrorReason {
  return err instanceof EnclaveError && err.code === 'auth_already_configured'
    ? 'interrupted'
    : 'storageFailure';
}

function checkIsPrivateKey(mnemonic: string[]): boolean {
  return mnemonic.length === 1 && mnemonic[0].length === PRIVATE_KEY_HEX_LENGTH;
}

/**
 * Reads every stored mnemonic, keeping each one paired with its account rather than positional, so
 * that skipping an unreadable account cannot shift a secret onto the wrong wallet.
 *
 * An account that refuses this password is passed over instead of ending the migration: its ciphertext
 * stays on disk either way, so carrying on without it costs that wallet nothing and spares every other
 * wallet in the profile.
 */
async function readMnemonics(accounts: LegacyAccountWithMnemonic[], password: string) {
  const readable: ReadableAccount[] = [];
  const unreadableAccountIds: string[] = [];

  for (const { accountId, mnemonicEncrypted } of accounts) {
    const mnemonic = await decryptLegacyMnemonic(mnemonicEncrypted, password);

    if (mnemonic) {
      readable.push({ accountId, mnemonic });
    } else {
      unreadableAccountIds.push(accountId);
    }
  }

  return { readable, unreadableAccountIds };
}

/**
 * Decrypts mnemonic using the old PBKDF2 password encryption format.
 * This is used during migration from the old auth system to the new Enclave.
 */
export async function decryptLegacyMnemonic(encrypted: string, password: string): Promise<string[] | undefined> {
  try {
    // Awaited rather than returned, so that a refusal of the oldest format is caught here and reported
    // as an unreadable mnemonic like every other one, instead of escaping as a thrown error
    if (!encrypted.includes(':')) {
      return await decryptMnemonicLegacyFormat(encrypted, password);
    }

    const [saltHex, ivHex, encryptedData] = encrypted.split(':');
    const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
    const iv = new Uint8Array(ivHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
    const keyMaterial = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(password),
      ...PBKDF2_IMPORT_KEY_ARGS,
    );
    const key = await crypto.subtle.deriveKey(
      { salt, ...PBKDF2_DERIVE_KEY_ARGS },
      keyMaterial,
      PBKDF2_DERIVE_KEY_TYPE,
      false,
      ['decrypt'],
    );
    const ctStr = atob(encryptedData);
    const ctUint8 = new Uint8Array(ctStr.match(/[\s\S]/g)!.map((ch) => ch.charCodeAt(0)));
    const plainBuffer = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ctUint8);
    const plaintext = new TextDecoder().decode(plainBuffer);

    return plaintext.split(',');
  } catch (err) {
    logDebugError('decryptLegacyMnemonic', err);
    return undefined;
  }
}

/**
 * Decrypts mnemonic using the legacy format (SHA-256 hash of password).
 */
async function decryptMnemonicLegacyFormat(encrypted: string, password: string): Promise<string[]> {
  const pwUtf8 = new TextEncoder().encode(password);
  const pwHash = await crypto.subtle.digest('SHA-256', pwUtf8);
  const iv = encrypted.slice(0, 24).match(/.{2}/g)!.map((byte) => parseInt(byte, 16));
  const alg = { name: 'AES-GCM', iv: new Uint8Array(iv) };
  const key = await crypto.subtle.importKey('raw', pwHash, alg, false, ['decrypt']);
  const ctStr = atob(encrypted.slice(24));
  const ctUint8 = new Uint8Array(ctStr.match(/[\s\S]/g)!.map((ch) => ch.charCodeAt(0)));
  const plainBuffer = await crypto.subtle.decrypt(alg, key, ctUint8);
  const plaintext = new TextDecoder().decode(plainBuffer);

  return plaintext.split(',');
}

/**
 * Performs full migration from legacy auth to Enclave using passcode.
 * This is for users who had password-based auth in the legacy system.
 */
export async function migrateToEnclave(
  legacyAccounts: LegacyAccountWithMnemonic[],
  password: string,
  isLongSession: boolean,
  enclave: EnclavePasscodeInterface,
  /** Secret reads the operation behind the password entry needs from the session it is handed */
  usageCount?: number,
): Promise<MigrationOutcome> {
  // Every step below stays inside the catch so that a throw is classified rather than surfaced raw
  try {
    const { readable, unreadableAccountIds } = await readMnemonics(legacyAccounts, password);

    // A password that opened nothing is far more likely mistyped than facing a profile that is damaged
    // end to end, and the retryable diagnosis is the only one that does not steer the user towards
    // wiping wallets that a second attempt would have migrated
    if (legacyAccounts.length > 0 && !readable.length) {
      return { error: 'wrongPassword' };
    }

    const privateKeyAccountIds = readable
      .filter(({ mnemonic }) => checkIsPrivateKey(mnemonic))
      .map(({ accountId }) => accountId);

    // Held until every mnemonic is in hand, because this is the first step that writes: reaching it with
    // nothing readable would leave an auth with no secrets under it, which is a state only a later
    // release could untangle. The early return above is what rules that out.
    // A retry after a partially imported migration finds the auth already provisioned. Setting it up again
    // would mint a master key over the secrets imported by the previous attempt, so resume instead.
    // The token it yields is discarded, since the imports below run under a session of their own, so
    // this call only has to prove that the auth is usable.
    const setupSession = await enclave.isAuthProvisioned('passcode')
      ? await enclave.authorize('passcode', false, password)
      : await enclave.setupAuth('passcode', password);
    if (!setupSession) {
      logDebugError('migrateToEnclave', 'Failed to setup enclave auth');
      return { error: 'storageFailure' };
    }

    // Scope the import session to exactly as many usages as imports instead of a 5-minute window. The
    // budget counts what is actually imported, not what is stored: an unreadable account spends nothing,
    // and over-counting would hand out a session wider than the work it covers.
    if (readable.length) {
      const importSession = await enclave.authorize('passcode', false, password, readable.length);
      if (!importSession) {
        logDebugError('migrateToEnclave', 'Failed to authorize for imports');
        return { error: 'storageFailure' };
      }

      for (const { accountId, mnemonic } of readable) {
        await enclave.importSecret(accountId, mnemonic.join(' '), importSession.token);
      }
    }

    // Issue a separate session for the caller, honouring the "remember me" preference and whatever
    // budget the operation behind the password entry declared
    const session = await enclave.authorize('passcode', isLongSession, password, usageCount);
    // Everything is committed by now and the next attempt resumes onto it, so this is the storage
    // refusing one more read rather than a dead end
    if (!session) return { error: 'storageFailure' };

    return { session, privateKeyAccountIds, unreadableAccountIds };
  } catch (err: any) {
    logDebugError('migrateToEnclave', err);
    return { error: classifyThrownError(err) };
  }
}

/**
 * Performs full migration from legacy biometric auth to Enclave biometrics.
 * The password parameter is the random password that was stored in the biometric system.
 */
export async function migrateToEnclaveBiometric(
  legacyAccounts: LegacyAccountWithMnemonic[],
  legacyPassword: string,
  enclave: EnclaveBiometricInterface,
  /** Secret reads the operation behind the password entry needs from the session it is handed */
  usageCount = 1,
): Promise<MigrationOutcome> {
  // Every step below stays inside the catch so that a throw is classified rather than surfaced raw
  try {
    const { readable, unreadableAccountIds } = await readMnemonics(legacyAccounts, legacyPassword);

    // The password came from the biometric store rather than from a keyboard, so a typo is not among
    // the explanations and there is nothing for the user to retype
    if (legacyAccounts.length > 0 && !readable.length) {
      return { error: 'damagedData' };
    }

    const privateKeyAccountIds = readable
      .filter(({ mnemonic }) => checkIsPrivateKey(mnemonic))
      .map(({ accountId }) => accountId);

    // Held until every mnemonic is in hand, because this is the first step that writes: reaching it with
    // nothing readable would leave an auth with no secrets under it, which is a state only a later
    // release could untangle. The early return above is what rules that out.
    // Budget: one usage per import plus whatever the caller needs, which receives this very session
    // and would otherwise get a token that is already spent by the time the migration returns. Imports
    // are counted over readable accounts alone, since an unreadable one never reaches the enclave.
    // A retry after a partially imported migration finds the auth already provisioned. Setting it up again
    // would mint a master key over the secrets imported by the previous attempt, so resume instead.
    const sessionUsageCount = readable.length + usageCount;
    const setupSession = await enclave.isAuthProvisioned('biometric')
      ? await enclave.authorize('biometric', false, undefined, sessionUsageCount)
      : await enclave.setupAuth('biometric', false, sessionUsageCount);
    if (!setupSession) {
      logDebugError('migrateToEnclaveBiometric', 'Failed to setup enclave biometric auth');
      return { error: 'storageFailure' };
    }

    for (const { accountId, mnemonic } of readable) {
      await enclave.importSecret(accountId, mnemonic.join(' '), setupSession.token);
    }

    return { session: { token: setupSession.token }, privateKeyAccountIds, unreadableAccountIds };
  } catch (err: any) {
    logDebugError('migrateToEnclaveBiometric', err);
    return { error: classifyThrownError(err) };
  }
}
