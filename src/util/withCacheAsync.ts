const cache = new WeakMap<AnyFunction, Map<string, any>>();

export default function withCacheAsync<T extends AnyAsyncFunction>(
  fn: T, canBeCached: (value: Awaited<ReturnType<T>>) => boolean = (value) => !!value,
) {
  return async (...args: Parameters<T>): Promise<Awaited<ReturnType<T>>> => {
    let fnCache = cache.get(fn);
    const cacheKey = buildCacheKey(args);

    if (fnCache) {
      if (fnCache.has(cacheKey)) {
        return fnCache.get(cacheKey);
      }
    } else {
      fnCache = new Map();
      cache.set(fn, fnCache);
    }

    const resultPromise = fn(...args);
    fnCache.set(cacheKey, resultPromise); // Putting into the cache early to prevent concurrent `fn` calls

    try {
      const result = await resultPromise;
      if (!canBeCached(result)) {
        fnCache.delete(cacheKey);
      }
      return result;
    } catch (err) {
      fnCache.delete(cacheKey);
      throw err;
    }
  };
}

function buildCacheKey(args: any[]) {
  return args.reduce((cacheKey, arg) => {
    return `${cacheKey}_${typeof arg === 'object' ? JSON.stringify(args) : arg}`;
  }, '');
}
