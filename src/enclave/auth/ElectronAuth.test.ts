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

function mockRoundTrip() {
  return {
    encryptPassword: jest.fn((password: string) => Promise.resolve(`encrypted:${password}`)),
    decryptPassword: jest.fn((encrypted: string) => Promise.resolve(encrypted.replace(/^encrypted:/, ''))),
  };
}

describe('ElectronAuth', () => {
  afterEach(() => {
    window.electron = undefined;
  });

  it('sets up without a presence probe where Touch ID answers the prompt', async () => {
    const { encryptPassword, decryptPassword } = mockRoundTrip();
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(true),
      encryptPassword,
      decryptPassword,
    });

    const storage = createMemoryStorage();
    const session = await new ElectronAuth(storage).setup();

    expect(session.token).toMatch(/^biometric:/);
    expect(encryptPassword).toHaveBeenCalledTimes(1);
    expect(decryptPassword).not.toHaveBeenCalled();
    expect(await storage.getItem('ElectronAuth:encryptedKeyMaterial')).toBeDefined();
  });

  it('sets up on Macs without Touch ID after the presence probe passes', async () => {
    const { encryptPassword, decryptPassword } = mockRoundTrip();
    mockElectron({
      getIsEncryptionSupported: () => Promise.resolve(true),
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword,
      decryptPassword,
    });

    const storage = createMemoryStorage();
    const session = await new ElectronAuth(storage).setup();

    expect(session.token).toMatch(/^biometric:/);
    expect(decryptPassword).toHaveBeenCalledTimes(1);
    expect(await storage.getItem('ElectronAuth:encryptedKeyMaterial')).toBeDefined();
  });

  it('sets up in shells exposing only `getIsTouchIdSupported` on Macs without Touch ID', async () => {
    const { encryptPassword, decryptPassword } = mockRoundTrip();
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword,
      decryptPassword,
    });

    const session = await new ElectronAuth(createMemoryStorage()).setup();

    expect(session.token).toMatch(/^biometric:/);
    expect(encryptPassword).toHaveBeenCalledTimes(1);
    expect(decryptPassword).toHaveBeenCalledTimes(1);
  });

  it('refuses to set up when the presence probe fails, leaving no key material behind', async () => {
    const { encryptPassword } = mockRoundTrip();
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword,
      decryptPassword: () => Promise.resolve(undefined),
    });

    const storage = createMemoryStorage();
    await expect(new ElectronAuth(storage).setup())
      .rejects.toThrow('Biometric setup failed.');
    expect(await storage.getItem('ElectronAuth:encryptedKeyMaterial')).toBeUndefined();
  });

  it('refuses to set up when the shell reports encryption unavailable', async () => {
    mockElectron({
      getIsEncryptionSupported: () => Promise.resolve(false),
      getIsTouchIdSupported: () => Promise.resolve(false),
      encryptPassword: () => Promise.reject(new Error('must not be called')),
      decryptPassword: () => Promise.reject(new Error('must not be called')),
    });

    await expect(new ElectronAuth(createMemoryStorage()).setup())
      .rejects.toThrow('ElectronAuth: encryption is not supported');
  });

  it('refuses to set up when the shell exposes no `encryptPassword`', async () => {
    mockElectron({
      getIsTouchIdSupported: () => Promise.resolve(true),
    });

    await expect(new ElectronAuth(createMemoryStorage()).setup())
      .rejects.toThrow('ElectronAuth: encryption is not supported');
  });

  const storedKeyMaterial = `encrypted:${Buffer.alloc(32).toString('base64')}`;

  it('authorizes with the decrypted key material', async () => {
    const { decryptPassword } = mockRoundTrip();
    mockElectron({ decryptPassword });

    const storage = createMemoryStorage();
    await storage.setItem('ElectronAuth:encryptedKeyMaterial', storedKeyMaterial);
    const session = await new ElectronAuth(storage).authorize();

    expect(session.token).toMatch(/^biometric:/);
    expect(decryptPassword).toHaveBeenCalledWith(storedKeyMaterial);
  });

  it('reports an unconfirmed presence prompt instead of crashing', async () => {
    mockElectron({
      decryptPassword: () => Promise.resolve(undefined),
    });

    const storage = createMemoryStorage();
    await storage.setItem('ElectronAuth:encryptedKeyMaterial', storedKeyMaterial);

    await expect(new ElectronAuth(storage).authorize())
      .rejects.toThrow('ElectronAuth: user presence was not confirmed');
  });

  it('reports missing key material instead of decrypting nothing', async () => {
    const { decryptPassword } = mockRoundTrip();
    mockElectron({ decryptPassword });

    await expect(new ElectronAuth(createMemoryStorage()).authorize())
      .rejects.toThrow('ElectronAuth: no key material is stored');
    expect(decryptPassword).not.toHaveBeenCalled();
  });
});
