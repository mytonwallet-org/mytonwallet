import { createChunkLoader } from '../../../util/chunkLoading';

export const ensureLovelyChart = createChunkLoader(
  () => import('./lovelyChartWithStyles').then((module) => module.default),
);
