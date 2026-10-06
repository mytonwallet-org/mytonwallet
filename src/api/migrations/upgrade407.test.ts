import type { Storage } from '../storages/types';

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  GLOBAL_STATE_CACHE_KEY: 'tonwallet-global-state',
  IS_AIR_APP: false,
  IS_EXTENSION: true,
  IS_GRAM_WALLET: true,
}));
jest.mock('../storages/extension', () => ({ __esModule: true, default: {} }));
jest.mock('../storages/idb', () => ({
  __esModule: true,
  default: { getItem: jest.fn().mockResolvedValue(undefined), getAll: jest.fn().mockResolvedValue({}) },
}));

import { GLOBAL_STATE_CACHE_KEY } from '../../config';
import { loadCache } from '../../global/cache';
import { INITIAL_STATE, STATE_VERSION } from '../../global/initialState';
import { decryptLegacyMnemonic } from '../../enclave/legacy/migration';
import { tryMigrateStorage } from '../common/helpers';
import { setEnvironment } from '../environment';
import { withStorage } from '../storages';

const PRIMARY_ACCOUNT_ID = '0-ton-mainnet';
const TWIN_ACCOUNT_ID = '0-ton-testnet';
const MULTICHAIN_ACCOUNT_ID = '1-ton-mainnet';
const PASSWORD = 'public-test-password';
const MNEMONIC = [
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'about',
];
const SALT_HEX = '000102030405060708090a0b0c0d0e0f';
const IV_HEX = '0f0e0d0c0b0a090807060504';

function hexToBytes(hex: string) {
  return new Uint8Array(hex.match(/.{2}/g)!.map((byte) => parseInt(byte, 16)));
}

function toBase64(buffer: ArrayBuffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

async function encrypt407Mnemonic() {
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(PASSWORD),
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
    new TextEncoder().encode(MNEMONIC.join(',')),
  );

  return `${SALT_HEX}:${IV_HEX}:${toBase64(encrypted)}`;
}

function clone<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

function createMemoryStorage(seed: Record<string, unknown>, failAtMutation?: number) {
  const values = new Map<string, unknown>(Object.entries(clone(seed)));
  let mutationCount = 0;
  function beforeMutation() {
    mutationCount += 1;
    if (mutationCount === failAtMutation) throw new Error(`Interrupted at storage mutation ${mutationCount}`);
  }
  const storage: Storage = {
    getItem: (name) => Promise.resolve(clone(values.get(name))),
    setItem: (name, value) => Promise.resolve().then(() => {
      beforeMutation();
      values.set(name, clone(value));
    }),
    removeItem: (name) => Promise.resolve().then(() => {
      beforeMutation();
      values.delete(name);
    }),
    clear: () => Promise.resolve().then(() => { values.clear(); }),
  };
  return { storage, values };
}

function create407Accounts(mnemonicEncrypted = 'cipher') {
  return {
    [PRIMARY_ACCOUNT_ID]: {
      type: 'ton',
      mnemonicEncrypted,
      ton: {
        type: 'ton', address: 'EQmain', publicKey: '11', index: 0, version: 'v3R2',
      },
    },
    [TWIN_ACCOUNT_ID]: {
      type: 'ton',
      mnemonicEncrypted,
      ton: {
        type: 'ton', address: 'kQtest', publicKey: '11', index: 0, version: 'v3R2',
      },
    },
    [MULTICHAIN_ACCOUNT_ID]: {
      type: 'bip39',
      mnemonicEncrypted,
      ton: {
        type: 'ton', address: 'EQmulti', publicKey: '22', index: 0, version: 'v3R2',
      },
      tron: {
        type: 'tron', address: 'Tmulti', publicKey: '33', index: 0,
      },
      byChain: {
        solana: { address: 'SolanaMulti', publicKey: '44', index: 0 },
      },
    },
  };
}

afterEach(() => localStorage.clear());

it('preserves existing account IDs, networks, permissions and the original encrypted mnemonic', async () => {
  setEnvironment({});
  const mnemonicEncrypted = await encrypt407Mnemonic();
  const dapps = { [TWIN_ACCOUNT_ID]: { 'https://testnet.example': { jsbridge: { connectedAt: 1 } } } };
  const { storage, values } = createMemoryStorage({
    stateVersion: 19, currentAccountId: TWIN_ACCOUNT_ID, dapps, accounts: create407Accounts(mnemonicEncrypted),
  });
  const onUpdate = jest.fn();
  const getItem = jest.spyOn(storage, 'getItem');
  await withStorage(storage, () => tryMigrateStorage(onUpdate));
  expect(values.get('stateVersion')).toBe(23);
  expect(getItem).not.toHaveBeenCalledWith('coreTwinsPurged');
  expect(values.get('currentAccountId')).toBe(TWIN_ACCOUNT_ID);
  expect(values.get('dapps')).toEqual(dapps);
  const accounts = values.get('accounts') as AnyLiteral;
  expect(Object.keys(accounts)).toEqual([PRIMARY_ACCOUNT_ID, TWIN_ACCOUNT_ID, MULTICHAIN_ACCOUNT_ID]);
  for (const account of Object.values(accounts) as AnyLiteral[]) {
    expect(account.mnemonicEncrypted).toBe(mnemonicEncrypted);
    await expect(decryptLegacyMnemonic(account.mnemonicEncrypted, PASSWORD)).resolves.toEqual(MNEMONIC);
  }
  await expect(decryptLegacyMnemonic(mnemonicEncrypted, 'wrong-password')).resolves.toBeUndefined();
  expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'removeAccounts' }));
});

it('retains both network records and their per-account UI data through cache migration', () => {
  localStorage.setItem(GLOBAL_STATE_CACHE_KEY, JSON.stringify({
    stateVersion: 44,
    currentAccountId: TWIN_ACCOUNT_ID,
    accounts: {
      byId: {
        [PRIMARY_ACCOUNT_ID]: {
          title: 'Mainnet wallet',
          type: 'mnemonic',
          addressByChain: { ton: 'EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c' },
        },
        [TWIN_ACCOUNT_ID]: {
          title: 'Testnet wallet',
          type: 'mnemonic',
          addressByChain: { ton: 'kQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHTW' },
        },
      },
    },
    byAccountId: {
      [PRIMARY_ACCOUNT_ID]: {
        currentTokenSlug: 'toncoin',
        activities: { byId: {}, idsBySlug: {} },
      },
      [TWIN_ACCOUNT_ID]: {
        currentTokenSlug: 'toncoin',
        activities: { byId: { testnetActivity: { id: 'testnetActivity' } }, idsBySlug: {} },
      },
    },
    settings: {
      ...INITIAL_STATE.settings,
      byAccountId: {
        [PRIMARY_ACCOUNT_ID]: { pinnedSlugs: ['toncoin'] },
        [TWIN_ACCOUNT_ID]: { pinnedSlugs: ['toncoin', 'testnet-token'] },
      },
    },
    tokenInfo: { bySlug: {} },
    pushNotifications: { enabledAccounts: { [TWIN_ACCOUNT_ID]: { address: 'kQpush' } } },
    currencyRates: INITIAL_STATE.currencyRates,
  }));

  const migrated = loadCache(INITIAL_STATE);

  expect(migrated.stateVersion).toBe(STATE_VERSION);
  expect(migrated.currentAccountId).toBe(TWIN_ACCOUNT_ID);
  expect(Object.keys(migrated.accounts!.byId)).toEqual([PRIMARY_ACCOUNT_ID, TWIN_ACCOUNT_ID]);
  expect(migrated.byAccountId).toHaveProperty(TWIN_ACCOUNT_ID);
  expect(migrated.byAccountId[TWIN_ACCOUNT_ID].currentTokenSlug).toBe('toncoin');
  expect(migrated.settings.byAccountId[TWIN_ACCOUNT_ID]?.pinnedSlugs).toEqual(['toncoin', 'testnet-token']);
  expect(migrated.pushNotifications.enabledAccounts).toEqual([TWIN_ACCOUNT_ID]);
});

it.each([1, 2, 3, 4, 5, 6, 7, 8])(
  'preserves every account when storage mutation %s interrupts the full migration and it retries',
  async (failAtMutation) => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage({
      stateVersion: 19,
      baseCurrency: 'USD',
      accounts: create407Accounts(),
    }, failAtMutation);

    const migration = withStorage(storage, () => tryMigrateStorage(jest.fn()));
    if (failAtMutation === 3) {
      await migration; // Removing the obsolete base currency is deliberately best-effort.
    } else {
      await expect(migration).rejects.toThrow('Interrupted');
    }
    await withStorage(storage, () => tryMigrateStorage(jest.fn(), [
      PRIMARY_ACCOUNT_ID, TWIN_ACCOUNT_ID, MULTICHAIN_ACCOUNT_ID,
    ]));

    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('accounts')).toEqual({
      [PRIMARY_ACCOUNT_ID]: {
        type: 'ton',
        mnemonicEncrypted: 'cipher',
        byChain: {
          ton: { address: 'EQmain', publicKey: '11', index: 0, version: 'v3R2' },
        },
      },
      [TWIN_ACCOUNT_ID]: {
        type: 'ton',
        mnemonicEncrypted: 'cipher',
        byChain: {
          ton: { address: 'kQtest', publicKey: '11', index: 0, version: 'v3R2' },
        },
      },
      [MULTICHAIN_ACCOUNT_ID]: {
        type: 'bip39',
        mnemonicEncrypted: 'cipher',
        byChain: {
          ton: {
            address: 'EQmulti', publicKey: '22', index: 0, version: 'v3R2',
            derivation: { path: 'm/44\'/607\'/{index}\'', index: 0 },
          },
          tron: { address: 'Tmulti', publicKey: '33', index: 0 },
          solana: {
            address: 'SolanaMulti', publicKey: '44', index: 0, derivationVersion: 1,
          },
        },
      },
    });
  },
);

it('serializes migrations on one storage before a later initialization can hold a stale snapshot', async () => {
  setEnvironment({});
  const values = new Map<string, unknown>(Object.entries(clone({
    stateVersion: 19,
    accounts: create407Accounts(),
  })));
  let versionReads = 0;
  let accountsReads = 0;
  let releaseFirstAccountsRead!: () => void;
  const firstAccountsReadGate = new Promise<void>((resolve) => {
    releaseFirstAccountsRead = resolve;
  });
  let firstAccountsReadStarted!: () => void;
  const firstAccountsRead = new Promise<void>((resolve) => {
    firstAccountsReadStarted = resolve;
  });
  const storage: Storage = {
    async getItem(name) {
      if (name === 'stateVersion') {
        versionReads += 1;
        if (versionReads === 2) {
          const accounts = clone(values.get('accounts')) as AnyLiteral;
          accounts['2-ton-mainnet'] = {
            type: 'ton', byChain: { ton: { address: 'EQadded', publicKey: '55', index: 0, version: 'v3R2' } },
          };
          values.set('accounts', accounts);
        }
      }
      if (name === 'accounts') {
        accountsReads += 1;
        if (accountsReads === 1) {
          firstAccountsReadStarted();
          await firstAccountsReadGate;
        }
      }
      return clone(values.get(name));
    },
    setItem(name, value) {
      values.set(name, clone(value));
      return Promise.resolve();
    },
    removeItem(name) {
      values.delete(name);
      return Promise.resolve();
    },
    clear() {
      values.clear();
      return Promise.resolve();
    },
  };

  const first = withStorage(storage, () => tryMigrateStorage(jest.fn()));
  await firstAccountsRead;
  const second = withStorage(storage, () => tryMigrateStorage(jest.fn()));
  await Promise.resolve();
  expect(versionReads).toBe(1);
  expect(accountsReads).toBe(1);
  releaseFirstAccountsRead();
  await Promise.all([first, second]);

  expect(values.get('stateVersion')).toBe(23);
  expect((values.get('accounts') as any)[PRIMARY_ACCOUNT_ID].byChain.ton.address).toBe('EQmain');
  expect((values.get('accounts') as any)[TWIN_ACCOUNT_ID].byChain.ton.address).toBe('kQtest');
  expect((values.get('accounts') as any)[MULTICHAIN_ACCOUNT_ID].byChain.solana.address).toBe('SolanaMulti');
  expect((values.get('accounts') as any)['2-ton-mainnet'].byChain.ton.address).toBe('EQadded');
});

it('lets an independent storage migrate while another runtime is blocked', async () => {
  setEnvironment({});
  const first = createMemoryStorage({ stateVersion: 19, accounts: create407Accounts('first-cipher') });
  const second = createMemoryStorage({ stateVersion: 19, accounts: create407Accounts('second-cipher') });
  const originalGet = first.storage.getItem;
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  first.storage.getItem = async (...args) => {
    await gate;
    return originalGet(...args);
  };
  const pending = withStorage(first.storage, () => tryMigrateStorage(jest.fn()));
  await withStorage(second.storage, () => tryMigrateStorage(jest.fn()));
  expect(first.values.get('stateVersion')).toBe(19);
  expect(second.values.get('stateVersion')).toBe(23);
  release();
  await pending;
  expect(first.values.get('stateVersion')).toBe(23);
  expect((first.values.get('accounts') as AnyLiteral)[PRIMARY_ACCOUNT_ID].mnemonicEncrypted).toBe('first-cipher');
  expect((second.values.get('accounts') as AnyLiteral)[PRIMARY_ACCOUNT_ID].mnemonicEncrypted).toBe('second-cipher');
});
