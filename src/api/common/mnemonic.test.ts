import type { ApiAccountWithMnemonic } from '../types';

import { decryptMnemonic, encryptMnemonic, getMnemonic } from './mnemonic';

// `getMnemonic` triggers a lazy re-encryption that writes through `updateStoredAccount`
// (from `./accounts`), which persists via `storage`. Mock `../storages` with an in-memory
// DB (same approach as `accounts.test.ts`) so we can observe the migrated value.
jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    mutateItem: jest.fn(),
  },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { storage } = require('../storages') as {
  storage: { getItem: jest.Mock; setItem: jest.Mock; mutateItem: jest.Mock };
};

const ACCOUNTS_KEY = 'accounts' as const;

/** Creates an isolated in-memory database and wires it into the storage mock. */
function createIsolatedDb(initial: Record<string, any> = {}) {
  const db: Record<string, any> = { [ACCOUNTS_KEY]: { ...initial } };
  storage.getItem.mockImplementation((key: string) => db[key] ?? undefined);
  storage.setItem.mockImplementation((key: string, value: any) => {
    db[key] = value;
  });
  storage.mutateItem.mockImplementation((key: string, mutate: (currentValue: any) => any) => {
    const nextValue = mutate(db[key] ?? undefined);
    db[key] = nextValue;
    return nextValue;
  });
  return db;
}

// A realistic legacy wallet: 24 words (pre-2024-09 wallets were 256-bit / 24-word).
// BIP39 validity is irrelevant here — encrypt/decrypt only join/split on commas.
const MNEMONIC = (
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon '
  + 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art'
).split(' ');
const PASSWORD = 'correct horse battery staple';

/**
 * Reproduces the pre-2024-09 legacy encryption scheme exactly as `decryptMnemonicLegacy`
 * expects to read it: raw AES-GCM key = SHA-256(password) (no KDF, no salt); the serialized
 * blob is `<24 hex chars of the 12-byte IV><base64 of (ciphertext || 16-byte GCM tag)>`.
 * Contains no ':' so `decryptMnemonic` routes it to the legacy path.
 */
async function encryptMnemonicLegacy(mnemonic: string[], password: string) {
  const plaintext = mnemonic.join(',');
  const pwUtf8 = new TextEncoder().encode(password);
  const pwHash = await crypto.subtle.digest('SHA-256', pwUtf8);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const alg = { name: 'AES-GCM', iv };
  const key = await crypto.subtle.importKey('raw', pwHash, alg, false, ['encrypt']);
  const ptUint8 = new TextEncoder().encode(plaintext);
  const ctBuffer = await crypto.subtle.encrypt(alg, key, ptUint8);
  const ctArray = Array.from(new Uint8Array(ctBuffer));
  const ctBase64 = btoa(String.fromCharCode(...ctArray));
  const ivHex = Array.from(iv).map((b) => (`00${b.toString(16)}`).slice(-2)).join('');

  return `${ivHex}${ctBase64}`;
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('modern format (PBKDF2 salt:iv:ct)', () => {
  it('round-trips encrypt → decrypt', async () => {
    const encrypted = await encryptMnemonic(MNEMONIC, PASSWORD);
    expect(encrypted).toContain(':');
    expect(encrypted.split(':')).toHaveLength(3);

    const decrypted = await decryptMnemonic(encrypted, PASSWORD);
    expect(decrypted).toEqual(MNEMONIC);
  });

  it('rejects a wrong password', async () => {
    const encrypted = await encryptMnemonic(MNEMONIC, PASSWORD);
    await expect(decryptMnemonic(encrypted, 'wrong password')).rejects.toThrow();
  });
});

describe('legacy format (unsalted SHA-256, no ":")', () => {
  it('decrypts a legacy blob via decryptMnemonic', async () => {
    const legacy = await encryptMnemonicLegacy(MNEMONIC, PASSWORD);
    expect(legacy).not.toContain(':');

    const decrypted = await decryptMnemonic(legacy, PASSWORD);
    expect(decrypted).toEqual(MNEMONIC);
  });

  it('rejects a wrong password on a legacy blob', async () => {
    const legacy = await encryptMnemonicLegacy(MNEMONIC, PASSWORD);
    await expect(decryptMnemonic(legacy, 'wrong password')).rejects.toThrow();
  });
});

describe('getMnemonic lazy re-encryption', () => {
  it('rewrites a legacy account to the modern format on successful unlock', async () => {
    const accountId = '0-mainnet';
    const legacy = await encryptMnemonicLegacy(MNEMONIC, PASSWORD);
    const db = createIsolatedDb({
      [accountId]: { type: 'bip39', mnemonicEncrypted: legacy },
    });
    const account = { type: 'bip39', mnemonicEncrypted: legacy } as unknown as ApiAccountWithMnemonic;

    const result = await getMnemonic(accountId, PASSWORD, account);
    expect(result).toEqual(MNEMONIC);

    const stored: string = db[ACCOUNTS_KEY][accountId].mnemonicEncrypted;
    expect(stored).not.toBe(legacy);
    expect(stored).toContain(':');
    // The migrated blob must still unlock with the same password.
    expect(await decryptMnemonic(stored, PASSWORD)).toEqual(MNEMONIC);
  });

  it('leaves a modern account untouched (no migration write)', async () => {
    const accountId = '0-mainnet';
    const modern = await encryptMnemonic(MNEMONIC, PASSWORD);
    const db = createIsolatedDb({
      [accountId]: { type: 'bip39', mnemonicEncrypted: modern },
    });
    const account = { type: 'bip39', mnemonicEncrypted: modern } as unknown as ApiAccountWithMnemonic;

    const result = await getMnemonic(accountId, PASSWORD, account);
    expect(result).toEqual(MNEMONIC);

    // Modern already has ':' → no re-encryption path → storage stays byte-identical.
    expect(db[ACCOUNTS_KEY][accountId].mnemonicEncrypted).toBe(modern);
    expect(storage.mutateItem).not.toHaveBeenCalled();
  });

  it('returns undefined for a wrong password without migrating', async () => {
    const accountId = '0-mainnet';
    const legacy = await encryptMnemonicLegacy(MNEMONIC, PASSWORD);
    const db = createIsolatedDb({
      [accountId]: { type: 'bip39', mnemonicEncrypted: legacy },
    });
    const account = { type: 'bip39', mnemonicEncrypted: legacy } as unknown as ApiAccountWithMnemonic;

    const result = await getMnemonic(accountId, 'wrong password', account);
    expect(result).toBeUndefined();

    // Failed unlock must not overwrite the stored legacy blob.
    expect(db[ACCOUNTS_KEY][accountId].mnemonicEncrypted).toBe(legacy);
    expect(storage.mutateItem).not.toHaveBeenCalled();
  });
});
