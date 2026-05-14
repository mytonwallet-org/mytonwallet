import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { configureStorage } from './index';

const STORAGE_FILE_NAME = 'headless-storage.json';

describe('storage selection', () => {
  afterEach(() => {
    configureStorage(undefined);
  });

  it('should persist accounts and currentAccountId across fresh node-file storage instances', async () => {
    const storageDir = await mkdtemp(join(tmpdir(), 'mywallet-storage-'));
    const storagePath = join(storageDir, STORAGE_FILE_NAME);
    const accounts = {
      'ton-testnet-1': {
        type: 'mnemonic',
        byChain: {
          ton: {
            address: 'address-1',
          },
        },
      },
    };

    const firstStorage = configureStorage({
      type: 'nodeFile',
      path: storagePath,
    });

    await firstStorage.setItem('accounts', accounts);
    await firstStorage.setItem('currentAccountId', 'ton-testnet-1');

    const secondStorage = configureStorage({
      type: 'nodeFile',
      path: storagePath,
    });

    await expect(secondStorage.getItem('accounts')).resolves.toEqual(accounts);
    await expect(secondStorage.getItem('currentAccountId')).resolves.toBe('ton-testnet-1');
  });
});
