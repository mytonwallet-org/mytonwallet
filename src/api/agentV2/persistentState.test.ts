import type { Storage } from '../storages/types';

import { clearAgentV2PersistentState } from './persistentState';

const WALLET_SESSION_STORAGE_KEY = 'agentV2WalletSession';

describe('Agent V2 persistent state', () => {
  it('clears account-bound state without an active runtime', async () => {
    const storage = createMemoryStorage({
      agentV2DeviceIdentity: 'identity',
      agentV2Consent: 'consent',
    });
    sessionStorage.setItem(WALLET_SESSION_STORAGE_KEY, 'session');

    await clearAgentV2PersistentState(storage);

    await expect(storage.getItem('agentV2DeviceIdentity')).resolves.toBeUndefined();
    await expect(storage.getItem('agentV2Consent')).resolves.toBeUndefined();
    expect(sessionStorage.getItem(WALLET_SESSION_STORAGE_KEY)).toBeNull();
  });
});

function createMemoryStorage(initial: Partial<Record<string, unknown>>): Storage {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (name) => Promise.resolve(values.get(name)),
    setItem: (name, value) => {
      values.set(name, value);
      return Promise.resolve();
    },
    removeItem: (name) => {
      values.delete(name);
      return Promise.resolve();
    },
    clear: () => {
      values.clear();
      return Promise.resolve();
    },
  };
}
