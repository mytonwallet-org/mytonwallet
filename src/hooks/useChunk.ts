import { useEffect, useState } from '../lib/teact/teact';

import { handleChunkLoadError } from '../util/chunkLoading';

type ChunkLoader<T> = () => Promise<T>;

// A mount after the load renders the chunk at once, as when the app switches layouts across the phone breakpoint
const loadedChunks = new WeakMap<ChunkLoader<unknown>, unknown>();

/**
 * What a lazy chunk from `createChunkLoader` resolves to, or `undefined` until it loads. On a failed load the value
 * stays `undefined`, and the next mount or request loads the chunk again.
 */
export default function useChunk<T>(load: ChunkLoader<T>, shouldLoad: boolean) {
  // The setter wraps the value, which may be a component and so a function
  const [chunk, setChunk] = useState(() => loadedChunks.get(load) as T | undefined);

  useEffect(() => {
    if (chunk || !shouldLoad) return undefined;

    let isActive = true;
    void load().then((loaded) => {
      loadedChunks.set(load, loaded);
      if (isActive) setChunk(() => loaded);
    }, handleChunkLoadError('useChunk'));

    return () => {
      isActive = false;
    };
  }, [chunk, load, shouldLoad]);

  return chunk;
}
