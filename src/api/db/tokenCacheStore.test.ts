const EXAMPLE_TOKEN = {
  name: 'Example Token',
  symbol: 'EXT',
  slug: 'ton-ext',
  decimals: 9,
  chain: 'ton',
  priceUsd: 1,
  percentChange24h: 0,
} as const;

describe('tokenCacheStore', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
    delete (globalThis as Record<string, unknown>).indexedDB;
  });

  it('returns empty results and no-ops when indexedDB is unavailable', async () => {
    const { tokenCacheStore } = await import('./tokenCacheStore');

    await expect(tokenCacheStore.getAll()).resolves.toEqual([]);
    await expect(tokenCacheStore.bulkPut([EXAMPLE_TOKEN])).resolves.toBeUndefined();
    await expect(tokenCacheStore.clear()).resolves.toBeUndefined();
  });

  it('delegates lazily to the browser token repository when indexedDB exists', async () => {
    const getAll = jest.fn().mockResolvedValue([EXAMPLE_TOKEN]);
    const bulkPut = jest.fn().mockResolvedValue(undefined);
    const clear = jest.fn().mockResolvedValue(undefined);

    (globalThis as Record<string, unknown>).indexedDB = {};
    jest.doMock('./index', () => ({
      tokenRepository: {
        all: getAll,
        bulkPut,
        clear,
      },
    }));

    const { tokenCacheStore } = await import('./tokenCacheStore');

    await expect(tokenCacheStore.getAll()).resolves.toEqual([EXAMPLE_TOKEN]);
    await expect(tokenCacheStore.bulkPut([EXAMPLE_TOKEN])).resolves.toBeUndefined();
    await expect(tokenCacheStore.clear()).resolves.toBeUndefined();

    expect(getAll).toHaveBeenCalledTimes(1);
    expect(bulkPut).toHaveBeenCalledWith([EXAMPLE_TOKEN]);
    expect(clear).toHaveBeenCalledTimes(1);
  });
});
