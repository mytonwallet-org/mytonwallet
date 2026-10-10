import { createChunkLoader } from '../../util/chunkLoading';

export const loadAgentV2Classic = createChunkLoader(
  () => import('../agentV2/AgentV2Classic').then((module) => module.default),
);
