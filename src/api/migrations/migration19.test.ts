import type { Storage } from '../storages/types';

import { withStorage } from '../storages';
import { start } from './00019';

function clone<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

function createMemoryStorage(seed: Record<string, unknown>) {
  const values = new Map(Object.entries(clone(seed)));
  const storage: Storage = {
    getItem: (name) => Promise.resolve(clone(values.get(name))),
    setItem: (name, value) => Promise.resolve(values.set(name, clone(value))).then(() => undefined),
    removeItem: (name) => Promise.resolve(values.delete(name)).then(() => undefined),
    clear: () => Promise.resolve(values.clear()),
  };

  return { storage, values };
}

it('keeps an already migrated byChain record intact when migration 19 runs again', async () => {
  const accounts = {
    '0-ton-mainnet': {
      type: 'ton',
      mnemonicEncrypted: 'cipher',
      byChain: {
        ton: { address: 'EQmain', publicKey: '11', index: 0, version: 'v3R2' },
        ethereum: { address: '0x123', publicKey: '22', index: 0 },
      },
    },
  };
  const snapshot = clone(accounts);
  const { storage, values } = createMemoryStorage({ accounts });

  await withStorage(storage, start);

  expect(values.get('accounts')).toEqual(snapshot);
  expect(accounts).toEqual(snapshot);
});

it('keeps current byChain data when a partially migrated record also has legacy fields', async () => {
  const { storage, values } = createMemoryStorage({
    accounts: {
      '0-ton-mainnet': {
        type: 'ton',
        mnemonicEncrypted: 'cipher',
        ton: { type: 'ton', address: 'EQlegacy', publicKey: '11', index: 0, version: 'v3R2' },
        byChain: {
          ton: { address: 'EQcurrent', publicKey: '11', index: 0, version: 'v3R2' },
        },
      },
    },
  });

  await withStorage(storage, start);

  expect(values.get('accounts')).toEqual({
    '0-ton-mainnet': {
      type: 'ton',
      mnemonicEncrypted: 'cipher',
      byChain: {
        ton: { address: 'EQcurrent', publicKey: '11', index: 0, version: 'v3R2' },
      },
    },
  });
});
