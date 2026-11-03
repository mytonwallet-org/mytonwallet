import { createChunkLoader } from '../../util/chunkLoading';

export const loadAgentV2Chats = createChunkLoader(
  () => import('../agentV2/AgentV2Chats').then((module) => module.default),
);
