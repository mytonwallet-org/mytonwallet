import { createStore, delMany } from 'idb-keyval';

import { INDEXED_DB_NAME, INDEXED_DB_STORE_NAME } from '../../config';

const LEGACY_AGENT_STORAGE_KEYS = ['agentMessages', 'agentConversationId'];
const store = createStore(INDEXED_DB_NAME, INDEXED_DB_STORE_NAME);

export default function clearLegacyAgentStorage(): Promise<void> {
  return delMany(LEGACY_AGENT_STORAGE_KEYS, store);
}
