import Deferred from '../../util/Deferred';
import { pause } from '../../util/schedulers';
import { removeAccountValue, removeNetworkAccountsValue, setAccountValue } from './accounts';

jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
  },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { storage } = require('../storages') as { storage: { getItem: jest.Mock; setItem: jest.Mock } };

const ACCOUNTS_KEY = 'accounts' as const;

/** Creates an isolated in-memory database and wires it into the storage mock. */
function createIsolatedDb(initial: Record<string, any> = {}) {
  const db: Record<string, any> = { [ACCOUNTS_KEY]: { ...initial } };
  storage.getItem.mockImplementation((key: string) => db[key] ?? undefined);
  storage.setItem.mockImplementation((key: string, value: any) => {
    db[key] = value;
  });
  return db;
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('setAccountValue', () => {
  it('creates an account entry when the key does not exist yet', async () => {
    const db = createIsolatedDb();
    db[ACCOUNTS_KEY] = undefined;

    await setAccountValue('0-mainnet', ACCOUNTS_KEY, { type: 'bip39' });

    expect(db[ACCOUNTS_KEY]).toEqual({ '0-mainnet': { type: 'bip39' } });
  });

  it('updates the target account and leaves others untouched', async () => {
    const db = createIsolatedDb({ '0-mainnet': { v: 1 }, '1-mainnet': { v: 2 } });

    await setAccountValue('0-mainnet', ACCOUNTS_KEY, { v: 99 });

    expect(db[ACCOUNTS_KEY]).toEqual({ '0-mainnet': { v: 99 }, '1-mainnet': { v: 2 } });
  });
});

describe('removeAccountValue', () => {
  it('removes the specified account and leaves others untouched', async () => {
    const db = createIsolatedDb({ '0-mainnet': { v: 1 }, '1-mainnet': { v: 2 } });

    await removeAccountValue('0-mainnet', ACCOUNTS_KEY);

    expect(db[ACCOUNTS_KEY]).not.toHaveProperty('0-mainnet');
    expect(db[ACCOUNTS_KEY]).toHaveProperty('1-mainnet');
  });

  it('does nothing when the storage key is absent', async () => {
    const db = createIsolatedDb();
    db[ACCOUNTS_KEY] = undefined;

    await removeAccountValue('0-mainnet', ACCOUNTS_KEY);

    expect(storage.setItem).not.toHaveBeenCalled();
  });

  it('does nothing when the account is not in the list', async () => {
    const db = createIsolatedDb({ '1-mainnet': { v: 2 } });

    await removeAccountValue('0-mainnet', ACCOUNTS_KEY);

    expect(db[ACCOUNTS_KEY]).toEqual({ '1-mainnet': { v: 2 } });
  });
});

describe('removeNetworkAccountsValue', () => {
  it('removes only accounts belonging to the given network', async () => {
    const db = createIsolatedDb({
      '0-mainnet': { v: 1 },
      '1-mainnet': { v: 2 },
      '0-testnet': { v: 3 },
    });

    await removeNetworkAccountsValue('mainnet', ACCOUNTS_KEY);

    expect(db[ACCOUNTS_KEY]).toEqual({ '0-testnet': { v: 3 } });
  });

  it('does nothing when the storage key is absent', async () => {
    const db = createIsolatedDb();
    db[ACCOUNTS_KEY] = undefined;

    await removeNetworkAccountsValue('mainnet', ACCOUNTS_KEY);

    expect(storage.setItem).not.toHaveBeenCalled();
  });
});

describe('serialization (race-condition fix)', () => {
  /**
   * Regression test for the read-modify-write race that caused deleted accounts to
   * reappear in storage.
   *
   * Old behaviour (no queue):
   *   1. setAccountValue reads {acc_del, acc_active} ── delay ─┐
   *   2. removeAccountValue runs fully → writes {acc_active}   │
   *   3. setAccountValue writes stale snapshot ────────────────┘
   *        → acc_del is RESTORED  ← bug
   *
   * New behaviour (write queue):
   *   setAccountValue holds the queue slot for its entire read+write sequence.
   *   removeAccountValue cannot start until that slot is released.
   *   When removeAccountValue finally runs it reads the fresh state and correctly
   *   removes acc_del, regardless of what setAccountValue wrote during its slot.
   */
  it('deleted account is not restored when setAccountValue runs concurrently', async () => {
    const db = createIsolatedDb({ '0-mainnet': { v: 'del' }, '1-mainnet': { v: 'active' } });

    const getDeferred = new Deferred<void>();
    let getCallCount = 0;

    // Simulate slow storage: capture a stale snapshot at read-time, then delay returning it.
    // Without the queue the write from setAccountValue (using the stale snapshot) would
    // arrive *after* removeAccountValue has already cleaned up, restoring acc_del.
    storage.getItem.mockImplementation(async (key: string) => {
      const snapshot = db[key] ? { ...db[key] } : undefined;

      if (key === ACCOUNTS_KEY && getCallCount++ === 0) {
        await getDeferred.promise; // pause the first read (belongs to setAccountValue)
      }

      return snapshot; // always returns snapshot taken BEFORE the delay
    });

    // setAccountValue enters the queue first; its getItem is delayed.
    const setOp = setAccountValue('1-mainnet', ACCOUNTS_KEY, { v: 'active_updated' });

    // Give the queue slot time to reach the deferred pause.
    await pause(5);

    // removeAccountValue is enqueued second and must wait for setOp to finish.
    const removeOp = removeAccountValue('0-mainnet', ACCOUNTS_KEY);

    // Release setAccountValue's delayed read.
    // It will write back the stale snapshot (which still contains acc_del).
    // removeAccountValue then runs next, reads the fresh state and removes acc_del.
    getDeferred.resolve();

    await Promise.all([setOp, removeOp]);

    expect(db[ACCOUNTS_KEY]).not.toHaveProperty('0-mainnet');
    expect(db[ACCOUNTS_KEY]).toHaveProperty('1-mainnet', { v: 'active_updated' });
  });

  it('multiple concurrent operations produce consistent final state', async () => {
    const db = createIsolatedDb({
      '0-mainnet': { v: 0 },
      '1-mainnet': { v: 1 },
      '2-mainnet': { v: 2 },
    });

    await Promise.all([
      removeAccountValue('0-mainnet', ACCOUNTS_KEY),
      removeAccountValue('1-mainnet', ACCOUNTS_KEY),
      setAccountValue('2-mainnet', ACCOUNTS_KEY, { v: 99 }),
    ]);

    expect(db[ACCOUNTS_KEY]).toEqual({ '2-mainnet': { v: 99 } });
  });

  it('operations on different StorageKeys do not block each other', async () => {
    const db: Record<string, any> = {
      [ACCOUNTS_KEY]: { '0-mainnet': { v: 1 } },
      dapps: { '0-mainnet': { v: 2 } },
    };
    const completed: string[] = [];

    storage.getItem.mockImplementation((key: string) => db[key] ?? undefined);
    storage.setItem.mockImplementation((key: string, value: any) => {
      db[key] = value;
      completed.push(key);
    });

    await Promise.all([
      removeAccountValue('0-mainnet', ACCOUNTS_KEY),
      removeAccountValue('0-mainnet', 'dapps' as any),
    ]);

    expect(completed).toContain(ACCOUNTS_KEY);
    expect(completed).toContain('dapps');
    expect(db[ACCOUNTS_KEY]).not.toHaveProperty('0-mainnet');
    expect(db.dapps).not.toHaveProperty('0-mainnet');
  });
});
