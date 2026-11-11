import type { ApiPerpsGetAssetsResult, OnApiUpdate } from '../types';

const mockStore = new Map<string, unknown>();
const mockCallBackendGet = jest.fn();

jest.mock('idb-keyval', () => ({
  createStore: () => jest.fn(),
  get: (key: string) => Promise.resolve(mockStore.get(key)),
  set: (key: string, value: unknown) => {
    mockStore.set(key, value);
    return Promise.resolve();
  },
}));

jest.mock('./backend', () => ({
  callBackendGet: (...args: unknown[]) => mockCallBackendGet(...args),
}));

const CATALOGUE = {
  assetsByChain: {
    hyperliquid: [{
      id: 'hyperliquid:hl:BTC',
      index: 0,
      name: 'BTC',
      chain: 'hyperliquid',
      provider: 'hyperliquid',
      dex: '',
      symbol: 'BTC',
      szDecimals: 5,
      maxLeverage: 40,
      context: {
        funding: '0.0001',
        openInterest: '1',
        prevDayPx: '1',
        dayNtlVlm: '1',
        premium: '0',
        oraclePx: '1',
        markPx: '1',
        midPx: '1',
        dayBaseVlm: '1',
      },
    }],
  },
  sections: [],
  limitsByChain: {
    hyperliquid: { minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '0.2', minPositionMarginUsdc: '10' },
  },
} as unknown as ApiPerpsGetAssetsResult;

beforeEach(() => {
  mockStore.clear();
  mockCallBackendGet.mockReset();
  jest.resetModules();
});

test.each([
  ['sections', { ...CATALOGUE, sections: undefined }],
  ['limits', { ...CATALOGUE, limitsByChain: {} }],
])('does not restore a stored catalogue without %s', async (_, result) => {
  mockStore.set('perpsAssets', { langCode: 'en', fetchedAt: 1, result });
  mockCallBackendGet.mockResolvedValue(CATALOGUE);
  const { getPerpsAssets, loadPerpsAssetsCache } = await loadCacheModule();

  await loadPerpsAssetsCache();

  await expect(getPerpsAssets('en')).resolves.toEqual(CATALOGUE);
  expect(mockCallBackendGet).toHaveBeenCalledTimes(1);
});

test('serves the catalogue from cache until a refresh replaces it', async () => {
  const { getPerpsAssets, refreshPerpsAssets, setPerpsAssetsUpdater } = await loadCacheModule();
  const updates: unknown[] = [];
  setPerpsAssetsUpdater(((update) => {
    updates.push(update);
  }) as OnApiUpdate);
  mockCallBackendGet.mockResolvedValue(CATALOGUE);

  const first = await getPerpsAssets('en');
  const second = await getPerpsAssets('en');

  expect(second).toBe(first);
  expect(mockCallBackendGet).toHaveBeenCalledTimes(1);

  const next = { ...CATALOGUE, sections: [] };
  mockCallBackendGet.mockResolvedValueOnce(next);
  await expect(refreshPerpsAssets('en')).resolves.toBe(next);
  await expect(getPerpsAssets('en')).resolves.toBe(next);
  expect(mockCallBackendGet).toHaveBeenCalledTimes(2);
  expect(mockCallBackendGet).toHaveBeenLastCalledWith('/perps/assets', { langCode: 'en' });
  expect(updates).toHaveLength(2);
});

test('a catalogue stored for another language is fetched again', async () => {
  const { getPerpsAssets } = await loadCacheModule();
  mockCallBackendGet.mockResolvedValue(CATALOGUE);

  await getPerpsAssets('en');
  await getPerpsAssets('ru');

  expect(mockCallBackendGet).toHaveBeenCalledTimes(2);
  expect(mockCallBackendGet).toHaveBeenLastCalledWith('/perps/assets', { langCode: 'ru' });
});

test('restores the catalogue and its original freshness from storage before the next request', async () => {
  mockStore.set('perpsAssets', { langCode: 'en', fetchedAt: 10, result: CATALOGUE });
  const {
    getPerpsAssets, getPerpsAssetsFetchedAt, loadPerpsAssetsCache, setPerpsAssetsUpdater,
  } = await loadCacheModule();
  const updates: unknown[] = [];
  setPerpsAssetsUpdater((update) => {
    updates.push(update);
  });
  await loadPerpsAssetsCache();

  await expect(getPerpsAssets('en')).resolves.toEqual(CATALOGUE);
  expect(getPerpsAssetsFetchedAt(CATALOGUE, 'en')).toBe(10);
  expect(getPerpsAssetsFetchedAt(CATALOGUE, 'ru')).toBe(0);
  expect(mockCallBackendGet).not.toHaveBeenCalled();
  expect(updates).toEqual([{
    type: 'updatePerpsAssets',
    assets: CATALOGUE,
    langCode: 'en',
    fetchedAt: 10,
  }]);
});

test('freshness belongs to the exact cached response, not an older response from a concurrent request', async () => {
  const { getPerpsAssets, getPerpsAssetsFetchedAt, refreshPerpsAssets } = await loadCacheModule();
  mockCallBackendGet.mockResolvedValueOnce(CATALOGUE);
  const first = await getPerpsAssets('en');
  const firstFetchedAt = getPerpsAssetsFetchedAt(first, 'en');
  expect(firstFetchedAt).toBeGreaterThan(0);

  const next = { ...CATALOGUE, sections: [] };
  mockCallBackendGet.mockResolvedValueOnce(next);
  await refreshPerpsAssets('en');
  expect(getPerpsAssetsFetchedAt(first, 'en')).toBe(0);
  expect(getPerpsAssetsFetchedAt(next, 'en')).toBeGreaterThanOrEqual(firstFetchedAt);
});

async function loadCacheModule() {
  return import('./perpsAssets');
}
