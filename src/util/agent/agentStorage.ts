import type { AgentMessage } from '../../global/types';

import { resetConversationId } from './agentApi';
import agentStore from './agentStore';

const IDB_KEY = 'agentMessages';

export async function loadAgentMessages(): Promise<AgentMessage[]> {
  const data = await agentStore.getItem(IDB_KEY);
  return Array.isArray(data) ? data : [];
}

export async function saveAgentMessages(messages: AgentMessage[]): Promise<void> {
  await agentStore.setItem(IDB_KEY, messages);
}

export async function clearAgentChat() {
  await agentStore.removeItem(IDB_KEY);
  await resetConversationId();
}
