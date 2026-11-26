import type { SimpleStorage, StorageKey, StorageValue } from '../types';

import { bufferFromBase64, bufferFromString, hexFromArrayBuffer } from '../../util/casting';

import PasscodeAuth from './PasscodeAuth';

const LEGACY_ITERATIONS = 100000;
const CURRENT_ITERATIONS = 600000;
const PLAINTEXT = new Uint8Array([1, 2, 3, 4]);

function createMemoryStorage(): SimpleStorage {
  const map = new Map<string, StorageValue>();

  return {
    getItem: (name) => Promise.resolve(map.get(name)),
    setItem: (name, value) => {
      map.set(name, value);
      return Promise.resolve();
    },
    removeItem: (name) => {
      map.delete(name);
      return Promise.resolve();
    },
    clear: () => {
      map.clear();
      return Promise.resolve();
    },
    getAllKeys: () => Promise.resolve([...map.keys()] as StorageKey[]),
  };
}

function getKeyError(auth: PasscodeAuth, token: string) {
  try {
    auth.getKey(token);
  } catch (err: any) {
    return err;
  }

  throw new Error('getKey was expected to throw');
}

async function setupPasscode(storage: SimpleStorage, passcode: string) {
  await new PasscodeAuth(storage).setup(passcode);
}

async function deriveVerifierHex(passcode: string, saltBase64: string, iterations: number) {
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', iterations, salt: bufferFromBase64(saltBase64) },
    await importPasscode(passcode),
    256,
  );

  return hexFromArrayBuffer(bits);
}

async function deriveKek(passcode: string, saltBase64: string, iterations: number) {
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', iterations, salt: bufferFromBase64(saltBase64) },
    await importPasscode(passcode),
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

async function importPasscode(passcode: string) {
  return crypto.subtle.importKey(
    'raw', bufferFromString(passcode), { name: 'PBKDF2' }, false, ['deriveKey', 'deriveBits'],
  );
}

// Proves two keys are the same key without exporting either: what one seals, only its twin opens
async function expectSameKey(sealingKey: CryptoKey, openingKey: CryptoKey) {
  const iv = new Uint8Array(12);
  const sealed = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, sealingKey, PLAINTEXT);
  const opened = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, openingKey, sealed);

  expect([...new Uint8Array(opened)]).toEqual([...PLAINTEXT]);
}

async function readSalts(storage: SimpleStorage) {
  const [salt, verifierSalt] = await Promise.all([
    storage.getItem('PasscodeAuth:salt'),
    storage.getItem('PasscodeAuth:verifierSalt'),
  ]);

  return { salt: salt!, verifierSalt: verifierSalt! };
}

describe('PasscodeAuth', () => {
  describe('iteration count', () => {
    // A build that knows no recorded count compares the record to the bare verifier
    it('sets up a passcode in the record a build without the count can open', async () => {
      const storage = createMemoryStorage();
      const auth = new PasscodeAuth(storage);
      const { token } = await auth.setup('123456');
      const { salt, verifierSalt } = await readSalts(storage);

      expect(await storage.getItem('PasscodeAuth:verifier'))
        .toBe(await deriveVerifierHex('123456', verifierSalt, LEGACY_ITERATIONS));
      await expectSameKey(await deriveKek('123456', salt, LEGACY_ITERATIONS), auth.getKey(token));
    });

    it('opens a passcode whose record names the current count', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');
      const { salt, verifierSalt } = await readSalts(storage);
      const verifierHex = await deriveVerifierHex('123456', verifierSalt, CURRENT_ITERATIONS);
      await storage.setItem('PasscodeAuth:verifier', `${CURRENT_ITERATIONS}:${verifierHex}`);

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(false, '123456');

      await expectSameKey(await deriveKek('123456', salt, CURRENT_ITERATIONS), auth.getKey(token));
      await expect(auth.authorize(false, '000000')).rejects.toThrow('Invalid passcode');
    });

    it('opens a passcode whose record names no count', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');
      const { salt, verifierSalt } = await readSalts(storage);
      await storage.setItem(
        'PasscodeAuth:verifier',
        await deriveVerifierHex('123456', verifierSalt, LEGACY_ITERATIONS),
      );

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(false, '123456');

      await expectSameKey(await deriveKek('123456', salt, LEGACY_ITERATIONS), auth.getKey(token));
      await expect(auth.authorize(false, '000000')).rejects.toThrow('Invalid passcode');
    });

    it.each([
      '1', '99999', '1e5', '600001', '1000000000', 'abc', '',
    ])('refuses a recorded count of "%s"', async (count) => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');
      const { verifierSalt } = await readSalts(storage);
      const verifierHex = await deriveVerifierHex('123456', verifierSalt, LEGACY_ITERATIONS);
      await storage.setItem('PasscodeAuth:verifier', `${count}:${verifierHex}`);

      const error = await new PasscodeAuth(storage).authorize(false, '123456').catch((err) => err);

      expect(error.code).toBe('auth_not_configured');
    });

    // A cut-off verifier matches no passcode, so calling the typed one wrong would ask for it forever
    it.each([0, 63])('refuses a counted record that holds %i of the 64 verifier characters', async (length) => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');
      const { verifierSalt } = await readSalts(storage);
      const verifierHex = await deriveVerifierHex('123456', verifierSalt, CURRENT_ITERATIONS);
      await storage.setItem('PasscodeAuth:verifier', `${CURRENT_ITERATIONS}:${verifierHex.slice(0, length)}`);

      const error = await new PasscodeAuth(storage).authorize(false, '123456').catch((err) => err);

      expect(error.code).toBe('auth_not_configured');
    });
  });

  it('authorizes with the correct passcode', async () => {
    const storage = createMemoryStorage();
    await setupPasscode(storage, '123456');

    const auth = new PasscodeAuth(storage);
    const session = await auth.authorize(false, '123456');

    expect(session.token).toMatch(/^passcode:/);
  });

  it('rejects a wrong passcode', async () => {
    const storage = createMemoryStorage();
    await setupPasscode(storage, '123456');

    const auth = new PasscodeAuth(storage);
    await expect(auth.authorize(false, '000000')).rejects.toThrow('Invalid passcode');
  });

  it('does not store the passcode verifier under the session-key salt', async () => {
    const storage = createMemoryStorage();
    await setupPasscode(storage, '123456');

    const [salt, verifierSalt] = await Promise.all([
      storage.getItem('PasscodeAuth:salt'),
      storage.getItem('PasscodeAuth:verifierSalt'),
    ]);

    expect(salt).toBeDefined();
    expect(verifierSalt).toBeDefined();
    expect(verifierSalt).not.toBe(salt);
  });

  it('grants a short session exactly the configured number of uses', async () => {
    const storage = createMemoryStorage();
    await setupPasscode(storage, '123456');

    const auth = new PasscodeAuth(storage);
    const { token } = await auth.authorize(false, '123456', 2);

    expect(auth.getKey(token)).toBeDefined();
    expect(auth.getKey(token)).toBeDefined();
    expect(getKeyError(auth, token).code).toBe('session_expired');
  });

  describe('long session expiry', () => {
    beforeEach(() => jest.useFakeTimers());
    afterEach(() => jest.useRealTimers());

    it('stops returning the key once the time limit passes', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(true, '123456');

      expect(auth.getKey(token)).toBeDefined();

      jest.advanceTimersByTime(5 * 60 * 1000 + 1);

      expect(getKeyError(auth, token).code).toBe('session_expired');
    });
  });

  describe('releasing a session', () => {
    it('takes back the uses an operation did not spend', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(false, '123456', 2);

      expect(auth.getKey(token)).toBeDefined();
      auth.releaseSession(token);

      expect(getKeyError(auth, token).code).toBe('session_expired');
    });

    it('leaves a session that expires by time alone', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(true, '123456');

      auth.releaseSession(token);

      expect(auth.getKey(token)).toBeDefined();
    });

    it('leaves a session another token owns', async () => {
      const storage = createMemoryStorage();
      await setupPasscode(storage, '123456');

      const auth = new PasscodeAuth(storage);
      const { token } = await auth.authorize(false, '123456', 2);

      auth.releaseSession('passcode:someone-elses-token');

      expect(auth.getKey(token)).toBeDefined();
    });
  });
});
