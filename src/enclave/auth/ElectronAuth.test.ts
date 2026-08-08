import type { SimpleStorage, StorageKey, StorageValue } from '../types';

import ElectronAuth from './ElectronAuth';

function createMemoryStorage(): SimpleStorage {
  const map = new Map<string, StorageValue>();

  return {
    getItem: (name) => Promise.resolve(map.get(name)),
    setItem: (name, value) => {
      map.set(name, value);
      return Promise.resolve();
    },
    removeItem: (name) => {
      map.delete(name);
      return Promise.resolve();
    },
    clear: () => {
      map.clear();
      return Promise.resolve();
    },
    getAllKeys: () => Promise.resolve([...map.keys()] as StorageKey[]),
  };
}

function mockElectron(api: Partial<NonNullable<typeof window.electron>>) {
  window.electron = api as NonNullable<typeof window.electron>;
}

describe('ElectronAuth', () => {
  afterEach(() => {
    window.electron = undefined;
  });

  it('sets up in shells exposing only `getIsTouchIdSupported`', async () => {
    const encryptPassword = jest.fn((password: string) => Promise.resolve(`encrypted:${password}`));
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(true),
      encryptPassword,
    });

    const storage = createMemoryStorage();
    const session = await new ElectronAuth(storage).setup();

    expect(session.token).toMatch(/^biometric:/);
    expect(encryptPassword).toHaveBeenCalledTimes(1);
    expect(await storage.getItem('ElectronAuth:encryptedKeyMaterial')).toBeDefined();
  });

  it('refuses to set up where encryption is available but Touch ID is not', async () => {
    mockElectron({
      getIsEncryptionSupported: () => Promise.resolve(true),
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword: () => Promise.reject(new Error('must not be called')),
    });

    await expect(new ElectronAuth(createMemoryStorage()).setup())
      .rejects.toThrow('ElectronAuth: encryption is not supported');
  });

  it('refuses to set up when the shell supports no encryption', async () => {
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword: () => Promise.reject(new Error('must not be called')),
    });

    await expect(new ElectronAuth(createMemoryStorage()).setup())
      .rejects.toThrow('ElectronAuth: encryption is not supported');
  });
});
