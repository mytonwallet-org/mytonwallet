import type { AuthType, EnclaveSession } from '../global/types';
import type { AnyAuth, AnyBiometricAuthClass, SimpleStorage } from './types';

import { randomBytes } from '../util/random';
import safeExec, { safeExecAsync } from '../util/safeExec';
import { deriveKeyFromRandom } from './auth/deriveKey';
import { decrypt, encrypt } from './aes';
import { EnclaveError } from './errors';

import PasscodeAuth from './auth/PasscodeAuth';

const MASTER_KEY_STORAGE_KEY_PREFIX = 'encryptedMasterKey:auth-';
const SECRET_STORAGE_KEY_PREFIX = 'encryptedSecret#';

let isSettingUpAuth = false;

let storage: SimpleStorage;
let BiometricAuthClass: AnyBiometricAuthClass;
/**
 * At most one instance per auth type: a token carries only its type, so `resolveAuth` has nothing to
 * tell two same-type instances apart and would hand the caller's token to the wrong one, whose own
 * session does not know it. Keyed by type the second instance cannot exist, and since the registry is
 * never rebound, no writer can drop what another one registered while it was awaiting.
 */
const auths = new Map<AuthType, AnyAuth>();

let resolveBiometricAuthClass: NoneToVoidFunction | undefined;
const biometricAuthClassReady = new Promise<void>((resolve) => {
  resolveBiometricAuthClass = resolve;
});

export function setupStorage(_storage: SimpleStorage) {
  storage = _storage;
  // Auth instances are bound to the storage they were built against, so they cannot outlive it
  auths.clear();

  return Promise.resolve(); // Support async providers
}

export function setupBiometricAuthClass(_BiometricAuthClass: AnyBiometricAuthClass) {
  BiometricAuthClass = _BiometricAuthClass;
  resolveBiometricAuthClass?.();

  return Promise.resolve(); // Support async providers
}

export async function setAuths(authTypes?: AuthType[]) {
  // Already set up or nothing to set up
  if (auths.size || !authTypes?.length) return;

  if (authTypes.includes('biometric')) {
    await biometricAuthClassReady;
  }

  for (const authType of authTypes) {
    ensureAuth(authType);
  }
}

export function setupAuth(authType: 'passcode', passcode: string): Promise<EnclaveSession>;
export function setupAuth(
  authType: 'biometric', isLong?: boolean, usageCount?: number,
): Promise<EnclaveSession>;
export async function setupAuth(
  authType: AuthType, passcodeOrIsLong?: string | boolean, usageCount?: number,
) {
  // Raised before the first await, so a second caller is turned away while the storage still looks
  // empty to it - the check below alone would let both through and both would write a master key
  if (isSettingUpAuth) {
    throw new EnclaveError('auth_setup_in_progress', 'Enclave: an auth setup is already in progress');
  }

  isSettingUpAuth = true;

  try {
    await assertNoMasterKey();

    const auth = initAuth(authType);
    const session = auth.type === 'passcode'
      ? await auth.setup(passcodeOrIsLong as string)
      : await auth.setup(undefined, passcodeOrIsLong as boolean, usageCount);
    const encryptKey = auth.getKey(session.token, true);

    await setupMasterKey(auth, encryptKey, randomBytes(32));

    // The storage held no master key, so whatever was registered before could not unlock anything
    auths.clear();
    auths.set(auth.type, auth);

    return session;
  } finally {
    isSettingUpAuth = false;
  }
}

export function migrateAuth(
  currentToken: string,
  newAuthType: 'passcode',
  passcode: string,
  shouldReplace?: boolean,
): Promise<EnclaveSession | undefined>;
export function migrateAuth(
  currentToken: string,
  newAuthType: 'biometric',
  passcode?: undefined,
  shouldReplace?: boolean,
  usageCount?: number,
): Promise<EnclaveSession | undefined>;
export async function migrateAuth(
  currentToken: string,
  newAuthType: AuthType,
  passcode?: string,
  shouldReplace = false,
  /**
   * Secret reads the caller needs from the session it gets back, which is a brand new one. Biometric
   * only - a passcode setup derives its session from the passcode alone and counts no further reads.
   */
  usageCount?: number,
): Promise<EnclaveSession | undefined> {
  const currentAuth = resolveAuth(currentToken);
  const currentKek = currentAuth.getKey(currentToken);
  const masterKeyAb = await retrieveMasterKeyAb(currentAuth, currentKek);

  const newAuth = initAuth(newAuthType);
  const newSession = newAuth.type === 'passcode'
    ? await newAuth.setup(passcode!)
    : await newAuth.setup(undefined, false, usageCount);
  const newKek = newAuth.getKey(newSession.token, true);

  await setupMasterKey(newAuth, newKek, masterKeyAb);

  if (shouldReplace) {
    if (currentAuth.type !== newAuth.type) {
      await storage.removeItem(buildMasterKeyStorageKeyPrefix(currentAuth));
      await currentAuth.destroy();
      auths.delete(currentAuth.type);
    } else {
      currentAuth.clearSession();
    }
  }

  // Auths of other types stay as they are, e.g. biometric survives a passcode change
  auths.set(newAuth.type, newAuth);

  return newSession;
}

function initAuth(authType: AuthType) {
  const AuthClass = authType === 'passcode' ? PasscodeAuth : BiometricAuthClass;

  return new AuthClass(storage);
}

export function getTokenAuthType(token: string): AuthType {
  return token.split(':')[0] as AuthType;
}

function getAuths() {
  if (!auths.size) throw new EnclaveError('auth_not_configured', 'Enclave: no auth is configured');

  return auths;
}

function resolveAuth(token: string) {
  const authType = getTokenAuthType(token);
  // The auth type comes out of the token, so it stays out of a message that ends up in logs
  const auth = getAuths().get(authType);
  if (!auth) throw new EnclaveError('unknown_token', 'Enclave: the token matches no configured auth');

  return auth;
}

export function authorize(
  authType: 'passcode', isLong: boolean, passcode: string, usageCount?: number,
): Promise<EnclaveSession | undefined>;
export function authorize(
  authType: 'biometric', isLong?: boolean, passcode?: undefined, usageCount?: number,
): Promise<EnclaveSession | undefined>;
export async function authorize(
  authType: AuthType, isLong?: boolean, passcode?: string, usageCount?: number,
) {
  return safeExecAsync(() => authorizeOrThrow(authType, isLong, passcode, usageCount), { shouldIgnoreError: true });
}

/**
 * The same authorization, with the reason it failed left intact. `authorize` answers the unlock
 * screens, which read `undefined` as a refused passcode and have nothing else to say; the migration
 * has to tell the user what happened, and a missing salt, an unreadable store and a wrong verifier
 * are not the same answer.
 */
export async function authorizeOrThrow(
  authType: AuthType, isLong?: boolean, passcode?: string, usageCount?: number,
) {
  const auth = await restoreAuth(authType);
  if (!auth) throw new EnclaveError('auth_not_configured', `Enclave: no ${authType} auth is configured`);

  return auth.type === 'passcode'
    ? auth.authorize(isLong!, passcode!, usageCount)
    : auth.authorize(isLong, undefined, usageCount);
}

/**
 * Ends a usage-counted session that its operation is done with, so the reads it asked for and did
 * not take stop being available. A token that names no live session, or names one that expires by
 * time, is left alone, which is why an operation may call this without knowing which kind it holds.
 */
export function releaseSession(token: string) {
  return safeExec(() => resolveAuth(token).releaseSession(token), { shouldIgnoreError: true });
}

/** Whether an auth method can already unlock the master key, i.e. whether `setupAuth` has run for it. */
export async function isAuthProvisioned(authType: AuthType) {
  return Boolean(await storage.getItem(`${MASTER_KEY_STORAGE_KEY_PREFIX}${authType}`));
}

/**
 * Whether any auth method at all can unlock the master key. There is one master key per storage, not
 * one per auth type, so this - and not the presence of a given type - is what decides whether
 * `setupAuth` has anything to mint a new one over.
 */
export async function hasProvisionedAuth() {
  const keys = await storage.getAllKeys();

  return keys.some((key) => key.startsWith(MASTER_KEY_STORAGE_KEY_PREFIX));
}

/**
 * Whether anything is sealed under the master key. A configured auth with no secrets beneath it
 * protects nothing, which is what separates leftovers of an unfinished setup from a real wallet.
 */
export async function hasStoredSecrets() {
  const keys = await storage.getAllKeys();

  return keys.some((key) => key.startsWith(SECRET_STORAGE_KEY_PREFIX));
}

/**
 * Storage outlives the in-memory auth instances: `setAuths` builds them from `authTypes`, which is UI
 * state and can be absent while the Enclave is configured on disk - after an interrupted migration, or a
 * lost cache. Authorizing has to work in exactly that state, so it rebuilds the instance and registers
 * it, which is what the later `resolveAuth` of the issued token looks up.
 */
async function restoreAuth(authType: AuthType) {
  const existing = auths.get(authType);
  if (existing) return existing;

  if (!await isAuthProvisioned(authType)) return undefined;

  if (authType === 'biometric') {
    await biometricAuthClassReady;
  }

  return ensureAuth(authType);
}

/**
 * Registration happens here and nowhere else, in one synchronous step, so two callers that both got
 * past their awaits still end up sharing a single instance instead of minting a token each against a
 * session the other one cannot see.
 */
function ensureAuth(authType: AuthType) {
  const existing = auths.get(authType);
  if (existing) return existing;

  const auth = initAuth(authType);
  auths.set(authType, auth);

  return auth;
}

/**
 * TODO [Enclave step 2]
 *
 * Sign data without exposing the secret outside the Enclave.
 *
 * Currently, signing is done by exporting the mnemonic via `exportSecret()`, deriving the private key
 * in the chain SDK (TON/Tron/Solana), and signing there. This means the secret temporarily enters
 * the JS context (Worker/WebView), which is the main security limitation of the current architecture.
 *
 * This function should replace that flow: the Enclave derives the private key internally
 * and returns only the signature. The secret never leaves the Enclave boundary.
 *
 * Implementation requires:
 * - Chain-aware key derivation inside the Enclave (ed25519 for TON/Solana, secp256k1 for Tron)
 * - A way to specify the chain and derivation path per account
 * - Native implementation for Android/iOS to keep secrets in Keystore/Secure Enclave
 */
// eslint-disable-next-line @typescript-eslint/require-await
export async function sign(id: string, data: Buffer, token: string) {
  // const secret = await retrieveSecret(id, token);
  throw new Error('Enclave: sign() is not yet implemented');
}

async function setupMasterKey(auth: AnyAuth, kek: CryptoKey, masterKeyAb: ArrayBuffer) {
  const encryptedMasterKey = await encrypt(masterKeyAb, kek);
  await storage.setItem(buildMasterKeyStorageKeyPrefix(auth), encryptedMasterKey);
}

async function retrieveMasterKey(auth: AnyAuth, token: string) {
  const kek = auth.getKey(token);
  const masterKeyAb = await retrieveMasterKeyAb(auth, kek);

  return deriveKeyFromRandom(masterKeyAb);
}

async function retrieveMasterKeyAb(auth: AnyAuth, kek: CryptoKey) {
  const encryptedMasterKey = await storage.getItem(buildMasterKeyStorageKeyPrefix(auth));
  if (!encryptedMasterKey) {
    throw new EnclaveError('master_key_missing', `Enclave: no master key for the ${auth.type} auth`);
  }

  return decrypt(encryptedMasterKey, kek, true);
}

function buildMasterKeyStorageKeyPrefix(auth: AnyAuth) {
  return `${MASTER_KEY_STORAGE_KEY_PREFIX}${auth.type}` as const;
}

/**
 * A master key is minted from fresh randomness, so setting up an auth over a storage that already
 * holds one leaves every secret sealed under a key nothing can reproduce. Adding a second auth method
 * to a configured Enclave is `migrateAuth`; getting here means the caller mistook one for the other.
 */
async function assertNoMasterKey() {
  if (await hasProvisionedAuth()) {
    throw new EnclaveError('auth_already_configured', 'Enclave: auth is already configured');
  }
}

export async function importSecret(id: string, secret: string, token: string) {
  const auth = resolveAuth(token);
  const masterKey = await retrieveMasterKey(auth, token);
  const encryptedSecret = await encrypt(secret, masterKey);

  await storeEncryptedSecret(id, encryptedSecret);
}

export async function exportSecret(id: string, token: string) {
  const secret = await retrieveSecret(id, token);

  return secret;
}

export async function duplicateSecret(fromId: string, toId: string) {
  const encryptedSecret = await loadEncryptedSecret(fromId);

  await storeEncryptedSecret(toId, encryptedSecret);
}

export function removeSecret(id: string) {
  return storage.removeItem(`${SECRET_STORAGE_KEY_PREFIX}${id}`);
}

export async function removeAuth(authType: AuthType) {
  const auth = auths.get(authType);
  if (!auth) return;

  await auth.destroy();
  await storage.removeItem(buildMasterKeyStorageKeyPrefix(auth));

  auths.delete(authType);
}

/** Resets the entire enclave, destroying all auth methods and secrets */
export async function reset() {
  await Promise.all([...auths.values()].map((auth) => auth.destroy()));
  auths.clear();

  await storage.clear();
}

async function retrieveSecret(id: string, token: string) {
  const auth = resolveAuth(token);
  const [encryptedSecret, masterKey] = await Promise.all([loadEncryptedSecret(id), retrieveMasterKey(auth, token)]);

  return decrypt(encryptedSecret, masterKey);
}

function storeEncryptedSecret(id: string, encryptedSecret: string) {
  return storage.setItem(`${SECRET_STORAGE_KEY_PREFIX}${id}`, encryptedSecret);
}

async function loadEncryptedSecret(id: string) {
  const encryptedSecret = await storage.getItem(`${SECRET_STORAGE_KEY_PREFIX}${id}`);
  if (!encryptedSecret) throw new EnclaveError('secret_missing', `Enclave: no secret for ${id}`);

  return encryptedSecret;
}
