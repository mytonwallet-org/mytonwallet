import type { ApiAccountAny } from '../types';

jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
  },
}));

// Force the combo flavor (Core identity, features unlocked) so `purgeCoreTwins` runs its purge instead of gating out.
jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_CORE_WALLET: true,
  IS_FEATURE_LIMITED: false,
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { storage } = require('../storages') as {
  storage: { getItem: jest.Mock; setItem: jest.Mock };
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { findRemovableTwinIds, purgeCoreTwins } = require('./coreTwins') as typeof import('./coreTwins');

type TonAccountExtra = Partial<{ type: 'ton' | 'bip39'; mnemonicEncrypted: string }>;

function tonAccount(publicKey: string, extra?: TonAccountExtra): ApiAccountAny {
  return {
    type: extra?.type ?? 'ton',
    mnemonicEncrypted: extra?.mnemonicEncrypted ?? `enc-${publicKey}`,
    byChain: { ton: { address: `addr-${publicKey}`, publicKey, index: 0, version: 'v4R2' } },
  } as ApiAccountAny;
}

function multiChainAccount(tonPublicKey: string, ethereumPublicKey: string): ApiAccountAny {
  return {
    type: 'bip39',
    mnemonicEncrypted: `enc-${tonPublicKey}`,
    byChain: {
      ton: { address: `addr-${tonPublicKey}`, publicKey: tonPublicKey, index: 0, version: 'v4R2' },
      ethereum: { address: `addr-${ethereumPublicKey}`, publicKey: ethereumPublicKey, index: 0 },
    },
  } as ApiAccountAny;
}

function ledgerAccount(publicKey: string): ApiAccountAny {
  return {
    type: 'ledger',
    driver: 'HID',
    byChain: { ton: { address: `addr-${publicKey}`, publicKey, index: 0, version: 'v4R2' } },
  } as unknown as ApiAccountAny;
}

function viewAccount(publicKey: string): ApiAccountAny {
  return {
    type: 'view',
    byChain: { ton: { address: `addr-${publicKey}`, publicKey, index: 0, version: 'v4R2' } },
  } as unknown as ApiAccountAny;
}

describe('findRemovableTwinIds', () => {
  it('removes the testnet twin when the user is on mainnet', () => {
    const accounts = { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual(['0-ton-testnet']);
  });

  it('removes the mainnet mirror when the primary wallet lives on testnet (Trap #1)', () => {
    const accounts = { '0-ton-testnet': tonAccount('P'), '0-ton-mainnet': tonAccount('P') };
    expect(findRemovableTwinIds(accounts, 'testnet')).toEqual(['0-ton-mainnet']);
  });

  it('never removes the current account itself', () => {
    const accounts = { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') };
    const removed = findRemovableTwinIds(accounts, 'mainnet');
    expect(removed).not.toContain('0-ton-mainnet');
  });

  it('leaves a deliberate sub-wallet on the other network alone (Trap #2)', () => {
    const accounts = {
      '0-ton-mainnet': tonAccount('P'),
      '0-ton-testnet': tonAccount('P'), // twin of the mainnet wallet
      '1-ton-testnet': tonAccount('Q'), // deliberate sub-wallet, different key
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual(['0-ton-testnet']);
  });

  it('matches by public key, not by ciphertext (survives decoupled encryption)', () => {
    const accounts = {
      '0-ton-mainnet': tonAccount('P', { mnemonicEncrypted: 'salt-A' }),
      '0-ton-testnet': tonAccount('P', { mnemonicEncrypted: 'salt-B' }), // same key, re-encrypted separately
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual(['0-ton-testnet']);
  });

  it('ignores ledger and view accounts (no mnemonic to mirror)', () => {
    const accounts = {
      '0-ton-mainnet': tonAccount('P'),
      '0-ton-testnet': ledgerAccount('P'),
      '1-ton-mainnet': viewAccount('R'),
      '1-ton-testnet': viewAccount('R'),
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual([]);
  });

  it('does not remove a lone other-network wallet with no current-network sibling', () => {
    const accounts = { '0-ton-testnet': tonAccount('P') };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual([]);
  });

  it('returns nothing when every account is on the current network', () => {
    const accounts = { '0-ton-mainnet': tonAccount('P'), '1-ton-mainnet': tonAccount('Q') };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual([]);
  });

  it('does not remove a multi-chain account whose non-TON key is not mirrored on the current network', () => {
    // Funds-loss regression: the candidate holds an ethereum key that the current-network sibling lacks —
    // removing it would lose the ethereum key (and the seed) irrecoverably, so it must stay.
    const accounts = {
      '0-ton-mainnet': tonAccount('P'),
      '0-ton-testnet': multiChainAccount('P', 'E'),
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual([]);
  });

  it('removes a multi-chain twin when every key is mirrored on the current network', () => {
    const accounts = {
      '0-ton-mainnet': multiChainAccount('P', 'E'),
      '0-ton-testnet': multiChainAccount('P', 'E'),
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual(['0-ton-testnet']);
  });

  it('requires a single sibling to cover all keys, not a union across siblings', () => {
    // Keys scattered across two current-network accounts do not prove the candidate's seed survives whole.
    const accounts = {
      '0-ton-mainnet': tonAccount('P'),
      '1-ton-mainnet': multiChainAccount('X', 'E'),
      '0-ton-testnet': multiChainAccount('P', 'E'),
    };
    expect(findRemovableTwinIds(accounts, 'mainnet')).toEqual([]);
  });
});

describe('purgeCoreTwins', () => {
  function wireStorage(db: Record<string, any>) {
    storage.getItem.mockImplementation((key: string) => db[key]);
    storage.setItem.mockImplementation((key: string, value: any) => {
      db[key] = value;
    });
    return db;
  }

  beforeEach(() => jest.clearAllMocks());

  it('purges twins from accounts and dapps storage, keeps the mainnet member and emits removeAccounts', async () => {
    const db = wireStorage({
      accounts: { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') },
      dapps: { '0-ton-mainnet': { d: 1 }, '0-ton-testnet': { d: 2 } },
    });
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);

    expect(Object.keys(db.accounts)).toEqual(['0-ton-mainnet']);
    expect(Object.keys(db.dapps)).toEqual(['0-ton-mainnet']);
    expect(onUpdate).toHaveBeenCalledWith({ type: 'removeAccounts', accountIds: ['0-ton-testnet'] });
  });

  it('always keeps mainnet even for a testnet-parked user (never reads currentAccountId)', async () => {
    // The user closed the tab while parked on testnet — the mainnet member still holds the real funds and must
    // survive. `currentAccountId` points at testnet on purpose: the purge must not consult it.
    const db = wireStorage({
      currentAccountId: '0-ton-testnet',
      accounts: { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') },
    });
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);

    expect(Object.keys(db.accounts)).toEqual(['0-ton-mainnet']);
    expect(onUpdate).toHaveBeenCalledWith({ type: 'removeAccounts', accountIds: ['0-ton-testnet'] });
    expect(storage.getItem).not.toHaveBeenCalledWith('currentAccountId');
  });

  it('sets the coreTwinsPurged marker after a successful pass', async () => {
    const db = wireStorage({
      accounts: { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') },
    });

    await purgeCoreTwins(jest.fn());

    expect(db.coreTwinsPurged).toBe(true);
  });

  it('is idempotent via the marker - a second call returns early without touching storage', async () => {
    wireStorage({
      accounts: { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') },
    });
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);
    onUpdate.mockClear();
    storage.setItem.mockClear();

    await purgeCoreTwins(onUpdate);

    expect(storage.setItem).not.toHaveBeenCalled();
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('does not rewrite storage when there are no twins but still sets the marker', async () => {
    const db = wireStorage({
      accounts: { '0-ton-mainnet': tonAccount('P'), '1-ton-mainnet': tonAccount('Q') },
    });
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);

    expect(Object.keys(db.accounts)).toEqual(['0-ton-mainnet', '1-ton-mainnet']);
    expect(storage.setItem).toHaveBeenCalledTimes(1);
    expect(storage.setItem).toHaveBeenCalledWith('coreTwinsPurged', true);
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('does nothing when there are no stored accounts but still sets the marker', async () => {
    const db = wireStorage({});
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);

    expect(onUpdate).not.toHaveBeenCalled();
    expect(db.coreTwinsPurged).toBe(true);
  });
});
