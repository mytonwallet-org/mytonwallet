import type { Storage } from '../storages/types';

import { AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY } from './identity';
import { AGENT_V2_CONSENT_STORAGE_KEY } from './runtime';
import { clearPersistedAgentV2WalletSession } from './walletSession';

export async function clearAgentV2PersistentState(storage: Storage) {
  await Promise.all([
    clearPersistedAgentV2WalletSession(),
    storage.removeItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY),
    storage.removeItem(AGENT_V2_CONSENT_STORAGE_KEY),
  ]);
}
