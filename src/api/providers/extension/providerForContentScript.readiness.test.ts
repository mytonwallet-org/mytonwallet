import type { Storage } from '../../storages/types';

import { createExtensionInterface } from '../../../util/createPostMessageInterface';
import { actualStateVersion } from '../../common/helpers';
import { getProtocolManager } from '../../dappProtocols';
import { connectSite } from '../../extensionMethods/sites';
import { withStorage } from '../../storages';

jest.mock('../../../util/createPostMessageInterface', () => ({ createExtensionInterface: jest.fn() }));
jest.mock('../../dappProtocols', () => ({ getProtocolManager: jest.fn() }));
jest.mock('../../extensionMethods/sites', () => ({ connectSite: jest.fn(), deactivateSite: jest.fn() }));

import './providerForContentScript';

const handler = jest.mocked(createExtensionInterface).mock.calls[0][1] as (
  name: string, origin?: string, ...args: unknown[]
) => Promise<unknown>;
const reconnect = jest.fn();

function createMemoryStorage(seed: Record<string, unknown>) {
  const values = new Map(Object.entries(seed));
  const instance: Storage = {
    getItem: jest.fn((key) => Promise.resolve(values.get(key))),
    getMany: jest.fn((keys) => Promise.resolve(Object.fromEntries(keys.map((key) => [key, values.get(key)])))),
    setItem: jest.fn(),
    removeItem: jest.fn(),
    clear: jest.fn(),
  };

  return instance;
}

beforeEach(() => {
  reconnect.mockReset().mockResolvedValue({ success: true });
  jest.mocked(getProtocolManager).mockReturnValue({ getAdapter: () => ({ reconnect }) } as never);
});

it('rejects cold restore while migration is incomplete without invoking the adapter', async () => {
  const storage = createMemoryStorage({ stateVersion: actualStateVersion, address: 'legacy' });

  await expect(withStorage(storage, () => handler('tonConnect_reconnect', 'https://dapp.example', 1)))
    .rejects.toThrow('Open your wallet to finish updating it, then reconnect.');
  expect(reconnect).not.toHaveBeenCalled();
  expect(storage.setItem).not.toHaveBeenCalled();
});

it('rejects cold restore after a failed versioned migration without invoking the adapter', async () => {
  const storage = createMemoryStorage({ stateVersion: actualStateVersion - 1, accounts: {} });

  await expect(withStorage(storage, () => handler('tonConnect_reconnect', 'https://dapp.example', 2)))
    .rejects.toThrow('Open your wallet to finish updating it, then reconnect.');
  expect(reconnect).not.toHaveBeenCalled();
  expect(storage.setItem).not.toHaveBeenCalled();
});

it('preserves warm restore for a migration-ready profile', async () => {
  const storage = createMemoryStorage({ stateVersion: actualStateVersion });

  await expect(withStorage(storage, () => handler('tonConnect_reconnect', 'https://dapp.example', 3)))
    .resolves.toEqual({ success: true });
  expect(reconnect).toHaveBeenCalledWith(expect.objectContaining({ url: 'https://dapp.example' }), 3);
});

it('keeps content auto-init outside the rejecting request gate', async () => {
  const onUpdate = jest.fn();

  await handler('init', 'https://dapp.example', onUpdate);

  expect(jest.mocked(connectSite)).toHaveBeenCalledWith(onUpdate);
});
