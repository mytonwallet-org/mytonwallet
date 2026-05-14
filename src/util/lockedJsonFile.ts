import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';

const LOCK_DIR_SUFFIX = '.lock';
const LOCK_METADATA_FILE_NAME = 'owner.json';
const LOCK_STALE_MS = 30_000;
const LOCK_RETRY_DELAY_MS = 50;
const LOCK_MAX_ATTEMPTS = 200;

interface LockedJsonFileStoreOptions {
  filePath: string;
  replaceValue?(key: string, value: unknown): unknown;
  reviveValue?(key: string, value: unknown): unknown;
}

export interface LockedJsonFileStore<T extends Record<string, any>> {
  read(): Promise<T>;
  mutate<TResult>(callback: (data: T) => TResult | Promise<TResult>): Promise<TResult>;
}

export function createLockedJsonFileStore<T extends Record<string, any>>(
  options: LockedJsonFileStoreOptions,
): LockedJsonFileStore<T> {
  let operationPromise = Promise.resolve();

  return {
    async read() {
      return readJsonFile<T>(options.filePath, options.reviveValue);
    },
    mutate<TResult>(callback: (data: T) => TResult | Promise<TResult>) {
      return enqueueOperation(async () => {
        const releaseLock = await acquireFileLock(options.filePath);

        try {
          const data = await readJsonFile<T>(options.filePath, options.reviveValue);
          const result = await callback(data);

          await writeJsonFile(options.filePath, data, options.replaceValue);

          return result;
        } finally {
          await releaseLock();
        }
      });
    },
  };

  function enqueueOperation<TResult>(callback: () => Promise<TResult>) {
    const nextPromise = operationPromise.then(callback, callback);

    operationPromise = nextPromise.then(() => undefined, () => undefined);

    return nextPromise;
  }
}

async function acquireFileLock(filePath: string) {
  const lockDirPath = `${filePath}${LOCK_DIR_SUFFIX}`;
  const lockMetadata = JSON.stringify({
    pid: process.pid,
    createdAt: Date.now(),
  });

  await mkdir(dirnamePath(filePath), { recursive: true });

  for (let attempt = 1; attempt <= LOCK_MAX_ATTEMPTS; attempt += 1) {
    try {
      await mkdir(lockDirPath);
      await writeFile(joinFilePath(lockDirPath, LOCK_METADATA_FILE_NAME), lockMetadata, 'utf8');

      return async () => {
        try {
          await rm(lockDirPath, { recursive: true, force: true });
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

      if (await isStaleLock(lockDirPath)) {
        await rm(lockDirPath, { recursive: true, force: true });
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

async function isStaleLock(lockDirPath: string) {
  try {
    const lockStat = await stat(lockDirPath);
    return Date.now() - lockStat.mtimeMs >= LOCK_STALE_MS;
  } catch (err: any) {
    if (err?.code === 'ENOENT') {
      return false;
    }

    throw err;
  }
}

function wait(ms: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function readJsonFile<T extends Record<string, any>>(
  filePath: string,
  reviveValue?: (key: string, value: unknown) => unknown,
): Promise<T> {
  try {
    const content = await readFile(filePath, 'utf8');
    return JSON.parse(content, reviveValue) as T;
  } catch (err: any) {
    if (err?.code === 'ENOENT') {
      return {} as T;
    }

    throw err;
  }
}

async function writeJsonFile(
  filePath: string,
  data: Record<string, any>,
  replaceValue?: (key: string, value: unknown) => unknown,
) {
  await mkdir(dirnamePath(filePath), { recursive: true });

  const tempFilePath = `${filePath}.${process.pid}.${randomUUID()}.tmp`;
  const content = JSON.stringify(data, replaceValue);

  await writeFile(tempFilePath, content, 'utf8');
  await rename(tempFilePath, filePath);
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

function dirnamePath(filePath: string) {
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
