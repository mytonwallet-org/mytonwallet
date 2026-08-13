import type { EnclaveSession } from '../../global/types';
import type { EnclaveErrorCode } from '../errors';

import { PRIVATE_KEY_HEX_LENGTH } from '../../config';
import { logDebugError } from '../../util/logs';

export interface LegacyAccountWithMnemonic {
  accountId: string;
  mnemonicEncrypted: string;
}

interface EnclavePasscodeInterface {
  setupAuth: (authType: 'passcode', passcode: string) => Promise<EnclaveSession>;
  authorize: (
    authType: 'passcode',
    isLong: boolean,
    passcode: string,
    usageCount?: number,
  ) => Promise<EnclaveSession>;
  isAuthProvisioned: (authType: 'passcode') => Promise<boolean>;
  importSecret: (id: string, secret: string, token: string) => Promise<void>;
}

interface EnclaveBiometricInterface {
  setupAuth: (
    authType: 'biometric',
    isLong?: boolean,
    usageCount?: number,
  ) => Promise<EnclaveSession>;
  authorize: (
    authType: 'biometric',
    isLong?: boolean,
    passcode?: undefined,
    usageCount?: number,
  ) => Promise<EnclaveSession>;
  isAuthProvisioned: (authType: 'biometric') => Promise<boolean>;
  importSecret: (id: string, secret: string, token: string) => Promise<void>;
}

export interface MigrationResult {
  session: EnclaveSession;
  privateKeyAccountIds: string[];
  /** Accounts whose secret reached the Enclave, private keys included, so the ciphertext is no longer the only copy */
  migratedAccountIds: string[];
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
export type MigrationFailureReason =
  /** Established: every stored ciphertext refused this password. */
  | { kind: 'passwordOpenedNothing' }
  /** Established: a prompt the migration cannot proceed without was dismissed. */
  | { kind: 'canceled' }
  /** Established: the device refused a write for want of room, the one storage cause it names. */
  | { kind: 'storageFull' }
  /** Established by name, and a second attempt from this screen can clear it. */
  | { kind: 'retryable'; cause: MigrationErrorCause }
  /** Established by name, and no attempt from this screen gets past it. */
  | { kind: 'blocked'; cause: MigrationErrorCause }
  /** Not established, and saying so is the point. */
  | { kind: 'unexpected'; cause: MigrationErrorCause };

/** Structured-cloneable on purpose: the migration is reached across the worker bridge */
export interface MigrationErrorCause {
  step: MigrationStep;
  /** The `EnclaveErrorCode` where the enclave named the failure, otherwise the platform error name */
  name: string;
  message: string;
}

/**
 * Where a migration was when it stopped. The last two lie outside `migrateToEnclave*`, in the handler
 * that fetches the legacy password and adds the second auth method afterwards - those calls stop a
 * migration just as squarely, and a stopped migration has to name its step wherever it happened.
 */
export type MigrationStep =
  | 'read' | 'provision' | 'authorize' | 'import' | 'finalSession' | 'legacyPassword' | 'secondAuth';

export interface MigrationFailure {
  error: MigrationFailureReason;
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

const ENCLAVE_ERROR_CODES: ReadonlySet<string> = new Set<EnclaveErrorCode>([
  'auth_already_configured',
  'auth_setup_in_progress',
  'auth_not_configured',
  'session_expired',
  'unknown_token',
  'master_key_missing',
  'secret_missing',
]);

/** The names a dismissed platform prompt arrives under, whichever API raised it */
const CANCELLATION_ERROR_NAMES: ReadonlySet<string> = new Set(['NotAllowedError', 'AbortError']);

/**
 * Sorts a throw by what it establishes. A cause the thrower named is answered on that name; only a
 * cause nobody can name from the evidence is carried out as unclassified, which is what the screen
 * then says out loud. Guessing in either direction misleads: inventing a verdict sends the user after
 * a problem they do not have, and discarding a name the enclave or the platform already supplied
 * withholds the one instruction that would help.
 */
export function describeThrownError(err: unknown, step: MigrationStep): MigrationFailureReason {
  const cause = buildErrorCause(err, step);
  const code = getEnclaveErrorCode(err);

  if (code) {
    return describeEnclaveError(code, cause);
  }

  if (CANCELLATION_ERROR_NAMES.has(cause.name)) {
    return { kind: 'canceled' };
  }

  // The numeric `DOMException.code` is not an `EnclaveErrorCode`, so the name is what carries this
  if (cause.name === 'QuotaExceededError') {
    return { kind: 'storageFull' };
  }

  return { kind: 'unexpected', cause };
}

/**
 * Exhaustive on purpose: a code added to `EnclaveErrorCode` stops compiling here until someone says
 * whether a second attempt from this screen can clear it.
 */
function describeEnclaveError(code: EnclaveErrorCode, cause: MigrationErrorCause): MigrationFailureReason {
  switch (code) {
    case 'auth_setup_in_progress':
    case 'session_expired':
    case 'unknown_token':
      return { kind: 'retryable', cause };

    case 'auth_already_configured':
    case 'auth_not_configured':
    case 'master_key_missing':
    case 'secret_missing':
      return { kind: 'blocked', cause };
  }
}

function buildErrorCause(err: unknown, step: MigrationStep): MigrationErrorCause {
  const error = err as { name?: unknown; message?: unknown } | undefined;

  return {
    step,
    name: getEnclaveErrorCode(err) ?? (typeof error?.name === 'string' ? error.name : 'Error'),
    message: typeof error?.message === 'string' ? error.message : String(err),
  };
}

/**
 * Read off the property rather than through `instanceof`: an error that crossed the worker bridge is
 * rebuilt as a plain `Error` with the code copied and the class lost, and an enclave that ever answers
 * from the other side would silently stop matching. Membership is what separates a code the enclave
 * minted from a `code` any platform error may carry - an `ENOENT` or an `UNAVAILABLE` from a native
 * bridge would otherwise reach support looking like a verdict the enclave had reached.
 */
function getEnclaveErrorCode(err: unknown): EnclaveErrorCode | undefined {
  const code = (err as { code?: unknown } | undefined)?.code;

  return typeof code === 'string' && ENCLAVE_ERROR_CODES.has(code) ? code as EnclaveErrorCode : undefined;
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
  // Every step below stays inside the catch so that a throw is described rather than surfaced raw
  let step: MigrationStep = 'read';

  try {
    const { readable, unreadableAccountIds } = await readMnemonics(legacyAccounts, password);

    // A password that opened nothing is far more likely mistyped than facing a profile that is damaged
    // end to end, and the retryable diagnosis is the only one that does not steer the user towards
    // wiping wallets that a second attempt would have migrated. Nothing readable also covers an empty
    // account list, which must not reach the write below: it would mint a master key over no secrets
    // at all, a state only a later release could untangle.
    if (!readable.length) {
      return { error: { kind: 'passwordOpenedNothing' } };
    }

    const privateKeyAccountIds = readable
      .filter(({ mnemonic }) => checkIsPrivateKey(mnemonic))
      .map(({ accountId }) => accountId);

    // Held until every mnemonic is in hand, because this is the first step that writes.
    // A retry after a partially imported migration finds the auth already provisioned. Setting it up again
    // would mint a master key over the secrets imported by the previous attempt, so resume instead.
    // Resuming already derives a key from the password, so that session is the one the imports run
    // under; deriving a second would cost another PBKDF2 pass over 100 000 iterations for nothing.
    step = 'provision';
    const resumedSession = await enclave.isAuthProvisioned('passcode')
      ? await enclave.authorize('passcode', false, password, readable.length)
      : undefined;

    if (!resumedSession) {
      await enclave.setupAuth('passcode', password);
    }

    // Scope the import session to exactly as many usages as imports instead of a 5-minute window. The
    // budget counts what is actually imported, not what is stored: an unreadable account spends nothing,
    // and over-counting would hand out a session wider than the work it covers.
    step = 'authorize';
    const importSession = resumedSession ?? await enclave.authorize('passcode', false, password, readable.length);

    step = 'import';
    for (const { accountId, mnemonic } of readable) {
      await enclave.importSecret(accountId, mnemonic.join(' '), importSession.token);
    }

    // Issue a separate session for the caller, honouring the "remember me" preference and whatever
    // budget the operation behind the password entry declared
    step = 'finalSession';
    const session = await enclave.authorize('passcode', isLongSession, password, usageCount);

    return {
      session,
      privateKeyAccountIds,
      migratedAccountIds: readable.map(({ accountId }) => accountId),
      unreadableAccountIds,
    };
  } catch (err: any) {
    logDebugError('migrateToEnclave', err);
    return { error: describeThrownError(err, step) };
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
  // Every step below stays inside the catch so that a throw is described rather than surfaced raw
  let step: MigrationStep = 'read';

  try {
    const { readable, unreadableAccountIds } = await readMnemonics(legacyAccounts, legacyPassword);

    // The password came from the biometric store rather than from a keyboard, so a typo is not among
    // the explanations and there is nothing for the user to retype. Which of the two things to say
    // is the presenter's to decide, since only it knows where the password came from. Nothing readable
    // also covers an empty account list, which must not reach the write below: it would mint a master
    // key over no secrets at all, a state only a later release could untangle.
    if (!readable.length) {
      return { error: { kind: 'passwordOpenedNothing' } };
    }

    const privateKeyAccountIds = readable
      .filter(({ mnemonic }) => checkIsPrivateKey(mnemonic))
      .map(({ accountId }) => accountId);

    // Held until every mnemonic is in hand, because this is the first step that writes.
    // Budget: one usage per import plus whatever the caller needs, which receives this very session
    // and would otherwise get a token that is already spent by the time the migration returns. Imports
    // are counted over readable accounts alone, since an unreadable one never reaches the enclave.
    // A retry after a partially imported migration finds the auth already provisioned. Setting it up again
    // would mint a master key over the secrets imported by the previous attempt, so resume instead.
    const sessionUsageCount = readable.length + usageCount;
    step = 'provision';
    const setupSession = await (await enclave.isAuthProvisioned('biometric')
      ? enclave.authorize('biometric', false, undefined, sessionUsageCount)
      : enclave.setupAuth('biometric', false, sessionUsageCount));

    step = 'import';
    for (const { accountId, mnemonic } of readable) {
      await enclave.importSecret(accountId, mnemonic.join(' '), setupSession.token);
    }

    return {
      session: { token: setupSession.token },
      privateKeyAccountIds,
      migratedAccountIds: readable.map(({ accountId }) => accountId),
      unreadableAccountIds,
    };
  } catch (err: any) {
    logDebugError('migrateToEnclaveBiometric', err);
    return { error: describeThrownError(err, step) };
  }
}
