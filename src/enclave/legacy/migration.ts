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
}

/**
 * Why a migration stopped, in the terms the caller has to act on. The first account doubles as the
 * password check, so its failure cannot tell a typo from unreadable data, while a failure on any
 * later account proves the password was right and leaves only the stored ciphertext to blame.
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
 * Whether any account other than the first one opens with this password. A refusal by the first
 * account alone cannot tell a typo from a blob that no longer decrypts, and one account that does
 * open settles it. The extra derivations are spent only on a path that has already failed.
 */
async function checkIsPasswordAcceptedElsewhere(accounts: LegacyAccountWithMnemonic[], password: string) {
  for (const account of accounts.slice(1)) {
    if (await decryptLegacyMnemonic(account.mnemonicEncrypted, password)) {
      return true;
    }
  }

  return false;
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
    // Validate password by decrypting the first account
    let existMnemonic: string[] | undefined;
    if (legacyAccounts.length > 0) {
      const firstAccount = legacyAccounts[0];
      existMnemonic = await decryptLegacyMnemonic(firstAccount.mnemonicEncrypted, password);

      // The first account alone cannot separate a typo from unreadable data, so the rest get asked
      if (!existMnemonic) {
        return {
          error: await checkIsPasswordAcceptedElsewhere(legacyAccounts, password)
            ? 'damagedData'
            : 'wrongPassword',
        };
      }
    }

    // Decrypt all mnemonics first to ensure all-or-nothing migration
    const mnemonics: string[][] = [];
    const privateKeyAccountIds: string[] = [];

    for (let i = 0; i < legacyAccounts.length; i++) {
      const mnemonic = i === 0
        ? existMnemonic! // Reuse already decrypted mnemonic
        : await decryptLegacyMnemonic(legacyAccounts[i].mnemonicEncrypted, password);

      // The same password just opened the first account, so the password is not what is wrong here
      if (!mnemonic) {
        logDebugError('migrateToEnclave', `Failed to decrypt mnemonic for account ${legacyAccounts[i].accountId}`);
        return { error: 'damagedData' };
      }

      if (checkIsPrivateKey(mnemonic)) {
        privateKeyAccountIds.push(legacyAccounts[i].accountId);
      }

      mnemonics.push(mnemonic);
    }

    // Held until every mnemonic is in hand, because this is the first step that writes: an account that
    // turns out to be unreadable then leaves the profile untouched rather than carrying an auth with no
    // secrets under it, which is a state only a later release could untangle.
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

    // Scope the import session to exactly as many usages as imports instead of a 5-minute window
    if (legacyAccounts.length > 0) {
      const importSession = await enclave.authorize('passcode', false, password, legacyAccounts.length);
      if (!importSession) {
        logDebugError('migrateToEnclave', 'Failed to authorize for imports');
        return { error: 'storageFailure' };
      }

      for (let i = 0; i < legacyAccounts.length; i++) {
        await enclave.importSecret(legacyAccounts[i].accountId, mnemonics[i].join(' '), importSession.token);
      }
    }

    // Issue a separate session for the caller, honouring the "remember me" preference and whatever
    // budget the operation behind the password entry declared
    const session = await enclave.authorize('passcode', isLongSession, password, usageCount);
    // Everything is committed by now and the next attempt resumes onto it, so this is the storage
    // refusing one more read rather than a dead end
    if (!session) return { error: 'storageFailure' };

    return { session, privateKeyAccountIds };
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
    // Validate password by decrypting the first account (if any)
    let existMnemonic: string[] | undefined;
    if (legacyAccounts.length > 0) {
      const firstAccount = legacyAccounts[0];
      existMnemonic = await decryptLegacyMnemonic(firstAccount.mnemonicEncrypted, legacyPassword);

      // The password came from the biometric store rather than from a keyboard, so a typo is not
      // among the explanations and there is nothing for the user to retype
      if (!existMnemonic) {
        logDebugError('migrateToEnclaveBiometric', 'Failed to decrypt mnemonic with legacy password');
        return { error: 'damagedData' };
      }
    }

    // Decrypt all mnemonics first to ensure all-or-nothing migration
    const mnemonics: string[][] = [];
    const privateKeyAccountIds: string[] = [];

    for (let i = 0; i < legacyAccounts.length; i++) {
      const mnemonic = i === 0
        ? existMnemonic! // Reuse already decrypted mnemonic
        : await decryptLegacyMnemonic(legacyAccounts[i].mnemonicEncrypted, legacyPassword);

      if (!mnemonic) {
        logDebugError(
          'migrateToEnclaveBiometric',
          `Failed to decrypt mnemonic for account ${legacyAccounts[i].accountId}`,
        );
        return { error: 'damagedData' };
      }

      if (checkIsPrivateKey(mnemonic)) {
        privateKeyAccountIds.push(legacyAccounts[i].accountId);
      }

      mnemonics.push(mnemonic);
    }

    // Held until every mnemonic is in hand, because this is the first step that writes: an account that
    // turns out to be unreadable then leaves the profile untouched rather than carrying an auth with no
    // secrets under it, which is a state only a later release could untangle.
    // Budget: one usage per import plus whatever the caller needs, which receives this very session
    // and would otherwise get a token that is already spent by the time the migration returns.
    // A retry after a partially imported migration finds the auth already provisioned. Setting it up again
    // would mint a master key over the secrets imported by the previous attempt, so resume instead.
    const sessionUsageCount = legacyAccounts.length + usageCount;
    const setupSession = await enclave.isAuthProvisioned('biometric')
      ? await enclave.authorize('biometric', false, undefined, sessionUsageCount)
      : await enclave.setupAuth('biometric', false, sessionUsageCount);
    if (!setupSession) {
      logDebugError('migrateToEnclaveBiometric', 'Failed to setup enclave biometric auth');
      return { error: 'storageFailure' };
    }

    // Import all mnemonics only after successful decryption of all accounts
    for (let i = 0; i < legacyAccounts.length; i++) {
      await enclave.importSecret(legacyAccounts[i].accountId, mnemonics[i].join(' '), setupSession.token);
    }

    return { session: { token: setupSession.token }, privateKeyAccountIds };
  } catch (err: any) {
    logDebugError('migrateToEnclaveBiometric', err);
    return { error: classifyThrownError(err) };
  }
}
