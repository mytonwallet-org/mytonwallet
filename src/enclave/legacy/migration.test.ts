import type { EnclaveSession } from '../../global/types';
import type { LegacyAccountWithMnemonic } from './migration';

import { PRIVATE_KEY_HEX_LENGTH } from '../../config';
import { EnclaveError } from '../errors';
import { migrateToEnclave, migrateToEnclaveBiometric } from './migration';

type PasscodeEnclave = Parameters<typeof migrateToEnclave>[3];
type BiometricEnclave = Parameters<typeof migrateToEnclaveBiometric>[2];

const PASSWORD = '123456';
const OTHER_PASSWORD = 'not-the-one';
const MNEMONIC = ['angry', 'calm', 'sad'];
const PRIVATE_KEY = 'a'.repeat(PRIVATE_KEY_HEX_LENGTH);
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

async function createPrivateKeyAccount(accountId: string, password: string): Promise<LegacyAccountWithMnemonic> {
  return { accountId, mnemonicEncrypted: await encryptLegacyMnemonic([PRIVATE_KEY], password) };
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

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet', '1-mainnet'],
      unreadableAccountIds: [],
    });
    expect(enclave.importSecret).toHaveBeenCalledTimes(2);
    expect(enclave.importSecret).toHaveBeenCalledWith('0-mainnet', MNEMONIC.join(' '), SESSION.token);
    expect(enclave.importSecret).toHaveBeenCalledWith('1-mainnet', MNEMONIC.join(' '), SESSION.token);
  });

  it('blames the password when no account at all opens', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD), await createAccount('1-mainnet', PASSWORD)];

    const outcome = await migrateToEnclave(accounts, OTHER_PASSWORD, false, createPasscodeEnclave());

    expect(outcome).toEqual({ error: { kind: 'passwordOpenedNothing' } });
  });

  // The account that happens to come first carries no special meaning, so its refusal must not end a
  // migration that the remaining accounts are ready for
  it('migrates the later accounts when the first one is unreadable', async () => {
    const accounts = [
      await createAccount('0-mainnet', OTHER_PASSWORD),
      await createAccount('1-mainnet', PASSWORD),
    ];
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['1-mainnet'],
      unreadableAccountIds: ['0-mainnet'],
    });
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
    expect(enclave.importSecret).toHaveBeenCalledWith('1-mainnet', MNEMONIC.join(' '), SESSION.token);
  });

  it('names the private key account by id when an earlier account is skipped', async () => {
    const accounts = [
      await createAccount('0-mainnet', OTHER_PASSWORD),
      await createPrivateKeyAccount('1-mainnet', PASSWORD),
    ];
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: ['1-mainnet'],
      migratedAccountIds: ['1-mainnet'],
      unreadableAccountIds: ['0-mainnet'],
    });
    expect(enclave.importSecret).toHaveBeenCalledWith('1-mainnet', PRIVATE_KEY, SESSION.token);
  });

  it('imports the readable accounts and names the one it skipped', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
      await createAccount('2-mainnet', PASSWORD),
    ];
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet', '2-mainnet'],
      unreadableAccountIds: ['1-mainnet'],
    });
    expect(enclave.importSecret).toHaveBeenCalledTimes(2);
    expect(enclave.importSecret).toHaveBeenCalledWith('0-mainnet', MNEMONIC.join(' '), SESSION.token);
    expect(enclave.importSecret).toHaveBeenCalledWith('2-mainnet', MNEMONIC.join(' '), SESSION.token);
  });

  // The session is spent one usage per import, so counting the stored accounts instead of the imported
  // ones would leave the budget short of the work and fail the last wallet
  it('budgets the import session by what it actually imports', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
      await createAccount('2-mainnet', PASSWORD),
    ];
    const enclave = createPasscodeEnclave();

    await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(enclave.authorize).toHaveBeenCalledWith('passcode', false, PASSWORD, 2);
  });

  // A lone account leaves the two causes genuinely indistinguishable, and the retryable one is the
  // only safe thing to say
  it('falls back to the password when a lone account does not open', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];

    const outcome = await migrateToEnclave(accounts, OTHER_PASSWORD, false, createPasscodeEnclave());

    expect(outcome).toEqual({ error: { kind: 'passwordOpenedNothing' } });
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
      migratedAccountIds: ['0-mainnet'],
      unreadableAccountIds: [],
    });

    // A refusal of that format has to read as a wrong password rather than as a storage fault
    await expect(migrateToEnclave(accounts, OTHER_PASSWORD, false, enclave)).resolves.toEqual({
      error: { kind: 'passwordOpenedNothing' },
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

    expect(outcome).toEqual({
      error: {
        kind: 'blocked',
        cause: { step: 'provision', name: 'auth_already_configured', message: 'Enclave: auth is already configured' },
      },
    });
  });

  it('reports a rejected import as unclassified, carrying what threw', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({
      importSecret: jest.fn(() => Promise.reject(new Error('boom'))),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      error: { kind: 'unexpected', cause: { step: 'import', name: 'Error', message: 'boom' } },
    });
  });

  // Setting the auth up a second time would mint a master key over the secrets the previous attempt
  // already imported, so a provisioned auth has to be authorized against rather than replaced
  it('resumes onto an auth left provisioned by an earlier attempt', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({ isAuthProvisioned: jest.fn(() => Promise.resolve(true)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet'],
      unreadableAccountIds: [],
    });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
  });

  // Which step stopped is the only thing support can act on, and it has to survive a failure that
  // happens after everything was already committed
  it('names the step that stopped, after the secrets were already imported', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    let issued = 0;
    const enclave = createPasscodeEnclave({
      authorize: jest.fn(() => {
        issued += 1;
        return issued === 1 ? Promise.resolve(SESSION) : Promise.reject(new Error('gone'));
      }),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
    expect(outcome).toEqual({
      error: { kind: 'unexpected', cause: { step: 'finalSession', name: 'Error', message: 'gone' } },
    });
  });

  // An error that crossed the worker bridge is rebuilt as a plain Error with the code copied and the
  // class lost, so recognising it by `instanceof` would quietly stop working
  it('recognises an enclave code on an error that lost its class', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const rebuilt = Object.assign(new Error('Enclave: auth is already configured'), {
      code: 'auth_already_configured',
    });
    const enclave = createPasscodeEnclave({ setupAuth: jest.fn(() => Promise.reject(rebuilt)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      error: {
        kind: 'blocked',
        cause: { step: 'provision', name: 'auth_already_configured', message: 'Enclave: auth is already configured' },
      },
    });
  });

  // A code the enclave minted is a diagnosis it already reached; the only question left is whether
  // trying again from this screen can clear the state it names
  it.each([
    ['auth_setup_in_progress', 'retryable'],
    ['session_expired', 'retryable'],
    ['unknown_token', 'retryable'],
    ['auth_not_configured', 'blocked'],
    ['master_key_missing', 'blocked'],
    ['secret_missing', 'blocked'],
  ] as const)('answers the %s code as %s', async (code, kind) => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({
      setupAuth: jest.fn(() => Promise.reject(new EnclaveError(code, 'Enclave: nope'))),
    });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      error: { kind, cause: { step: 'provision', name: code, message: 'Enclave: nope' } },
    });
  });

  // A `code` is a property any platform error may carry, and only the enclave's own vocabulary
  // may be presented as an enclave verdict
  it('does not read a foreign code as an enclave diagnosis', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const foreign = Object.assign(new TypeError('bridge is gone'), { code: 'UNAVAILABLE' });
    const enclave = createPasscodeEnclave({ setupAuth: jest.fn(() => Promise.reject(foreign)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({
      error: {
        kind: 'unexpected',
        cause: { step: 'provision', name: 'TypeError', message: 'bridge is gone' },
      },
    });
  });

  // Dismissing the prompt is the most common way a migration stops, and it stops nothing else
  it.each(['NotAllowedError', 'AbortError'])('reports a dismissed prompt (%s) as cancelled', async (name) => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const dismissed = Object.assign(new Error('The operation was not allowed'), { name });
    const enclave = createPasscodeEnclave({ setupAuth: jest.fn(() => Promise.reject(dismissed)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: { kind: 'canceled' } });
  });

  // The one storage cause the platform names; its numeric `DOMException.code` is not an enclave code
  it('recognises a device that ran out of room', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const full = Object.assign(new Error('The quota has been exceeded.'), { name: 'QuotaExceededError', code: 22 });
    const enclave = createPasscodeEnclave({ importSecret: jest.fn(() => Promise.reject(full)) });

    const outcome = await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: { kind: 'storageFull' } });
  });

  // The write below would mint a master key protecting no secrets at all
  it('refuses an empty account list rather than provisioning over nothing', async () => {
    const enclave = createPasscodeEnclave();

    const outcome = await migrateToEnclave([], PASSWORD, false, enclave);

    expect(outcome).toEqual({ error: { kind: 'passwordOpenedNothing' } });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
  });

  it('derives no second key when it resumes onto a provisioned auth', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createPasscodeEnclave({ isAuthProvisioned: jest.fn(() => Promise.resolve(true)) });

    await migrateToEnclave(accounts, PASSWORD, false, enclave);

    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.authorize).toHaveBeenCalledTimes(2);
  });
});

describe('migrateToEnclaveBiometric', () => {
  it('hands every decrypted mnemonic to the enclave', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD), await createAccount('1-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave();

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet', '1-mainnet'],
      unreadableAccountIds: [],
    });
    expect(enclave.importSecret).toHaveBeenCalledTimes(2);
  });

  // Nothing was typed on this path: the password comes out of the platform store, so a mismatch can
  // never be a typo and must not be reported as one
  it('reports that the stored password opened nothing, without blaming a typo', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];

    const outcome = await migrateToEnclaveBiometric(accounts, OTHER_PASSWORD, createBiometricEnclave());

    expect(outcome).toEqual({ error: { kind: 'passwordOpenedNothing' } });
  });

  it('imports the readable accounts and names the one it skipped', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
    ];
    const enclave = createBiometricEnclave();

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({
      session: { token: SESSION.token },
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet'],
      unreadableAccountIds: ['1-mainnet'],
    });
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
    expect(enclave.importSecret).toHaveBeenCalledWith('0-mainnet', MNEMONIC.join(' '), SESSION.token);
  });

  // This session covers the imports and is then handed to the caller, so a budget counted over stored
  // rather than imported accounts hands out more reads than the migration accounted for
  it('budgets the session by what it actually imports plus the caller', async () => {
    const accounts = [
      await createAccount('0-mainnet', PASSWORD),
      await createAccount('1-mainnet', OTHER_PASSWORD),
    ];
    const enclave = createBiometricEnclave();

    await migrateToEnclaveBiometric(accounts, PASSWORD, enclave, 3);

    expect(enclave.setupAuth).toHaveBeenCalledWith('biometric', false, 4);
  });

  it('reports an earlier half-finished migration as interrupted', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({
      setupAuth: jest.fn(() => Promise.reject(
        new EnclaveError('auth_already_configured', 'Enclave: auth is already configured'),
      )),
    });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({
      error: {
        kind: 'blocked',
        cause: { step: 'provision', name: 'auth_already_configured', message: 'Enclave: auth is already configured' },
      },
    });
  });

  it('refuses an empty account list rather than provisioning over nothing', async () => {
    const enclave = createBiometricEnclave();

    const outcome = await migrateToEnclaveBiometric([], PASSWORD, enclave);

    expect(outcome).toEqual({ error: { kind: 'passwordOpenedNothing' } });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
  });

  it('resumes onto an auth left provisioned by an earlier attempt', async () => {
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({ isAuthProvisioned: jest.fn(() => Promise.resolve(true)) });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({
      session: SESSION,
      privateKeyAccountIds: [],
      migratedAccountIds: ['0-mainnet'],
      unreadableAccountIds: [],
    });
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.importSecret).toHaveBeenCalledTimes(1);
  });
  // The reported failure: an extension had replaced navigator.credentials, and the TypeError that came
  // back was reported to the user as a device out of disk space
  it('reports a TypeError from the credentials API as unclassified', async () => {
    const message = 'undefined is not an object (evaluating \'e.buffer.slice\')';
    const accounts = [await createAccount('0-mainnet', PASSWORD)];
    const enclave = createBiometricEnclave({
      setupAuth: jest.fn(() => Promise.reject(new TypeError(message))),
    });

    const outcome = await migrateToEnclaveBiometric(accounts, PASSWORD, enclave);

    expect(outcome).toEqual({
      error: {
        kind: 'unexpected',
        cause: {
          step: 'provision',
          name: 'TypeError',
          message,
        },
      },
    });
  });
});
