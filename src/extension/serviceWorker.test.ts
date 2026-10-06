jest.mock('../api/providers/extension/providerForPopup', () => ({}));
jest.mock('../api/providers/extension/providerForContentScript', () => ({}));
jest.mock('../config', () => ({
  ...jest.requireActual('../config'), IS_EXTENSION: true, IS_AIR_APP: false,
}));
jest.mock('../api/storages/extension', () => ({
  __esModule: true,
  default: { getItem: jest.fn(), setItem: jest.fn(), clear: jest.fn() },
}));

it('configures extension storage before the first popup initializes the API', async () => {
  jest.resetModules();
  const previousStorageGlobals = Reflect.get(globalThis, '__mtwStorageGlobals');
  Reflect.deleteProperty(globalThis, '__mtwStorageGlobals');

  try {
    const { default: extensionStorage } = await import('../api/storages/extension');
    jest.mocked(extensionStorage.getItem).mockResolvedValue('0-ton');

    await import('./serviceWorker');

    const { storage } = await import('../api/storages');
    await expect(storage.getItem('currentAccountId')).resolves.toBe('0-ton');
    expect(extensionStorage.setItem).not.toHaveBeenCalled();
    expect(extensionStorage.clear).not.toHaveBeenCalled();
  } finally {
    if (previousStorageGlobals === undefined) {
      Reflect.deleteProperty(globalThis, '__mtwStorageGlobals');
    } else {
      Reflect.set(globalThis, '__mtwStorageGlobals', previousStorageGlobals);
    }
  }
});
