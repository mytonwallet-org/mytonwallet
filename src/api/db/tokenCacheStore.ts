import type { ApiTokenWithPrice } from '../types';

export interface TokenCacheStore {
  getAll(): Promise<ApiTokenWithPrice[]>;
  bulkPut(items: ApiTokenWithPrice[]): Promise<void>;
  clear(): Promise<void>;
}

const IS_INDEXED_DB_AVAILABLE = typeof indexedDB !== 'undefined';
let browserTokenCacheStorePromise: Promise<TokenCacheStore> | undefined;

function loadBrowserTokenCacheStore() {
  if (!browserTokenCacheStorePromise) {
    browserTokenCacheStorePromise = import('./index').then(({ tokenRepository }) => ({
      getAll: () => tokenRepository.all(),
      bulkPut: (items) => tokenRepository.bulkPut(items),
      clear: () => tokenRepository.clear(),
    }));
  }

  return browserTokenCacheStorePromise;
}

export const tokenCacheStore: TokenCacheStore = {
  async getAll() {
    if (!IS_INDEXED_DB_AVAILABLE) {
      return [];
    }

    return (await loadBrowserTokenCacheStore()).getAll();
  },
  async bulkPut(items) {
    if (!IS_INDEXED_DB_AVAILABLE) {
      return;
    }

    const browserTokenCacheStore = await loadBrowserTokenCacheStore();
    await browserTokenCacheStore.bulkPut(items);
  },
  async clear() {
    if (!IS_INDEXED_DB_AVAILABLE) {
      return;
    }

    const browserTokenCacheStore = await loadBrowserTokenCacheStore();
    await browserTokenCacheStore.clear();
  },
};
