import { FetchDemand, isFetchDemand } from './fetchDemand';

type CacheEntry = {
  promise: Promise<any>;
  demand?: FetchDemand;
};

const cache = new WeakMap<AnyFunction, Map<string, CacheEntry>>();

export default function withCacheAsync<T extends AnyAsyncFunction>(
  fn: T,
  canBeCached: (value: Awaited<ReturnType<T>>) => boolean = (value) => !!value,
) {
  return createCachedFunction(fn, canBeCached, false) as (...args: Parameters<T>) => Promise<Awaited<ReturnType<T>>>;
}

/**
 * Like `withCacheAsync`, for work that makes provider requests. The work gets a `FetchDemand` of its own as the first
 * argument and makes its requests on behalf of it. A caller may pass its demand as the last argument: the demand is
 * left out of the cache key and is lent to the work while the caller waits for the result, so the requests of work that
 * someone else started move ahead while an urgent caller waits for them.
 */
export function withFetchDemandCacheAsync<Args extends any[], R>(
  fn: (demand: FetchDemand, ...args: Args) => Promise<R>,
  canBeCached: (value: R) => boolean = (value) => !!value,
) {
  return createCachedFunction(fn, canBeCached, true) as (...args: Args | [...Args, FetchDemand?]) => Promise<R>;
}

function createCachedFunction(
  fn: AnyAsyncFunction,
  canBeCached: (value: any) => boolean,
  shouldPassDemand: boolean,
) {
  return async (...args: any[]) => {
    let fnCache = cache.get(fn);
    const callerDemand = shouldPassDemand ? args.find(isFetchDemand) : undefined;
    const keyArgs = callerDemand ? args.filter((arg) => arg !== callerDemand) : args;
    const cacheKey = buildCacheKey(keyArgs);

    if (fnCache) {
      const entry = fnCache.get(cacheKey);
      if (entry) {
        return waitForEntry(entry, callerDemand);
      }
    } else {
      fnCache = new Map();
      cache.set(fn, fnCache);
    }

    const demand = shouldPassDemand ? new FetchDemand() : undefined;
    const resultPromise = demand ? fn(demand, ...keyArgs) : fn(...args);
    const entry = { promise: resultPromise, demand };
    fnCache.set(cacheKey, entry); // Putting into the cache early to prevent concurrent `fn` calls

    try {
      const result = await waitForEntry(entry, callerDemand);
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

function waitForEntry({ promise, demand }: CacheEntry, callerDemand?: FetchDemand) {
  return demand && callerDemand ? callerDemand.waitFor(demand, promise) : promise;
}

function buildCacheKey(args: any[]) {
  // A trailing `undefined` is the same call as an omitted argument
  let length = args.length;
  while (length && args[length - 1] === undefined) {
    length--;
  }

  return args.slice(0, length).reduce((cacheKey, arg) => {
    return `${cacheKey}_${typeof arg === 'object' ? JSON.stringify(arg) : arg}`;
  }, '');
}
