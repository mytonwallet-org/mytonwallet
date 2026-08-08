import * as idb from 'idb-keyval';

import type { SimpleStorage, StorageKey } from '../types';

const INDEXED_DB_NAME = 'enclave';
const INDEXED_DB_STORE_NAME = 'enclave';

// TODO `idb` → `LocalStorage`
const storage = idb.createStore(INDEXED_DB_NAME, INDEXED_DB_STORE_NAME);

export default {
  getItem: (name: StorageKey) => idb.get(name, storage),
  setItem: (name: StorageKey, value: any) => idb.set(name, value, storage),
  removeItem: (name: StorageKey) => idb.del(name, storage),
  clear: () => idb.clear(storage),
  getAllKeys: () => idb.keys(storage),
} as SimpleStorage;
