import type { Storage } from '../storages/types';

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'), IS_EXTENSION: true, IS_GRAM_WALLET: true, IS_AIR_APP: false,
}));
jest.mock('../storages/extension', () => ({ __esModule: true, default: {} }));
jest.mock('../methods/polling', () => ({
  removeAllPollingAccounts: jest.fn(), removeNetworkPollingAccounts: jest.fn(), removePollingAccount: jest.fn(),
}));
jest.mock('../methods/accounts', () => ({ deactivateAllAccounts: jest.fn(), activateAccount: jest.fn() }));
jest.mock('../methods/agentV2Lifecycle', () => ({ resetAgentV2: jest.fn() }));
jest.mock('../db', () => ({ ...jest.requireActual('../db'), tokenRepository: { clear: jest.fn() } }));

import { tryMigrateStorage } from '../common/helpers';
import { setEnvironment } from '../environment';
import { removeAccount, removeNetworkAccounts, resetAccounts } from '../methods/auth';
import { withStorage } from '../storages';

const ORIGINAL = '0-ton-testnet';
const OTHER = '1-ton-mainnet';
const LEGACY = {
  walletVersion: 'v3R2', isTestnet: true, address: 'kQoriginal', words: 'original-cipher', publicKey: '11',
};

function createStorage() {
  const values = new Map<string, any>(Object.entries(LEGACY));
  const storage: Storage = {
    getItem: (name) => Promise.resolve(values.get(name)),
    setItem: (name, value) => Promise.resolve().then(() => { values.set(name, JSON.parse(JSON.stringify(value))); }),
    removeItem: (name) => Promise.resolve().then(() => { values.delete(name); }),
    clear: () => Promise.resolve().then(() => { values.clear(); }),
  };
  return { values, storage };
}

it.each(['all', 'original account', 'original network'])(
  'does not replay an intentionally removed flat import after deleting %s', async (scope) => {
    setEnvironment({});
    const { values, storage } = createStorage();
    await withStorage(storage, () => tryMigrateStorage(jest.fn()));
    const other = { type: 'ton', mnemonicEncrypted: 'other-cipher', byChain: { ton: { address: 'EQother' } } };
    values.set('accounts', { ...values.get('accounts'), [OTHER]: other });
    await withStorage(storage, () => {
      if (scope === 'all') return resetAccounts();
      if (scope === 'original network') return removeNetworkAccounts('testnet');
      return removeAccount(ORIGINAL, undefined);
    });
    expect(values.get('words')).toBeUndefined();
    expect(values.get('address')).toBeUndefined();
    expect(values.get('publicKey')).toBeUndefined();
    expect(values.get('accounts')).toEqual(scope === 'all' ? undefined : { [OTHER]: other });
    const onUpdate = jest.fn();
    await withStorage(storage, () => tryMigrateStorage(onUpdate));
    expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
    expect(values.get('accounts')).toEqual(scope === 'all' ? undefined : { [OTHER]: other });
  },
);

it.each(['account', 'network'])('does not retire the flat import when deleting another %s', async (scope) => {
  setEnvironment({});
  const { values, storage } = createStorage();
  await withStorage(storage, () => tryMigrateStorage(jest.fn()));
  const original = values.get('accounts')[ORIGINAL];
  values.set('accounts', { [ORIGINAL]: original, [OTHER]: { type: 'ton', byChain: { ton: { address: 'EQother' } } } });
  await withStorage(storage, () => scope === 'network'
    ? removeNetworkAccounts('mainnet') : removeAccount(OTHER, undefined));
  expect(values.get('words')).toBe(LEGACY.words);
  expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
  const onUpdate = jest.fn();
  await withStorage(storage, () => tryMigrateStorage(onUpdate));
  expect(values.get('accounts')).toEqual({ [ORIGINAL]: original });
  expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
    type: 'migrateLegacyCoreApplication', accounts: [{ accountId: ORIGINAL, address: LEGACY.address }],
  }));
});

it.each(['address', 'words', 'publicKey', 'completion marker'])(
  'recovers the durable account after failed %s before its first UI acknowledgement', async (stage) => {
    setEnvironment({});
    const { values, storage } = createStorage();
    await withStorage(storage, () => tryMigrateStorage(jest.fn()));
    const accounts = values.get('accounts');
    let didFail = false;
    const remove = storage.removeItem;
    const set = storage.setItem;
    storage.removeItem = (name) => {
      if (!didFail && stage !== 'completion marker' && name === (stage as never)) {
        didFail = true;
        return Promise.reject(new Error('cleanup failed'));
      }
      return remove(name);
    };
    storage.setItem = (name, value) => {
      if (!didFail && stage === 'completion marker' && name === 'legacyCoreMigrationCompleted') {
        didFail = true;
        return Promise.reject(new Error('marker failed'));
      }
      return set(name, value);
    };
    await expect(withStorage(storage, resetAccounts)).rejects.toThrow('failed');
    expect(values.get('accounts')).toEqual(accounts);
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
    if (stage !== 'address') expect(values.get('address')).toBeUndefined();
    const onUpdate = jest.fn();
    await withStorage(storage, () => tryMigrateStorage(onUpdate));
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'migrateLegacyCoreApplication', accounts: [{ accountId: ORIGINAL, address: LEGACY.address }],
    }));
    await withStorage(storage, resetAccounts);
    expect(values.get('accounts')).toBeUndefined();
    expect(values.get('words')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
    const reopened = jest.fn();
    await withStorage(storage, () => tryMigrateStorage(reopened));
    expect(reopened).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
  },
);

it('finishes an in-flight migration snapshot before retiring and deleting its wallet', async () => {
  setEnvironment({});
  const { values, storage } = createStorage();
  await withStorage(storage, () => tryMigrateStorage(jest.fn()));
  const originalGet = storage.getItem;
  let releaseRead!: () => void;
  let signalRead!: () => void;
  const gate = new Promise<void>((resolve) => {
    releaseRead = resolve;
  });
  const started = new Promise<void>((resolve) => {
    signalRead = resolve;
  });
  storage.getItem = async (name, force) => {
    const result = await originalGet(name, force);
    if (name === 'accounts') {
      signalRead();
      await gate;
    }
    return result;
  };
  const order: string[] = [];
  const migration = withStorage(storage, () => tryMigrateStorage((update) => {
    if (update.type === 'migrateLegacyCoreApplication') order.push('migration');
  }));
  await started;
  const reset = withStorage(storage, resetAccounts).then(() => {
    order.push('reset');
  });
  await new Promise((resolve) => setTimeout(resolve, 0));
  releaseRead();
  await Promise.all([migration, reset]);
  expect(order).toEqual(['migration', 'reset']);
  expect(values.get('accounts')).toBeUndefined();
  expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
});

it('keeps cleanup inside the migration queue until an earlier removal settles', async () => {
  setEnvironment({});
  const { storage } = createStorage();
  await withStorage(storage, () => tryMigrateStorage(jest.fn()));
  const remove = storage.removeItem;
  let releaseRemoval!: () => void;
  let signalRemoval!: () => void;
  const gate = new Promise<void>((resolve) => {
    releaseRemoval = resolve;
  });
  const started = new Promise<void>((resolve) => {
    signalRemoval = resolve;
  });
  storage.removeItem = async (name) => {
    if (name === ('address' as never)) {
      signalRemoval();
      await gate;
    }
    if (name === ('words' as never)) throw new Error('cleanup failed');
    await remove(name);
  };
  let didReject = false;
  const reset = withStorage(storage, resetAccounts).catch(() => {
    didReject = true;
  });
  await started;
  const onUpdate = jest.fn();
  const migration = withStorage(storage, () => tryMigrateStorage(onUpdate));
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(didReject).toBe(false);
  expect(onUpdate).not.toHaveBeenCalled();
  releaseRemoval();
  await Promise.all([reset, migration]);
  expect(didReject).toBe(true);
  expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
});

it.each(['0-mainnet', '1-mainnet', '0-testnet', '2-ton-mainnet'])(
  'does not read obsolete Core keys when removing modern or unrelated account %s', async (accountId) => {
    setEnvironment({});
    const { values, storage } = createStorage();
    const other = { type: 'view', byChain: { ton: { address: 'EQother' } } };
    values.set('accounts', { [accountId]: other, [ORIGINAL]: other });
    const get = storage.getItem;
    storage.getItem = (name, force) => {
      if (name === ('address' as never)) throw new Error('legacy storage read failed');
      return get(name, force);
    };
    await withStorage(storage, () => removeAccount(accountId, undefined));
    expect(values.get('accounts')).toEqual({ [ORIGINAL]: other });
    expect(values.get('words')).toBe(LEGACY.words);
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
  },
);

it('retains the original account on a legacy read failure and permits a successful removal retry', async () => {
  setEnvironment({});
  const { values, storage } = createStorage();
  await withStorage(storage, () => tryMigrateStorage(jest.fn()));
  const accounts = values.get('accounts');
  const get = storage.getItem;
  storage.getItem = (name, force) => name === ('address' as never)
    ? Promise.reject(new Error('legacy read failed')) : get(name, force);
  await expect(withStorage(storage, () => removeAccount(ORIGINAL, undefined))).rejects.toThrow('legacy read failed');
  expect(values.get('accounts')).toEqual(accounts);
  expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
  storage.getItem = get;
  await withStorage(storage, () => removeAccount(ORIGINAL, undefined));
  expect(values.get('accounts')).toEqual({});
  expect(values.get('words')).toBeUndefined();
  expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
});
