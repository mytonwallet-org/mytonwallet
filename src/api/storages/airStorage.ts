import type { Storage, StorageKey } from './types';

import { bigintReviver } from '../../util/bigint';
import { callWindow } from '../../util/windowProvider/connector';
import { getEnvironment } from '../environment';

let cache: AnyLiteral = {};

const storage: Storage & {
  getKeys: () => Promise<string[] | undefined>;
} = {
  async getItem(key: StorageKey, force?: boolean) {
    if (getEnvironment().isAndroidApp && key in cache && !force) {
      return cache[key];
    }

    const result = await callWindow('airStorageGetItem', key);
    const value = result ? JSON.parse(result, bigintReviver) : undefined;

    if (getEnvironment().isAndroidApp) {
      if (value === undefined) {
        delete cache[key];
      } else {
        cache[key] = value;
      }
    }

    return value;
  },

  async setItem(key: StorageKey, value: any) {
    await callWindow('airStorageSetItem', key, JSON.stringify(value));

    if (getEnvironment().isAndroidApp) {
      cache[key] = value;
    }
  },

  async removeItem(key: StorageKey) {
    await callWindow('airStorageRemoveItem', key);

    if (getEnvironment().isAndroidApp) {
      delete cache[key];
    }
  },

  async clear() {
    await callWindow('airStorageClear');

    if (getEnvironment().isAndroidApp) {
      cache = {};
    }
  },

  async getKeys() {
    const result = await callWindow('airStorageKeys');

    return result?.value;
  },
};

export default storage;
