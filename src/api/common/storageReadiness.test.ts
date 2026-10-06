import type { Storage } from '../storages/types';

import { withStorage } from '../storages';
import { actualStateVersion } from './helpers';
import { isStorageMigrationReady } from './storageReadiness';

function createMemoryStorage(seed: Record<string, unknown>) {
  const values = new Map(Object.entries(seed));
  const instance: Storage = {
    getItem: jest.fn((key) => Promise.resolve(values.get(key))),
    getMany: jest.fn((keys) => Promise.resolve(Object.fromEntries(keys.map((key) => [key, values.get(key)])))),
    setItem: jest.fn(),
    removeItem: jest.fn(),
    clear: jest.fn(),
  };

  return instance;
}

it.each([
  ['current profile', { stateVersion: actualStateVersion }, true],
  ['outdated schema', { stateVersion: actualStateVersion - 1 }, false],
  ['new empty store', {}, false],
  ['incomplete flat migration', { stateVersion: actualStateVersion, address: 'legacy' }, false],
  ['converted flat migration pending UI handoff', {
    stateVersion: actualStateVersion, legacyCoreAccountsConverted: true,
  }, false],
  ['completed flat migration', {
    stateVersion: actualStateVersion, address: 'legacy', legacyCoreMigrationCompleted: true,
  }, true],
])('checks %s without writing', async (_label, seed, expected) => {
  const storage = createMemoryStorage(seed);

  await expect(withStorage(storage, isStorageMigrationReady)).resolves.toBe(expected);
  expect(storage.setItem).not.toHaveBeenCalled();
  expect(storage.removeItem).not.toHaveBeenCalled();
  expect(storage.clear).not.toHaveBeenCalled();
});

it('fails closed on a storage read error without writing', async () => {
  const storage = createMemoryStorage({ stateVersion: actualStateVersion });
  jest.mocked(storage.getMany!).mockRejectedValueOnce(new Error('read failed'));

  await expect(withStorage(storage, isStorageMigrationReady)).resolves.toBe(false);
  expect(storage.setItem).not.toHaveBeenCalled();
  expect(storage.removeItem).not.toHaveBeenCalled();
  expect(storage.clear).not.toHaveBeenCalled();
});
