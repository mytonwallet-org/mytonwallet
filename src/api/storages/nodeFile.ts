import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';

import type { Storage, StorageKey } from './types';

type NodeFileStorageConfig = {
  path?: string;
  profile?: string;
};

const DEFAULT_STORAGE_DIRECTORY_NAME = 'mywallet';
const DEFAULT_STORAGE_FILE_NAME = 'storage.json';
const BIGINT_STORAGE_TAG = '__mtw_bigint';
const UINT8_ARRAY_STORAGE_TAG = '__mtw_uint8array';
const LOCK_DIRECTORY_SUFFIX = '.lock';
const LOCK_METADATA_FILE_NAME = 'owner.json';
const LOCK_STALE_MS = 30_000;
const LOCK_RETRY_DELAY_MS = 50;
const LOCK_MAX_ATTEMPTS = 200;

export function createNodeFileStorage(config: NodeFileStorageConfig): Storage {
  const filePath = resolveStorageFilePath(config);
  let operationPromise = Promise.resolve();

  function enqueueOperation<T>(callback: () => Promise<T>) {
    const nextPromise = operationPromise.then(callback, callback);

    operationPromise = nextPromise.then(() => undefined, () => undefined);

    return nextPromise;
  }

  return {
    async getItem(name: StorageKey) {
      const data = await readStorageFile(filePath);
      return data[name];
    },
    async setItem(name: StorageKey, value: any) {
      await enqueueOperation(async () => {
        await mutateStorageFile(filePath, (data) => {
          data[name] = value;
          return data;
        });
      });
    },
    async removeItem(name: StorageKey) {
      await enqueueOperation(async () => {
        await mutateStorageFile(filePath, (data) => {
          delete data[name];
          return data;
        });
      });
    },
    async clear() {
      await enqueueOperation(async () => {
        await mutateStorageFile(filePath, () => ({}));
      });
    },
    async getAll() {
      return readStorageFile(filePath);
    },
    async setMany(items) {
      await enqueueOperation(async () => {
        await mutateStorageFile(filePath, (data) => ({
          ...data,
          ...items,
        }));
      });
    },
    async getMany(keys) {
      const data = await readStorageFile(filePath);

      return Object.fromEntries(keys.map((key) => [key, data[key]]));
    },
  };
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

export function resolveDefaultNodeFileStoragePath(profile = DEFAULT_STORAGE_DIRECTORY_NAME) {
  return joinFilePath(homedir(), `.${DEFAULT_STORAGE_DIRECTORY_NAME}`, profile, DEFAULT_STORAGE_FILE_NAME);
}

function expandNodeFileStoragePath(filePath: string) {
  return filePath.replace(/\$\{HOME\}/g, homedir());
}

async function mutateStorageFile(
  filePath: string,
  mutate: (data: Record<string, any>) => Record<string, any>,
) {
  const releaseLock = await acquireStorageLock(filePath);

  try {
    const data = await readStorageFile(filePath);
    await writeStorageFile(filePath, mutate(data));
  } finally {
    await releaseLock();
  }
}

async function acquireStorageLock(filePath: string) {
  const lockDirectoryPath = `${filePath}${LOCK_DIRECTORY_SUFFIX}`;
  const lockMetadata = JSON.stringify({
    processId: process.pid,
    createdAt: Date.now(),
  });

  await mkdir(getDirectoryPath(filePath), { recursive: true });

  for (let attempt = 1; attempt <= LOCK_MAX_ATTEMPTS; attempt++) {
    try {
      await mkdir(lockDirectoryPath);
      await writeFile(joinFilePath(lockDirectoryPath, LOCK_METADATA_FILE_NAME), lockMetadata, 'utf8');

      return async () => {
        try {
          await rm(lockDirectoryPath, { recursive: true, force: true });
        } catch (err: any) {
          if (err?.code !== 'ENOENT') {
            throw err;
          }
        }
      };
    } catch (err: any) {
      if (err?.code !== 'EEXIST') {
        throw err;
      }

      if (await isStaleLock(lockDirectoryPath)) {
        await rm(lockDirectoryPath, { recursive: true, force: true });
        continue;
      }

      if (attempt === LOCK_MAX_ATTEMPTS) {
        throw new Error(`Timed out acquiring node-file storage lock for ${filePath}`);
      }

      await wait(LOCK_RETRY_DELAY_MS);
    }
  }

  throw new Error(`Failed to acquire node-file storage lock for ${filePath}`);
}

async function isStaleLock(lockDirectoryPath: string) {
  try {
    const lockDirectoryStat = await stat(lockDirectoryPath);
    return Date.now() - lockDirectoryStat.mtimeMs >= LOCK_STALE_MS;
  } catch (err: any) {
    if (err?.code === 'ENOENT') {
      return false;
    }

    throw err;
  }
}

function wait(delayMs: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, delayMs);
  });
}

async function readStorageFile(filePath: string) {
  try {
    const content = await readFile(filePath, 'utf8');
    return JSON.parse(content, reviveStorageValue) as Record<string, any>;
  } catch (err: any) {
    if (err?.code === 'ENOENT') {
      return {};
    }

    throw err;
  }
}

async function writeStorageFile(filePath: string, data: Record<string, any>) {
  await mkdir(getDirectoryPath(filePath), { recursive: true });

  const tempFilePath = `${filePath}.${process.pid}.${randomUUID()}.tmp`;
  const content = JSON.stringify(data, replaceStorageValue);

  await writeFile(tempFilePath, content, 'utf8');
  await rename(tempFilePath, filePath);
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

function getDirectoryPath(filePath: string) {
  const normalizedPath = filePath.replace(/[\\/]+$/, '');
  const lastSeparatorIndex = Math.max(normalizedPath.lastIndexOf('/'), normalizedPath.lastIndexOf('\\'));

  if (lastSeparatorIndex < 0) {
    return '.';
  }

  if (lastSeparatorIndex === 0) {
    return normalizedPath[0];
  }

  if (lastSeparatorIndex === 2 && normalizedPath[1] === ':') {
    return normalizedPath.slice(0, 3);
  }

  return normalizedPath.slice(0, lastSeparatorIndex);
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
