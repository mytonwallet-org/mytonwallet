import { createChunkLoader } from '../../../util/chunkLoading';

export const loadChunk = createChunkLoader(() => import('../chunk'));
