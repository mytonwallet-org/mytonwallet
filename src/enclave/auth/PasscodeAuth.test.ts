import type { SimpleStorage, StorageKey, StorageValue } from '../types';

import PasscodeAuth from './PasscodeAuth';

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

describe('PasscodeAuth', () => {
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
