import { createStore, del, get, set } from 'idb-keyval';

import { INDEXED_DB_NAME, INDEXED_DB_STORE_NAME } from '../../config';

const store = createStore(INDEXED_DB_NAME, INDEXED_DB_STORE_NAME);

export default {
  getItem: <T>(key: string) => get<T>(key, store),
  setItem: (key: string, value: unknown) => set(key, value, store),
  removeItem: (key: string) => del(key, store),
};
