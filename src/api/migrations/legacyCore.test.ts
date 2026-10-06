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

import { decryptLegacyMnemonic } from '../../enclave/legacy/migration';
import { migrateStorage } from '../common/helpers';
import { setEnvironment } from '../environment';
import { withStorage } from '../storages';
import { confirmLegacyCoreMigration } from './legacyCore';

const TWIN_ACCOUNT_ID = '0-ton-testnet';
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

describe('unopened legacy Core storage', () => {
  const legacySeed = {
    walletVersion: 'v3R2',
    isTestnet: true,
    address: 'kQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHTW',
    words: 'legacy-encrypted-words',
    publicKey: '11'.repeat(32),
    proxy: true,
  };

  it('leaves a flag-only profile untouched and initializes normally', async () => {
    setEnvironment({});
    const flags = { walletVersion: 'v3R2', isTestnet: true, proxy: true, magic: true };
    const { storage, values } = createMemoryStorage(flags);
    const onUpdate = jest.fn();

    await withStorage(storage, () => migrateStorage(onUpdate));

    expect(values.get('stateVersion')).toBe(23);
    expect(Object.fromEntries(Object.keys(flags).map((key) => [key, values.get(key)]))).toEqual(flags);
    expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
  });

  it.each(['mainnet', 'testnet'] as const)('imports only the original %s wallet and password', async (network) => {
    setEnvironment({});
    const words = await encrypt407Mnemonic();
    const address = network === 'mainnet'
      ? 'EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c' : legacySeed.address;
    const accountId = `0-ton-${network}`;
    const { storage, values } = createMemoryStorage({
      ...legacySeed, isTestnet: network === 'testnet', address, words,
    });
    const onUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(onUpdate));
    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('legacyCoreAccountsConverted')).toBe(true);
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
    expect(values.get('words')).toBe(words);
    expect(values.get('address')).toBe(address);
    expect(values.get('accounts')).toEqual({
      [accountId]: {
        type: 'ton', mnemonicEncrypted: words,
        byChain: { ton: { address, publicKey: legacySeed.publicKey, index: 0, version: 'v3R2' } },
      },
    });
    await expect(decryptLegacyMnemonic(words, PASSWORD)).resolves.toEqual(MNEMONIC);
    await expect(decryptLegacyMnemonic(words, 'wrong-password')).resolves.toBeUndefined();
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'migrateLegacyCoreApplication', accounts: [{ accountId, address }], currentAccountId: accountId,
    }));
  });

  it.each([1, 2, 3, 4])('resumes after flat storage write %s fails', async (failAtMutation) => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage(legacySeed, failAtMutation);
    const onUpdate = jest.fn();

    await expect(withStorage(storage, () => migrateStorage(onUpdate))).rejects.toThrow(
      `Interrupted at storage mutation ${failAtMutation}`,
    );
    expect(values.get('stateVersion')).toBeUndefined();
    const convertedAccounts = clone(values.get('accounts'));

    await withStorage(storage, () => migrateStorage(onUpdate));

    expect(values.get('stateVersion')).toBe(23);
    if (convertedAccounts) expect(values.get('accounts')).toEqual(convertedAccounts);
    expect(Object.keys(values.get('accounts') as object)).toEqual([TWIN_ACCOUNT_ID]);
    expect(values.get('words')).toBe(legacySeed.words);
  });

  it('reconciles only actual SDK records when 4.0.7 wrote its account map before the version stamp', async () => {
    const existing = {
      '0-ton-testnet': {
        type: 'ton', mnemonicEncrypted: legacySeed.words,
        ton: { type: 'ton', address: legacySeed.address, publicKey: legacySeed.publicKey, index: 0, version: 'v3R2' },
      },
      '0-ton-mainnet': {
        type: 'ton', mnemonicEncrypted: legacySeed.words,
        ton: { type: 'ton', address: 'EQmain', publicKey: legacySeed.publicKey, index: 0, version: 'v3R2' },
      },
    };
    const { storage, values } = createMemoryStorage({ ...legacySeed, accounts: existing });
    const onUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(onUpdate));
    expect(Object.keys(values.get('accounts') as object)).toEqual(Object.keys(existing));
    expect((values.get('accounts') as AnyLiteral)['0-ton-mainnet']).toEqual({
      type: 'ton', mnemonicEncrypted: legacySeed.words,
      byChain: { ton: { address: 'EQmain', publicKey: legacySeed.publicKey, index: 0, version: 'v3R2' } },
    });
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'migrateLegacyCoreApplication', currentAccountId: TWIN_ACCOUNT_ID,
      accounts: [
        { accountId: TWIN_ACCOUNT_ID, address: legacySeed.address },
        { accountId: '0-ton-mainnet', address: 'EQmain' },
      ],
    });
  });

  it('replays UI reconciliation at stateVersion 23 when the popup cache missed the first event', async () => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage(legacySeed);
    const firstOnUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(firstOnUpdate));
    const convertedAccounts = clone(values.get('accounts'));

    const reopenedOnUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(reopenedOnUpdate));

    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('accounts')).toEqual(convertedAccounts);
    expect(reopenedOnUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'migrateLegacyCoreApplication', currentAccountId: TWIN_ACCOUNT_ID,
    }));
  });

  it('stops reconciliation after the UI acknowledgement and does not resurrect a later deletion', async () => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage(legacySeed);
    await withStorage(storage, () => migrateStorage(jest.fn()));
    await withStorage(storage, confirmLegacyCoreMigration);

    const accounts = clone(values.get('accounts')) as AnyLiteral;
    delete accounts[TWIN_ACCOUNT_ID];
    values.set('accounts', accounts);
    const reopenedOnUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(reopenedOnUpdate));

    expect((values.get('accounts') as AnyLiteral)[TWIN_ACCOUNT_ID]).toBeUndefined();
    expect(values.get('words')).toBe(legacySeed.words);
    expect(reopenedOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({
      type: 'migrateLegacyCoreApplication',
    }));
  });

  it('does not rewrite SDK accounts while retrying a lost UI acknowledgement', async () => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage(legacySeed);
    await withStorage(storage, () => migrateStorage(jest.fn()));
    expect(values.get('legacyCoreAccountsConverted')).toBe(true);
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();

    const accounts = clone(values.get('accounts')) as AnyLiteral;
    delete accounts[TWIN_ACCOUNT_ID];
    values.set('accounts', accounts);
    const retryOnUpdate = jest.fn();
    await expect(withStorage(storage, () => migrateStorage(retryOnUpdate))).rejects.toThrow('Missing converted');
    expect((values.get('accounts') as AnyLiteral)[TWIN_ACCOUNT_ID]).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
    expect(retryOnUpdate).not.toHaveBeenCalled();
  });

  it('accepts accounts whose ciphertext was removed by a completed Enclave migration', async () => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage(legacySeed);
    await withStorage(storage, () => migrateStorage(jest.fn()));
    const accounts = clone(values.get('accounts')) as AnyLiteral;
    delete accounts[TWIN_ACCOUNT_ID].mnemonicEncrypted;
    values.set('accounts', accounts);

    await expect(withStorage(storage, () => migrateStorage(jest.fn()))).resolves.toBeUndefined();
    expect(values.get('words')).toBe(legacySeed.words);
  });

  it('replays a pending converted handoff while advancing an older SDK version', async () => {
    const { storage, values } = createMemoryStorage(legacySeed);
    await withStorage(storage, () => migrateStorage(jest.fn()));
    values.set('stateVersion', 22);
    for (const key of ['words', 'address', 'publicKey']) values.delete(key);
    const onUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(onUpdate));
    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
    expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
      type: 'migrateLegacyCoreApplication', accounts: [{ accountId: TWIN_ACCOUNT_ID, address: legacySeed.address }],
    }));
  });

  it('does not stamp an incomplete legacy profile as successfully migrated', async () => {
    setEnvironment({});
    const { storage, values } = createMemoryStorage({ address: legacySeed.address, words: legacySeed.words });
    const onUpdate = jest.fn();

    await expect(withStorage(storage, () => migrateStorage(onUpdate))).rejects.toThrow(
      'Incomplete legacy Core Wallet storage',
    );

    expect(values.get('stateVersion')).toBeUndefined();
    expect(values.get('accounts')).toBeUndefined();
  });

  it('keeps an unsupported existing record and refuses to complete its migration', async () => {
    const unsupported = { type: 'view', byChain: { ton: { address: 'EQview' } } };
    const { storage, values } = createMemoryStorage({ ...legacySeed, accounts: { '5-ton-mainnet': unsupported } });
    await expect(withStorage(storage, () => migrateStorage(jest.fn()))).rejects.toThrow('Unsupported');
    expect(values.get('stateVersion')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();
    expect((values.get('accounts') as AnyLiteral)['5-ton-mainnet']).toEqual(unsupported);
    expect(values.get('words')).toBe(legacySeed.words);
  });

  it.each([{ address: 'leftover' }, { ...legacySeed }])('ignores flat keys in versioned storage', async (keys) => {
    const accounts = {
      [TWIN_ACCOUNT_ID]: {
        type: 'ton', mnemonicEncrypted: 'versioned-cipher',
        ton: { type: 'ton', address: 'kQversioned', publicKey: '22', index: 0, version: 'W5' },
      },
    };
    const { storage, values } = createMemoryStorage({ ...keys, accounts, stateVersion: 19 });
    const onUpdate = jest.fn();
    await withStorage(storage, () => migrateStorage(onUpdate));
    await withStorage(storage, () => migrateStorage(onUpdate));
    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('legacyCoreAccountsConverted')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
    expect((values.get('accounts') as AnyLiteral)[TWIN_ACCOUNT_ID].mnemonicEncrypted).toBe('versioned-cipher');
    expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
  });

  it('ignores stale flat keys when the SDK schema is already current', async () => {
    const accounts = {
      '5-ton-mainnet': { type: 'view', byChain: { ton: { address: 'EQlive' } } },
    };
    const { storage, values } = createMemoryStorage({ ...legacySeed, accounts, stateVersion: 23 });
    const onUpdate = jest.fn();

    await withStorage(storage, () => migrateStorage(onUpdate));

    expect(values.get('accounts')).toEqual(accounts);
    expect(values.get('legacyCoreAccountsConverted')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
    expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
  });

  it('retries versioned classification when its terminal marker write fails', async () => {
    const accounts = {
      [TWIN_ACCOUNT_ID]: {
        type: 'ton', mnemonicEncrypted: 'versioned-cipher',
        ton: { type: 'ton', address: 'kQversioned', publicKey: '22', index: 0, version: 'W5' },
      },
    };
    const { storage, values } = createMemoryStorage({ ...legacySeed, accounts, stateVersion: 19 });
    const originalSetItem = storage.setItem;
    let shouldFailCompletion = true;
    storage.setItem = async (name, value) => {
      if (name === 'legacyCoreMigrationCompleted' && shouldFailCompletion) {
        shouldFailCompletion = false;
        throw new Error('Interrupted while classifying versioned storage');
      }
      return originalSetItem(name, value);
    };
    const onUpdate = jest.fn();

    await expect(withStorage(storage, () => migrateStorage(onUpdate))).rejects.toThrow(
      'Interrupted while classifying versioned storage',
    );
    expect(values.get('legacyCoreAccountsConverted')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBeUndefined();

    await withStorage(storage, () => migrateStorage(onUpdate));

    expect(values.get('stateVersion')).toBe(23);
    expect(values.get('legacyCoreAccountsConverted')).toBeUndefined();
    expect(values.get('legacyCoreMigrationCompleted')).toBe(true);
    expect((values.get('accounts') as AnyLiteral)[TWIN_ACCOUNT_ID].byChain.ton.address).toBe('kQversioned');
    expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'migrateLegacyCoreApplication' }));
  });

  it('does not overwrite a conflicting account map or stamp the profile', async () => {
    setEnvironment({});
    const conflictingAccounts = {
      [TWIN_ACCOUNT_ID]: {
        type: 'ton',
        mnemonicEncrypted: 'different-cipher',
        byChain: { ton: { address: 'kQdifferent', publicKey: '22', index: 0, version: 'v3R2' } },
      },
    };
    const { storage, values } = createMemoryStorage({ ...legacySeed, accounts: conflictingAccounts });
    const onUpdate = jest.fn();

    await expect(withStorage(storage, () => migrateStorage(onUpdate))).rejects.toThrow(
      'Legacy Core Wallet conflicts',
    );

    expect(values.get('stateVersion')).toBeUndefined();
    expect(values.get('accounts')).toEqual(conflictingAccounts);
  });
});
