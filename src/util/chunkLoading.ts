import { SECOND } from './dateFormat';
import { logDebugError } from './logs';

// What Chromium, Firefox and Safari reject `import()` with when the module cannot be fetched, plus Vite's own
// error for a stylesheet the chunk depends on. An exception thrown while the module evaluates matches none of them.
const CHUNK_LOAD_ERROR_REGEX = new RegExp([
  'Failed to fetch dynamically imported module',
  'error loading dynamically imported module',
  'Importing a module script failed',
  'Unable to preload CSS',
].join('|'));

// Firefox and Safari fetch a failed module again on the next `import()`, while Chromium keeps the failure until the
// page reloads. Either way, callers that come right after a failure share it instead of repeating the request.
const CHUNK_RETRY_DELAY = 5 * SECOND;

// Vite dispatches `vite:preloadError` only for imports on the main thread, so the API connector reports
// the failed chunks of the worker with this event
const API_CHUNK_LOAD_ERROR_EVENT = 'mtw:apiChunkLoadError';

type VitePreloadErrorEvent = Event & { payload?: unknown };

export function isChunkLoadError(err: unknown) {
  return err instanceof Error && CHUNK_LOAD_ERROR_REGEX.test(err.message);
}

/**
 * Memoizes a lazy chunk. A failed load is kept for `CHUNK_RETRY_DELAY`, after which the next call imports again.
 */
export function createChunkLoader<T>(load: () => Promise<T>) {
  let promise: Promise<T> | undefined;

  return () => {
    if (!promise) {
      const current = load();
      promise = current;

      current.catch(() => {
        setTimeout(() => {
          if (promise === current) promise = undefined;
        }, CHUNK_RETRY_DELAY);
      });
    }

    return promise;
  };
}

/**
 * Rejection handler for code that waits for a lazy chunk. A failed load is only logged, because the reload prompt
 * covers it. Any other error, such as one thrown by the module itself, is rethrown to reach `handleError`.
 */
export function handleChunkLoadError(label: string) {
  return (err: unknown) => {
    if (!isChunkLoadError(err)) throw err;

    logDebugError(label, err);
  };
}

export function reportApiChunkLoadError(err: unknown) {
  if (isChunkLoadError(err)) {
    window.dispatchEvent(new Event(API_CHUNK_LOAD_ERROR_EVENT));
  }
}

export function addChunkLoadErrorListener(callback: NoneToVoidFunction) {
  window.addEventListener('vite:preloadError', (e: VitePreloadErrorEvent) => {
    if (isChunkLoadError(e.payload)) callback();
  });
  window.addEventListener(API_CHUNK_LOAD_ERROR_EVENT, callback);
}
