import { createChunkLoader, handleChunkLoadError } from '../../util/chunkLoading';

type RLottieClass = typeof import('./RLottie').default;

let RLottie: RLottieClass;

// Time for the main interface to completely load
const LOTTIE_LOAD_DELAY = 3000;

export const ensureRLottie = createChunkLoader(async () => {
  RLottie = (await import('./RLottie')).default;
  return RLottie;
});

export function getRLottie() {
  return RLottie;
}

setTimeout(() => {
  // A failed warm-up is retried by the first sticker that needs the module
  void ensureRLottie().catch(handleChunkLoadError('ensureRLottie'));
}, LOTTIE_LOAD_DELAY);
