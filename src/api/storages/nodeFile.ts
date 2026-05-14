import { homedir } from 'node:os';

import type { NodeFileStorageConfig, Storage, StorageKey } from './types';

import { createLockedJsonFileStore } from '../../util/lockedJsonFile';

const HEADLESS_STORAGE_DIR_NAME = 'mywallet';
const HEADLESS_STORAGE_FILE_NAME = 'storage.json';
const BIGINT_STORAGE_TAG = '__mtw_bigint';
const UINT8_ARRAY_STORAGE_TAG = '__mtw_uint8array';

export function createNodeFileStorage(config: NodeFileStorageConfig): Storage {
  const filePath = resolveStorageFilePath(config);
  const fileStore = createLockedJsonFileStore<Record<string, any>>({
    filePath,
    replaceValue: replaceStorageValue,
    reviveValue: reviveStorageValue,
  });

  return {
    async getItem(name: StorageKey) {
      const data = await fileStore.read();
      return data[name];
    },
    async setItem(name: StorageKey, value: any) {
      await fileStore.mutate((data) => {
        data[name] = value;
      });
    },
    async mutateItem(name: StorageKey, mutate: (currentValue: any) => any) {
      return fileStore.mutate((data) => {
        const nextValue = mutate(data[name]);
        data[name] = nextValue;
        return nextValue;
      });
    },
    async removeItem(name: StorageKey) {
      await fileStore.mutate((data) => {
        delete data[name];
      });
    },
    async clear() {
      await fileStore.mutate((data) => {
        for (const key of Object.keys(data)) {
          delete data[key];
        }
      });
    },
    async getAll() {
      return fileStore.read();
    },
    async setMany(items) {
      await fileStore.mutate((data) => {
        Object.assign(data, items);
      });
    },
    async getMany(keys) {
      const data = await fileStore.read();

      return Object.fromEntries(keys.map((key) => [key, data[key]]));
    },
  };
}

export function resolveDefaultNodeFileStoragePath(profile = HEADLESS_STORAGE_DIR_NAME) {
  return joinFilePath(homedir(), `.${HEADLESS_STORAGE_DIR_NAME}`, profile, HEADLESS_STORAGE_FILE_NAME);
}

function resolveStorageFilePath(config: NodeFileStorageConfig) {
  if (config.path) {
    return resolveFilePath(expandNodeFileStoragePath(config.path));
  }

  if (config.profile) {
    return resolveDefaultNodeFileStoragePath(config.profile);
  }

  throw new Error('Node file storage requires an explicit `path` or `profile`');
}

function expandNodeFileStoragePath(filePath: string) {
  return filePath.replace(/\$\{HOME\}/g, homedir());
}

function replaceStorageValue(_key: string, value: unknown) {
  if (typeof value === 'bigint') {
    return {
      [BIGINT_STORAGE_TAG]: value.toString(),
    };
  }

  if (value instanceof Uint8Array) {
    return {
      [UINT8_ARRAY_STORAGE_TAG]: Array.from(value),
    };
  }

  return value;
}

function reviveStorageValue(_key: string, value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value;
  }

  if (BIGINT_STORAGE_TAG in value) {
    return BigInt((value as Record<string, string>)[BIGINT_STORAGE_TAG]);
  }

  if (UINT8_ARRAY_STORAGE_TAG in value) {
    return new Uint8Array((value as Record<string, number[]>)[UINT8_ARRAY_STORAGE_TAG]);
  }

  return value;
}

function joinFilePath(...parts: string[]) {
  const separator = parts.some((part) => part.includes('\\')) ? '\\' : '/';
  const [firstPart = '', ...restParts] = parts.filter(Boolean);

  if (!firstPart) {
    return '';
  }

  const normalizedFirstPart = firstPart === '/' || firstPart === '\\'
    ? firstPart
    : firstPart.replace(/[\\/]+$/, '');
  const normalizedRestParts = restParts
    .map((part) => part.replace(/^[\\/]+|[\\/]+$/g, ''))
    .filter(Boolean);

  if (!normalizedRestParts.length) {
    return normalizedFirstPart;
  }

  const base = normalizedFirstPart.endsWith(separator)
    ? normalizedFirstPart.slice(0, -1)
    : normalizedFirstPart;

  return `${base}${separator}${normalizedRestParts.join(separator)}`;
}

function resolveFilePath(filePath: string) {
  if (isAbsolutePath(filePath)) {
    return filePath;
  }

  return joinFilePath(process.cwd(), filePath);
}

function isAbsolutePath(filePath: string) {
  return filePath.startsWith('/') || filePath.startsWith('\\') || /^[a-zA-Z]:[\\/]/.test(filePath);
}
