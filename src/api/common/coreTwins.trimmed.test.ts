import type { ApiAccountAny } from '../types';

jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
  },
}));

// Force the TRIMMED core flavor: it keeps the cross-network twins on purpose (no network switcher, wipe-both logout),
// so `purgeCoreTwins` must gate out entirely — and must NOT set the `coreTwinsPurged` marker, or the eventual combo
// boot over the same storage would skip the purge and resurrect the logout-leaves-mnemonic bug.
jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_CORE_WALLET: true,
  IS_FEATURE_LIMITED: true,
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { storage } = require('../storages') as {
  storage: { getItem: jest.Mock; setItem: jest.Mock };
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { purgeCoreTwins } = require('./coreTwins') as typeof import('./coreTwins');

function tonAccount(publicKey: string): ApiAccountAny {
  return {
    type: 'ton',
    mnemonicEncrypted: `enc-${publicKey}`,
    byChain: { ton: { address: `addr-${publicKey}`, publicKey, index: 0, version: 'v4R2' } },
  } as ApiAccountAny;
}

describe('purgeCoreTwins on the trimmed core build', () => {
  beforeEach(() => jest.clearAllMocks());

  it('returns early without purging and without setting the marker', async () => {
    const db: Record<string, any> = {
      accounts: { '0-ton-mainnet': tonAccount('P'), '0-ton-testnet': tonAccount('P') },
    };
    storage.getItem.mockImplementation((key: string) => db[key]);
    storage.setItem.mockImplementation((key: string, value: any) => {
      db[key] = value;
    });
    const onUpdate = jest.fn();

    await purgeCoreTwins(onUpdate);

    expect(storage.getItem).not.toHaveBeenCalled();
    expect(storage.setItem).not.toHaveBeenCalled();
    expect(onUpdate).not.toHaveBeenCalled();
    expect(Object.keys(db.accounts)).toEqual(['0-ton-mainnet', '0-ton-testnet']);
    expect(db.coreTwinsPurged).toBeUndefined();
  });
});
