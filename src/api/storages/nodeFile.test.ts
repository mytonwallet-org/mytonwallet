/* eslint-disable no-template-curly-in-string */
import { mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';

jest.mock('node:fs/promises', () => ({
  mkdir: jest.fn(),
  readFile: jest.fn(),
  rename: jest.fn(),
  rm: jest.fn(),
  stat: jest.fn(),
  writeFile: jest.fn(),
}));

import { createNodeFileStorage, resolveDefaultNodeFileStoragePath } from './nodeFile';

const mkdirMock = jest.mocked(mkdir);
const readFileMock = jest.mocked(readFile);
const renameMock = jest.mocked(rename);
const rmMock = jest.mocked(rm);
const statMock = jest.mocked(stat);
const writeFileMock = jest.mocked(writeFile);

describe('node-file storage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mkdirMock.mockResolvedValue(undefined as never);
    readFileMock.mockResolvedValue('{}' as never);
    renameMock.mockResolvedValue(undefined as never);
    rmMock.mockResolvedValue(undefined as never);
    writeFileMock.mockResolvedValue(undefined as never);
    statMock.mockResolvedValue({ mtimeMs: Date.now() } as never);
  });

  it('should use unique temp files for concurrent writes to the same storage path', async () => {
    const seenRenameSources = new Set<string>();

    renameMock.mockImplementation((sourcePath: any) => {
      if (seenRenameSources.has(String(sourcePath))) {
        const error = Object.assign(new Error(`ENOENT: missing temp file ${String(sourcePath)}`), {
          code: 'ENOENT',
        });

        return Promise.reject(error);
      }

      seenRenameSources.add(String(sourcePath));
      return Promise.resolve(undefined as never);
    });

    const storageA = createNodeFileStorage({ type: 'nodeFile', path: '/tmp/headless-storage.json' });
    const storageB = createNodeFileStorage({ type: 'nodeFile', path: '/tmp/headless-storage.json' });

    await expect(Promise.all([
      storageA.setItem('accounts', { a: 1 }),
      storageB.setItem('currentAccountId', 'ton-testnet-1'),
    ])).resolves.toEqual([undefined, undefined]);

    const tempWritePaths = writeFileMock.mock.calls
      .map(([targetPath]) => `${targetPath as string}`)
      .filter((targetPath) => targetPath.endsWith('.tmp'));
    expect(tempWritePaths).toHaveLength(2);
    expect(new Set(tempWritePaths).size).toBe(2);
    expect(tempWritePaths.every((targetPath) => targetPath.startsWith('/tmp/headless-storage.json.'))).toBe(true);

    const renameSourcePaths = renameMock.mock.calls.map(([sourcePath]) => String(sourcePath));
    expect(new Set(renameSourcePaths).size).toBe(2);
  });

  it('should recover a stale per-storage lock before mutating', async () => {
    let mkdirCalls = 0;

    mkdirMock.mockImplementation((targetPath: any) => {
      if (String(targetPath).endsWith('.lock')) {
        mkdirCalls += 1;

        if (mkdirCalls === 1) {
          const error = Object.assign(new Error('EEXIST'), { code: 'EEXIST' });
          throw error;
        }
      }

      return undefined as never;
    });
    statMock.mockResolvedValue({ mtimeMs: Date.now() - 60_000 } as never);

    const storage = createNodeFileStorage({ type: 'nodeFile', path: '/tmp/headless-storage.json' });

    await storage.setItem('accounts', { a: 1 });

    expect(statMock).toHaveBeenCalledWith('/tmp/headless-storage.json.lock');
    expect(rmMock).toHaveBeenCalledWith('/tmp/headless-storage.json.lock', { recursive: true, force: true });
    expect(renameMock).toHaveBeenCalledTimes(1);
  });

  it('should fail with a clear error when the lock cannot be acquired in time', async () => {
    jest.useFakeTimers();

    mkdirMock.mockImplementation((targetPath: any) => {
      if (String(targetPath).endsWith('.lock')) {
        const error = Object.assign(new Error('EEXIST'), { code: 'EEXIST' });
        throw error;
      }

      return undefined as never;
    });

    const storage = createNodeFileStorage({ type: 'nodeFile', path: '/tmp/headless-storage.json' });
    const pendingWrite = storage.setItem('accounts', { a: 1 }).catch((err) => err);

    await jest.advanceTimersByTimeAsync(10_000);

    await expect(pendingWrite).resolves.toMatchObject({
      message: 'Timed out acquiring node-file storage lock for /tmp/headless-storage.json',
    });

    expect(renameMock).not.toHaveBeenCalled();

    jest.useRealTimers();
  });

  it('should resolve profile-backed storage into a durable home-directory path', async () => {
    const storage = createNodeFileStorage({ type: 'nodeFile', profile: 'mywallet' });

    await storage.getItem('accounts');

    expect(readFileMock).toHaveBeenCalledWith(resolveDefaultNodeFileStoragePath('mywallet'), 'utf8');
  });

  it('should expand ${HOME} placeholders in explicit storage paths', async () => {
    const storage = createNodeFileStorage({ type: 'nodeFile', path: '${HOME}/.mywallet/custom/storage.json' });

    await storage.getItem('accounts');

    expect(readFileMock).toHaveBeenCalledWith(`${homedir()}/.mywallet/custom/storage.json`, 'utf8');
  });
});
