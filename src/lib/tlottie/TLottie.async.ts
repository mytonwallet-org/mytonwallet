import { createChunkLoader, handleChunkLoadError } from '../../util/chunkLoading';

type TLottieClass = typeof import('./TLottie').default;

let TLottie: TLottieClass;

// Time for the main interface to completely load
const LOTTIE_LOAD_DELAY = 3000;

export const ensureTLottie = createChunkLoader(async () => {
  TLottie = (await import('./TLottie')).default;
  return TLottie;
});

export function getTLottie() {
  return TLottie;
}

setTimeout(() => {
  // A failed warm-up is retried by the first sticker that needs the module
  void ensureTLottie().catch(handleChunkLoadError('ensureTLottie'));
}, LOTTIE_LOAD_DELAY);
