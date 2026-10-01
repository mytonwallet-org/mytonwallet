import { createChunkLoader } from '../../util/chunkLoading';

export const loadAgentV2Host = createChunkLoader(
  () => import('../agentV2/AgentV2HostContextBridge').then((module) => module.default),
);

export const loadAgentV2Classic = createChunkLoader(
  () => loadAgentV2Host().then(() => (
    import('../agentV2/AgentV2Classic').then((module) => module.default)
  )),
);
