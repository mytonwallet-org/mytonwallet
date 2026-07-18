// F1 characterization: on the full-featured combo build, migrating a legacy toncenter TON Wallet must NOT create the
// invisible opposite-network twin (it would leave the mnemonic behind on logout). See `migrateCoreWallet` in helpers.ts.

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_CORE_WALLET: true,
  IS_FEATURE_LIMITED: false, // combo
  IS_AIR_APP: false,
  IS_EXTENSION: false,
}));

const legacyStore: Record<string, any> = {
  walletVersion: 'v4R2',
  address: 'EQD__legacy_mainnet_address',
  words: 'encrypted-mnemonic',
  publicKey: 'PUBKEY',
};

jest.mock('../storages/localStorage', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn((key: string) => legacyStore[key]),
    removeItem: jest.fn((key: string) => { delete legacyStore[key]; }),
  },
}));

const db: Record<string, any> = {};
jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn((key: string) => db[key]),
    setItem: jest.fn((key: string, value: any) => { db[key] = value; }),
  },
}));

jest.mock('../storages/airStorage', () => ({ __esModule: true, default: {} }));
jest.mock('../storages/idb', () => ({ __esModule: true, default: {} }));
jest.mock('../chains/ton/util/tonCore', () => ({ toBase64Address: jest.fn(() => 'converted') }));
jest.mock('../environment', () => ({ getEnvironment: jest.fn(() => ({ isDappSupported: false })) }));
jest.mock('./addresses', () => ({
  checkHasScamLink: jest.fn(),
  checkHasTelegramBotMention: jest.fn(),
  getKnownAddresses: jest.fn(),
  getScamMarkers: jest.fn(),
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { migrateStorage } = require('./helpers') as typeof import('./helpers');
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ton = require('../chains/ton') as typeof import('../chains/ton');

describe('migrateCoreWallet on the combo build', () => {
  it('migrates a legacy core wallet without creating an opposite-network twin', async () => {
    const onUpdate = jest.fn();

    await migrateStorage(onUpdate, ton);

    const accountIds = Object.keys(db.accounts ?? {});
    expect(accountIds).toEqual(['0-ton-mainnet']);
    expect(accountIds).not.toContain('0-ton-testnet');

    const update = onUpdate.mock.calls.map(([u]) => u).find((u) => u.type === 'migrateCoreApplication');
    expect(update.secondAccountId).toBeUndefined();
    expect(update.secondAddress).toBeUndefined();
  });
});
