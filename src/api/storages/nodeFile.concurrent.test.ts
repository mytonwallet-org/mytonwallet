import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const WRITER_SCRIPT_PATH = join(__dirname, 'nodeFile.concurrent-writer.js');

function spawnWriter(args: string[]) {
  return new Promise<void>((resolve, reject) => {
    const child = spawn(process.execPath, [WRITER_SCRIPT_PATH, ...args], {
      cwd: process.cwd(),
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stderr = '';

    child.stderr.on('data', (chunk) => {
      stderr += String(chunk);
    });

    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(new Error(stderr || `Writer exited with code ${code}`));
    });
  });
}

describe('node-file storage cross-process concurrency', () => {
  it('should preserve updates from concurrent processes writing different logical keys', async () => {
    const storageDir = await mkdtemp(join(tmpdir(), 'mywallet-nodefile-lock-'));
    const storagePath = join(storageDir, 'storage.json');
    const startPath = join(storageDir, 'start');
    const readyAPath = join(storageDir, 'ready-a');
    const readyBPath = join(storageDir, 'ready-b');

    await writeFile(storagePath, '{}', 'utf8');

    const writerA = spawnWriter([
      storagePath,
      readyAPath,
      startPath,
      'accounts',
      JSON.stringify({
        'ton-testnet-1': {
          type: 'mnemonic',
          byChain: {
            ton: { address: 'address-1' },
          },
        },
      }),
    ]);
    const writerB = spawnWriter([
      storagePath,
      readyBPath,
      startPath,
      'currentAccountId',
      JSON.stringify('ton-testnet-1'),
    ]);

    await Promise.all([
      waitForFile(readyAPath),
      waitForFile(readyBPath),
    ]);

    await writeFile(startPath, 'go', 'utf8');
    await Promise.all([writerA, writerB]);

    const stored = JSON.parse(await readFile(storagePath, 'utf8'));

    expect(stored).toEqual({
      accounts: {
        'ton-testnet-1': {
          type: 'mnemonic',
          byChain: {
            ton: { address: 'address-1' },
          },
        },
      },
      currentAccountId: 'ton-testnet-1',
    });
  });

  it('should preserve concurrent same-key account updates across processes', async () => {
    const storageDir = await mkdtemp(join(tmpdir(), 'mywallet-nodefile-same-key-'));
    const storagePath = join(storageDir, 'storage.json');
    const startPath = join(storageDir, 'start');
    const readyAPath = join(storageDir, 'ready-a');
    const readyBPath = join(storageDir, 'ready-b');

    await writeFile(storagePath, '{"accounts":{}}', 'utf8');

    const writerA = spawnWriter([
      storagePath,
      readyAPath,
      startPath,
      '__setAccountValue__',
      JSON.stringify({
        type: 'mnemonic',
        byChain: {
          ton: { address: 'address-1' },
        },
      }),
      'ton-testnet-1',
    ]);
    const writerB = spawnWriter([
      storagePath,
      readyBPath,
      startPath,
      '__setAccountValue__',
      JSON.stringify({
        type: 'mnemonic',
        byChain: {
          ton: { address: 'address-2' },
        },
      }),
      'ton-testnet-2',
    ]);

    await Promise.all([
      waitForFile(readyAPath),
      waitForFile(readyBPath),
    ]);

    await writeFile(startPath, 'go', 'utf8');
    await Promise.all([writerA, writerB]);

    const stored = JSON.parse(await readFile(storagePath, 'utf8'));

    expect(stored).toEqual({
      accounts: {
        'ton-testnet-1': {
          type: 'mnemonic',
          byChain: {
            ton: { address: 'address-1' },
          },
        },
        'ton-testnet-2': {
          type: 'mnemonic',
          byChain: {
            ton: { address: 'address-2' },
          },
        },
      },
    });
  });
});

async function waitForFile(filePath: string) {
  for (;;) {
    try {
      await readFile(filePath, 'utf8');
      return;
    } catch (err: any) {
      if (err?.code !== 'ENOENT') {
        throw err;
      }

      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }
}
