import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { Storage } from '../storages/types';
import type { ApiNetwork } from '../types';

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_AIR_APP: false,
  IS_EXTENSION: true,
  IS_GRAM_WALLET: true,
}));
jest.mock('../storages/extension', () => ({ __esModule: true, default: {} }));

import { publicKeyToAddress } from '../chains/ton/wallet';
import { tryMigrateStorage } from '../common/helpers';
import { setEnvironment } from '../environment';
import { withStorage } from '../storages';

const WALLET_VERSIONS = ['v3R2', 'v4R2', 'W5'] as const;

function clone<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

function createMemoryStorage(seed: Record<string, unknown>) {
  const values = new Map<string, unknown>(Object.entries(clone(seed)));
  const storage: Storage = {
    getItem(name) {
      return Promise.resolve(clone(values.get(name)));
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

  return { storage, values };
}

function createTonWallet(
  network: ApiNetwork,
  version: ApiTonWalletVersion,
  publicKeyByte: number,
  index = 0,
) {
  const publicKeyBytes = new Uint8Array(32).fill(publicKeyByte);
  return {
    type: 'ton' as const,
    address: publicKeyToAddress(network, publicKeyBytes, version),
    publicKey: publicKeyByte.toString(16).padStart(2, '0').repeat(32),
    index,
    version,
    isInitialized: true,
  };
}

function create407AccountMatrix() {
  const accounts: Record<string, any> = {};

  WALLET_VERSIONS.forEach((version, index) => {
    const publicKeyByte = index + 1;
    const mnemonicEncrypted = `cipher-${version}`;
    accounts[`${index}-ton-mainnet`] = {
      type: 'ton',
      mnemonicEncrypted,
      ton: createTonWallet('mainnet', version, publicKeyByte),
    };
    accounts[`${index}-ton-testnet`] = {
      type: 'ton',
      mnemonicEncrypted,
      ton: createTonWallet('testnet', version, publicKeyByte),
    };
  });

  accounts['3-ton-mainnet'] = {
    type: 'ledger',
    ton: createTonWallet('mainnet', 'v3R2', 4, 3),
    driver: 'HID',
    deviceId: 'synthetic-ledger-hid',
    deviceName: 'Synthetic HID Ledger',
  };
  accounts['4-ton-testnet'] = {
    type: 'ledger',
    ton: createTonWallet('testnet', 'v4R2', 5, 4),
    driver: 'USB',
    deviceId: 'synthetic-ledger-usb',
    deviceName: 'Synthetic USB Ledger',
  };
  accounts['5-ton-mainnet'] = {
    type: 'view',
    ton: createTonWallet('mainnet', 'v3R2', 6),
  };
  accounts['6-ton-testnet'] = {
    type: 'view',
    ton: createTonWallet('testnet', 'v4R2', 7),
  };
  accounts['7-ton-mainnet'] = {
    type: 'view',
    ton: {
      ...createTonWallet('mainnet', 'W5', 8),
      publicKey: undefined,
      isInitialized: false,
    },
  };
  return accounts;
}

it('preserves every published 4.0.7 account shape through the current storage migrations', async () => {
  setEnvironment({});
  const oldAccounts = create407AccountMatrix();
  const { storage, values } = createMemoryStorage({ stateVersion: 19, accounts: oldAccounts });

  await withStorage(storage, () => tryMigrateStorage(jest.fn()));

  expect(values.get('stateVersion')).toBe(23);
  const accounts = values.get('accounts') as Record<string, any>;
  expect(Object.keys(accounts)).toEqual(Object.keys(oldAccounts));

  for (const [accountId, oldAccount] of Object.entries(oldAccounts)) {
    const { ton: { type: _chainType, ...ton }, ...account } = oldAccount;
    expect(accounts[accountId]).toEqual({ ...account, byChain: { ton } });
  }
});
