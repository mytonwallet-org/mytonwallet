import {
  DEFAULT_ERROR_PAUSE,
  DEFAULT_RETRIES,
  DEFAULT_TIMEOUT,
  EVM_MAINNET_RPC_URL,
  EVM_TESTNET_RPC_URL,
  IPFS_GATEWAY_BASE_URL,
  PROXY_API_BASE_URL,
} from '../config';
import { getIsNegVerdictCacheEnabled } from '../api/common/cache';
import { ApiServerError } from '../api/errors';
import { pauseWithAbortSignal, throwIfAborted } from './abortSignal';
import {
  bucketKey as defaultBucketKey,
  CircuitBreaker,
  CircuitOpenError,
} from './circuit-breaker';
import { logDebug } from './logs';
import { NegativeVerdictCache } from './negativeVerdictCache';

import {
  fetchWithThrottledProvider,
  getProviderFetchRetryPolicy,
  getRetryAfterMs,
} from './ThrottledFetcher';

type FetchOptions = {
  retries?: number;
  timeouts?: number | number[];
  shouldSkipRetryFn?: (message?: string, statusCode?: number) => boolean;
  bucketKey?: string;
};

const breaker = new CircuitBreaker();
const negativeVerdictCache = new NegativeVerdictCache();

export type QueryParams = Record<string, string | number | boolean | string[] | undefined>;

const MAX_TIMEOUT = 30000; // 30 sec
const MAX_BACKOFF_MS = 10000; // 10 sec - jitter ceiling for retryable failures

// Statuses in which the host ruled on the request itself: it arrived and was answered with a
// deterministic verdict, so repeating the identical request cannot change the outcome. Narrower than the full
// terminal set on purpose - 401/403 stay terminal (no retry) but say something about access or
// about the upstream's own state, not about this request, and they can flip without the request
// changing at all.
//
// Two callers read this, and both need exactly that distinction. The negative-verdict cache
// replays these answers, so caching a 401 would mask a transient auth state for the whole TTL.
// The circuit breaker counts these as proof the host is alive, so counting a 401 or a 403 would
// let an upstream rejecting every request in bulk register as healthy for as long as it lasted.
const REQUEST_VERDICT_STATUSES = [400, 404, 422];

// The negative-verdict cache is scoped to the evmapi (Zerion) origin - the only path with the
// deterministic-4xx storm class. Other origins are excluded deliberately: toncenter GETs carry a
// `_=<time>` cache-buster (every URL unique, they would only pollute the bounded LRU) and some
// non-evmapi GETs legitimately poll a 404 until it flips to 200 (a fresh NFT before indexing, a
// dapp manifest), which a cached 4xx would stall.
const EVM_API_ORIGINS = new Set([
  new URL(EVM_MAINNET_RPC_URL).origin,
  new URL(EVM_TESTNET_RPC_URL).origin,
]);

export function fetchJsonWithProxy(url: string | URL, data?: QueryParams, init?: RequestInit) {
  return fetchJson(getProxiedJsonUrl(url.toString()), data, init);
}

/** Builds the request URL, folding query params into it the way `fetchJson` does. */
export function buildRequestUrl(url: string | URL, data?: QueryParams) {
  const urlObject = new URL(url);
  if (data) {
    Object.entries(data).forEach(([key, value]) => {
      if (value === undefined) {
        return;
      }

      if (Array.isArray(value)) {
        value.forEach((item) => {
          urlObject.searchParams.append(key, item.toString());
        });
      } else {
        urlObject.searchParams.set(key, value.toString());
      }
    });
  }

  return urlObject;
}

export async function fetchJson<T extends AnyLiteral>(
  url: string | URL,
  data?: QueryParams,
  init?: RequestInit,
  options?: FetchOptions,
): Promise<T> {
  const response = await fetchWithRetry(buildRequestUrl(url, data), init, options);

  return (await response.json()) as T;
}

export async function fetchWithRetry(url: string | URL, init?: RequestInit, options?: FetchOptions) {
  throwIfAborted(init?.signal);
  const providerRetryPolicy = getProviderFetchRetryPolicy(url);
  const {
    retries = providerRetryPolicy?.retries ?? DEFAULT_RETRIES,
    timeouts = DEFAULT_TIMEOUT,
    shouldSkipRetryFn = isTerminalFailure,
    bucketKey = defaultBucketKey(url),
  } = options ?? {};

  const method = init?.method ?? 'GET';
  const urlString = url.toString();

  // A GET to evmapi whose deterministic 4xx we already saw is replayed locally, before touching
  // the breaker: a replay is not a host contact, so it must produce no breaker or probe signal.
  const isNegVerdictCacheable = !init?.signal
    && method === 'GET'
    && getIsNegVerdictCacheEnabled()
    && isEvmApiOrigin(urlString);
  if (isNegVerdictCacheable) {
    const cached = negativeVerdictCache.get(urlString);
    if (cached) {
      throw new ApiServerError(
        buildFetchErrorMessage(method, urlString, cached.message, 0, cached.statusCode),
        cached.statusCode,
      );
    }
  }

  const slot = breaker.acquire(bucketKey);
  if (!slot) throw new CircuitOpenError(bucketKey);

  let message = 'Unknown error.';
  let statusCode: number | undefined;
  let settled = false;

  const cacheNegativeVerdictIfEligible = () => {
    if (isNegVerdictCacheable && isNegativeCacheableStatus(statusCode)) {
      negativeVerdictCache.set(urlString, { statusCode: statusCode!, message });
    }
  };

  try {
    for (let i = 1; i <= retries; i++) {
      try {
        if (i > 1) {
          logDebug(`Retry request #${i}:`, urlString, statusCode);
        }

        const timeout = Array.isArray(timeouts)
          ? timeouts[i - 1] ?? timeouts[timeouts.length - 1]
          : Math.min(timeouts * i, MAX_TIMEOUT);
        // Reset before the fetch so the status reflects only this attempt. If the fetch
        // throws before a response arrives (timeout/transport error), a stale code from a
        // prior attempt would otherwise mislead shouldSkipRetryFn and the breaker verdict
        // into treating a host-health failure as a 4xx success.
        statusCode = undefined;
        const response = await fetchWithTimeout(url, init, timeout);
        statusCode = response.status;

        if (statusCode >= 400) {
          const { error } = await response.json().catch(() => ({}));
          const requestError = new Error(error ?? `HTTP Error ${statusCode}`) as Error & {
            retryAfterMs?: number;
          };
          requestError.retryAfterMs = getRetryAfterMs(response.headers) ?? providerRetryPolicy?.fallbackRetryAfterMs;
          throw requestError;
        }

        slot.recordSuccess();
        settled = true;
        return response;
      } catch (err: any) {
        throwIfAborted(init?.signal);
        message = typeof err === 'string' ? err : err.message ?? message;
        const retryAfterMs = typeof err === 'string'
          ? undefined
          : (err as Error & { retryAfterMs?: number }).retryAfterMs;

        const shouldSkipRetry = shouldSkipRetryFn(message, statusCode);

        if (shouldSkipRetry) {
          // Host-health verdict: a request-verdict status (400/404/422) means an alive host that
          // ruled against this request; everything else, 401/403 included, counts toward tripping
          // the breaker, even when shouldSkipRetry short-circuits the retry budget.
          if (isBreakerHealthy4xx(statusCode)) {
            slot.recordSuccess();
          } else {
            slot.recordFailure();
          }
          cacheNegativeVerdictIfEligible();
          settled = true;
          throw new ApiServerError(buildFetchErrorMessage(method, urlString, message, i, statusCode), statusCode);
        }

        if (i < retries) {
          const backoffMs = computeRetryBackoffMs(i);
          await pauseWithAbortSignal(
            retryAfterMs !== undefined ? Math.max(retryAfterMs, backoffMs) : backoffMs,
            init?.signal,
          );
        }
      }
    }

    throwIfAborted(init?.signal);
    // Same verdict as the in-loop branch: only a request-verdict status proves the host alive.
    if (isBreakerHealthy4xx(statusCode)) {
      slot.recordSuccess();
    } else {
      slot.recordFailure();
    }
    cacheNegativeVerdictIfEligible();
    settled = true;
    throw new ApiServerError(buildFetchErrorMessage(method, urlString, message, retries, statusCode), statusCode);
  } finally {
    if (!settled) slot.cancelled();
  }
}

function buildFetchErrorMessage(
  method: string,
  url: string,
  message: string,
  attempts: number,
  statusCode?: number,
): string {
  const parts = [`${method} ${url}`, `attempts=${attempts}`];
  if (statusCode !== undefined) parts.push(`status=${statusCode}`);
  parts.push(message);
  return parts.join(' | ');
}

export function fetchWithTimeout(url: string | URL, init?: RequestInit, timeout = DEFAULT_TIMEOUT) {
  return fetchWithThrottledProvider(url, init, timeout);
}

export async function handleFetchErrors(response: Response, ignoreHttpCodes?: number[]) {
  if (!response.ok && (!ignoreHttpCodes?.includes(response.status))) {
    // eslint-disable-next-line prefer-const
    let { error, errors } = await response.json().catch(() => undefined);
    if (!error && errors && errors.length) {
      error = errors[0]?.msg;
    }

    throw new ApiServerError(error ?? `HTTP Error ${response.status}`, response.status);
  }
  return response;
}

/**
 * Retry policy: retry ONLY failures that can plausibly resolve on their own (transport/timeout,
 * 408, 429, 5xx). Every other 4xx (400/401/403/404/405/410/422/451/...) is terminal - repeating
 * the identical request cannot fix a client-side error, and retrying it only amplifies storms.
 */
export function classifyFetchFailure(statusCode?: number): 'retryable' | 'terminal' {
  if (statusCode === undefined) return 'retryable'; // network / transport / timeout
  if (statusCode === 408 || statusCode === 429) return 'retryable';
  if (statusCode >= 500) return 'retryable';
  if (statusCode >= 400) return 'terminal';
  return 'retryable';
}

function isTerminalFailure(_message?: string, statusCode?: number): boolean {
  return classifyFetchFailure(statusCode) === 'terminal';
}

/**
 * Whether a status proves the host is alive and serving. Only a deterministic verdict on the
 * request itself does: 429 and 408 are overload signals, and 401/403 report access or upstream state, which an
 * upstream can return to everyone at once while being anything but healthy. An unrecognised 4xx
 * is not read as health either - the cost of that is a breaker opening slightly early, against a
 * breaker that never opens at all.
 */
function isBreakerHealthy4xx(statusCode?: number): boolean {
  return statusCode !== undefined && REQUEST_VERDICT_STATUSES.includes(statusCode);
}

export function isNegativeCacheableStatus(statusCode?: number): boolean {
  return statusCode !== undefined && REQUEST_VERDICT_STATUSES.includes(statusCode);
}

function isEvmApiOrigin(url: string): boolean {
  try {
    return EVM_API_ORIGINS.has(new URL(url).origin);
  } catch {
    return false;
  }
}

/** Full-jitter exponential backoff: random in [0, min(MAX, BASE * 2^attempt)] (1-based attempt). */
export function computeRetryBackoffMs(attempt: number): number {
  const ceiling = Math.min(MAX_BACKOFF_MS, DEFAULT_ERROR_PAUSE * 2 ** attempt);
  return Math.round(Math.random() * ceiling);
}

/** Test-only: clears module-level fetch state (negative-verdict cache + circuit breaker). */
export function resetFetchStateForTests(): void {
  negativeVerdictCache.reset();
  breaker.reset();
}

export function getProxiedJsonUrl(url: string) {
  return `${PROXY_API_BASE_URL}/download-json?url=${encodeURIComponent(url)}`;
}

export function getProxiedLottieUrl(url: string) {
  return `${PROXY_API_BASE_URL}/download-lottie?url=${encodeURIComponent(url)}`;
}

export function fixIpfsUrl(url: string) {
  return url.replace('ipfs://', IPFS_GATEWAY_BASE_URL);
}
