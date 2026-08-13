import type { SimpleStorage, StorageKey, StorageValue } from './types';

const PASSCODE = '123456';
const ACCOUNT_ID = '0-mainnet';
const SECRET = 'angry calm sad';

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

/**
 * Wraps a storage so that reads of one key park until released. Two callers awaiting the same read
 * are interleaved on purpose here, which is what a race in production does by accident.
 */
function createHeldStorage(storage: SimpleStorage, heldKey: StorageKey) {
  const parked: NoneToVoidFunction[] = [];
  let isHolding = true;

  return {
    storage: {
      ...storage,
      getItem: (name: StorageKey) => (isHolding && name === heldKey
        ? new Promise<void>((resolve) => { parked.push(resolve); }).then(() => storage.getItem(name))
        : storage.getItem(name)),
    } satisfies SimpleStorage,
    waitForCalls: async (count: number) => {
      while (parked.length < count) {
        await new Promise(setImmediate);
      }
    },
    release: () => parked.shift()!(),
    passThrough: () => { isHolding = false; },
  };
}

// The enclave keeps `auths` and `storage` in module scope, so every test needs its own module instance
async function loadEnclave(storage: SimpleStorage) {
  jest.resetModules();
  const enclave = await import('./enclave');
  await enclave.setupStorage(storage);

  return enclave;
}

describe('enclave', () => {
  it('exports a secret imported under the same master key', async () => {
    const storage = createMemoryStorage();
    const enclave = await loadEnclave(storage);

    const setupSession = await enclave.setupAuth('passcode', PASSCODE);
    await enclave.importSecret(ACCOUNT_ID, SECRET, setupSession.token);

    const readSession = await enclave.authorize('passcode', false, PASSCODE);

    await expect(enclave.exportSecret(ACCOUNT_ID, readSession!.token)).resolves.toBe(SECRET);
  });

  it('refuses to set up an auth over an already initialized storage', async () => {
    const storage = createMemoryStorage();
    const enclave = await loadEnclave(storage);

    const setupSession = await enclave.setupAuth('passcode', PASSCODE);
    await enclave.importSecret(ACCOUNT_ID, SECRET, setupSession.token);

    // A second setup mints a fresh master key and orphans every secret encrypted under the previous one
    const error = await enclave.setupAuth('passcode', PASSCODE).catch((err) => err);

    expect(error.code).toBe('auth_already_configured');
  });

  // The loser of the race is told something a caller can act on: the setup is in flight, so waiting
  // and retrying works. That is the opposite of finding a master key already minted, and the two are
  // told apart by their codes rather than sharing one
  it('lets only one of two concurrent setups through', async () => {
    const storage = createMemoryStorage();
    const enclave = await loadEnclave(storage);

    const [first, second] = await Promise.allSettled([
      enclave.setupAuth('passcode', PASSCODE),
      enclave.setupAuth('passcode', PASSCODE),
    ]);

    expect(first.status).toBe('fulfilled');
    expect(second.status).toBe('rejected');
    expect((second as PromiseRejectedResult).reason.code).toBe('auth_setup_in_progress');
  });

  it('reports a missing secret as a domain error', async () => {
    const storage = createMemoryStorage();
    const enclave = await loadEnclave(storage);

    const session = await enclave.setupAuth('passcode', PASSCODE);
    const error = await enclave.exportSecret(ACCOUNT_ID, session.token).catch((err) => err);

    expect(error.name).toBe('EnclaveError');
    expect(error.code).toBe('secret_missing');
  });

  it('reports a spent session as a domain error', async () => {
    const storage = createMemoryStorage();
    const enclave = await loadEnclave(storage);

    const session = await enclave.setupAuth('passcode', PASSCODE);
    // The default session carries a single usage, and the import spends it
    await enclave.importSecret(ACCOUNT_ID, SECRET, session.token);

    const error = await enclave.exportSecret(ACCOUNT_ID, session.token).catch((err) => err);

    expect(error.name).toBe('EnclaveError');
    expect(error.code).toBe('session_expired');
  });

  // An interrupted migration or a lost cache leaves the auth configured on disk while the module holds
  // no instance for it, and that is exactly the state the recovery has to authorize from
  it('authorizes against an auth that only exists in storage', async () => {
    const storage = createMemoryStorage();
    const setupEnclave = await loadEnclave(storage);
    const session = await setupEnclave.setupAuth('passcode', PASSCODE);
    await setupEnclave.importSecret(ACCOUNT_ID, SECRET, session.token);

    const freshEnclave = await loadEnclave(storage);
    const restoredSession = await freshEnclave.authorize('passcode', false, PASSCODE);

    expect(restoredSession).toBeDefined();
    await expect(freshEnclave.exportSecret(ACCOUNT_ID, restoredSession!.token)).resolves.toBe(SECRET);
  });

  // Both calls look for an instance while none is registered yet, so a registry that let each add its
  // own would keep the first one and answer every later token with the session it never issued
  it('shares one auth instance between two concurrent authorizations', async () => {
    const storage = createMemoryStorage();
    const setupEnclave = await loadEnclave(storage);
    const session = await setupEnclave.setupAuth('passcode', PASSCODE);
    await setupEnclave.importSecret(ACCOUNT_ID, SECRET, session.token);

    // The lookup that decides whether an auth exists on disk, held open to keep both callers inside
    // the window where neither has registered anything
    const held = createHeldStorage(storage, 'encryptedMasterKey:auth-passcode');
    const freshEnclave = await loadEnclave(held.storage);

    const firstAuthorization = freshEnclave.authorize('passcode', false, PASSCODE);
    const secondAuthorization = freshEnclave.authorize('passcode', false, PASSCODE);
    await held.waitForCalls(2);

    // Released one by one, so the second session is the later one and the assertion has one answer
    held.release();
    await firstAuthorization;
    held.release();
    const second = await secondAuthorization;
    held.passThrough();

    await expect(freshEnclave.exportSecret(ACCOUNT_ID, second!.token)).resolves.toBe(SECRET);
  });

  it('refuses to authorize when no auth is configured', async () => {
    const enclave = await loadEnclave(createMemoryStorage());

    await expect(enclave.authorize('passcode', false, PASSCODE)).resolves.toBeUndefined();
    await expect(enclave.isAuthProvisioned('passcode')).resolves.toBe(false);
  });
});
