import type { EnclaveSession } from '../../global/types';
import type { LegacyAccountWithMnemonic } from './migration';

import { EnclaveError } from '../errors';
import { migrateToEnclave, migrateToEnclaveBiometric } from './migration';

type PasscodeEnclave = Parameters<typeof migrateToEnclave>[3];
type BiometricEnclave = Parameters<typeof migrateToEnclaveBiometric>[2];

const PASSWORD = '123456';
const OTHER_PASSWORD = 'not-the-one';
const MNEMONIC = ['angry', 'calm', 'sad'];
const SALT_HEX = '000102030405060708090a0b0c0d0e0f';
const IV_HEX = '0f0e0d0c0b0a09080706050403020100';
// The colon-less format reads the IV as the leading 24 hex characters, so it is a 12-byte one
const OLDEST_FORMAT_IV_HEX = '0f0e0d0c0b0a090807060504';
const SESSION: EnclaveSession = { token: 'passcode:stub' };

function hexToBytes(hex: string) {
  return new Uint8Array(hex.match(/.{2}/g)!.map((byte) => parseInt(byte, 16)));
}

function toBase64(buffer: ArrayBuffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

/** The `salt:iv:data` ciphertext of the PBKDF2 era, which is what nearly every stored account holds */
async function encryptLegacyMnemonic(mnemonic: string[], password: string) {
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveKey'],
  );
  const key = await crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: hexToBytes(SALT_HEX), iterations: 100000, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt'],
  );
  const encrypted = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: hexToBytes(IV_HEX) },
    key,
    new TextEncoder().encode(mnemonic.join(',')),
  );

  return `${SALT_HEX}:${IV_HEX}:${toBase64(encrypted)}`;
}

/** The older colon-less ciphertext, keyed on a bare SHA-256 of the password, still present on old installs */
async function encryptOldestFormat(mnemonic: string[], password: string) {
  const passwordHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(password));
  const key = await crypto.subtle.importKey('raw', passwordHash, { name: 'AES-GCM' }, false, ['encrypt']);
  const encrypted = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: hexToBytes(OLDEST_FORMAT_IV_HEX) },
    key,
    new TextEncoder().encode(mnemonic.join(',')),
  );

  return `${OLDEST_FORMAT_IV_HEX}${toBase64(encrypted)}`;
}

async function createAccount(accountId: string, password: string): Promise<LegacyAccountWithMnemonic> {
  return { accountId, mnemonicEncrypted: await encryptLegacyMnemonic(MNEMONIC, password) };
}

function createPasscodeEnclave(overrides: Partial<PasscodeEnclave> = {}) {
  return {
    setupAuth: jest.fn(() => Promise.resolve(SESSION)),
    authorize: jest.fn(() => Promise.resolve(SESSION)),
    isAuthProvisioned: jest.fn(() => Promise.resolve(false)),
    importSecret: jest.fn(() => Promise.resolve()),
    ...overrides,
  } as unknown as PasscodeEnclave & { setupAuth: jest.Mock; importSecret: jest.Mock };
}

function createBiometricEnclave(overrides: Partial<BiometricEnclave> = {}) {
  return {
    setupAuth: jest.fn(() => Promise.resolve(SESSION)),
    authorize: jest.fn(() => Promise.resolve(SESSION)),
    isAuthProvisioned: jest.fn(() => Promise.resolve(false)),
    importSecret: jest.fn(() => Promise.resolve()),
    ...overrides,
  } as unknown as BiometricEnclave & { setupAuth: jest.Mock; importSecret: jest.Mock };
}

describe('migrateToEnclave', () => {
  it('hands every decrypted mnemonic to the enclave', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD), await createAccount('1-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ session: SESSION, privateKeyAccountIds: [] });
    expect(enclave.importSecret).toHaveBeenCalledTimes(2);
    expect(enclave.importSecret).toHaveBeenCalledWith('0-mainnet', MNEMONIC.join(' '), SESSION.token);
    expect(enclave.importSecret).toHaveBeenCalledWith('1-mainnet', MNEMONIC.join(' '), SESSION.token);
  });

  it('blames the password when no account at all opens', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD), await createAccount('1-mainnet', PASSWORD)];

    const outcome = await migrateToEnclave(accounts, OTHER_PASSWORD, false, createPasscodeEnclave());

    expect(outcome).toEqual({ error: 'wrongPassword' });
  });

  // The account that happens to come first carries no special meaning, so its refusal alone must not
  // be reported as a typo while the password is demonstrably opening the others
  it('blames the data when the first account is unreadable but a later one opens', async () => {
    const accounts = [
      await createAccount('0-mainnet', OTHER_PASSWORD),
      await createAccount('1-mainnet', PASSWORD),
    ];

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, createPasscodeEnclave());

    expect(outcome).toEqual({ error: 'damagedData' });
  });

  // Nothing may be written before every account has been read, so that an unreadable one leaves the
  // profile as it was instead of carrying an auth with no secrets under it
  it('writes nothing when a later account does not open', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
    ];
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: 'damagedData' });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).not.toHaveBeenCalled();
  });

  // A lone account leaves the two causes genuinely indistinguishable, and the retryable one is the
  // only safe thing to say
  it('falls back to the password when a lone account does not open', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];

    const outcome = await migrateToEnclave(accounts, OTHER_PASSWORD, false, createPasscodeEnclave());

    expect(outcome).toEqual({ error: 'wrongPassword' });
  });

  it('treats the oldest ciphertext format as a readable mnemonic', async () => {
    const accounts = [{
      accountId: '0-mainnet',
      mnemonicEncrypted: await encryptOldestFormat(MNEMONIC, PASSWORD),
    }];
    const enclave = createPasscodeEnclave();

    await expect(migrateToEnclave(accounts, PASSWORD, false, enclave)).resolves.toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
    });

    // A refusal of that format has to read as a wrong password rather than as a storage fault
    await expect(migrateToEnclave(accounts, OTHER_PASSWORD, false, enclave)).resolves.toEqual({
      error: 'wrongPassword',
    });
  });

  it('reports an earlier half-finished migration as interrupted', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({
      setupAuth: jest.fn(() => Promise.reject(
        new EnclaveError('auth_already_configured', 'Enclave: auth is already configured'),
      )),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: 'interrupted' });
  });

  it('reports a refused setup as a storage failure', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({ setupAuth: jest.fn(() => Promise.resolve(undefined)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: 'storageFailure' });
  });

  it('reports a refused import session as a storage failure', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({ authorize: jest.fn(() => Promise.resolve(undefined)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: 'storageFailure' });
  });

  it('reports a rejected import as a storage failure', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({
      importSecret: jest.fn(() => Promise.reject(new Error('QuotaExceededError'))),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: 'storageFailure' });
  });

  it('reports a missing final session as a storage failure', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    let issued = 0;
    const enclave = createPasscodeEnclave({
      authorize: jest.fn(() => {
        issued += 1;
        return Promise.resolve(issued === 1 ? SESSION : undefined);
      }),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
    expect(outcome).toEqual({ error: 'storageFailure' });
  });

  // Setting the auth up a second time would mint a master key over the secrets the previous attempt
  // already imported, so a provisioned auth has to be authorized against rather than replaced
  it('resumes onto an auth left provisioned by an earlier attempt', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({ isAuthProvisioned: jest.fn(() => Promise.resolve(true)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ session: SESSION, privateKeyAccountIds: [] });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
  });
});

describe('migrateToEnclaveBiometric', () => {
  it('hands every decrypted mnemonic to the enclave', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD), await createAccount('1-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave();

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({ session: SESSION, privateKeyAccountIds: [] });
    expect(enclave.importSecret).toHaveBeenCalledTimes(2);
  });

  // Nothing was typed on this path: the password comes out of the platform store, so a mismatch can
  // never be a typo and must not be reported as one
  it('never blames the password, even when the first account does not open', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];

    const outcome = await migrateToEnclaveBiometric(accounts, OTHER_PASSWORD, createBiometricEnclave());

    expect(outcome).toEqual({ error: 'damagedData' });
  });

  it('writes nothing when a later account does not open', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
    ];
    const enclave = createBiometricEnclave();

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({ error: 'damagedData' });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).not.toHaveBeenCalled();
  });

  it('reports an earlier half-finished migration as interrupted', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({
      setupAuth: jest.fn(() => Promise.reject(
        new EnclaveError('auth_already_configured', 'Enclave: auth is already configured'),
      )),
    });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({ error: 'interrupted' });
  });

  it('reports a refused setup as a storage failure', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({ setupAuth: jest.fn(() => Promise.resolve(undefined)) });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({ error: 'storageFailure' });
  });

  it('resumes onto an auth left provisioned by an earlier attempt', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({ isAuthProvisioned: jest.fn(() => Promise.resolve(true)) });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({ session: SESSION, privateKeyAccountIds: [] });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
  });
});
