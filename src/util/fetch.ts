import {
  DEFAULT_ERROR_PAUSE,
  DEFAULT_RETRIES,
  DEFAULT_TIMEOUT,
  IPFS_GATEWAY_BASE_URL,
  PROXY_API_BASE_URL,
} from '../config';
import { ApiServerError } from '../api/errors';
import {
  bucketKey as defaultBucketKey,
  CircuitBreaker,
  CircuitOpenError,
} from './circuit-breaker';
import { logDebug } from './logs';
import { pause } from './schedulers';

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

type QueryParams = Record<string, string | number | boolean | string[] | undefined>;

const MAX_TIMEOUT = 30000; // 30 sec

export function fetchJsonWithProxy(url: string | URL, data?: QueryParams, init?: RequestInit) {
  return fetchJson(getProxiedJsonUrl(url.toString()), data, init);
}

export async function fetchJson<T extends AnyLiteral>(
  url: string | URL,
  data?: QueryParams,
  init?: RequestInit,
  options?: FetchOptions,
): Promise<T> {
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

  const response = await fetchWithRetry(urlObject, init, options);

  return (await response.json()) as T;
}

export async function fetchWithRetry(url: string | URL, init?: RequestInit, options?: FetchOptions) {
  const providerRetryPolicy = getProviderFetchRetryPolicy(url);
  const {
    retries = providerRetryPolicy?.retries ?? DEFAULT_RETRIES,
    timeouts = DEFAULT_TIMEOUT,
    shouldSkipRetryFn = isNotTemporaryError,
    bucketKey = defaultBucketKey(url),
  } = options ?? {};

  const slot = breaker.acquire(bucketKey);
  if (!slot) throw new CircuitOpenError(bucketKey);

  const method = init?.method ?? 'GET';
  const urlString = url.toString();

  let message = 'Unknown error.';
  let statusCode: number | undefined;
  let settled = false;

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
        message = typeof err === 'string' ? err : err.message ?? message;
        const retryAfterMs = typeof err === 'string'
          ? undefined
          : (err as Error & { retryAfterMs?: number }).retryAfterMs;

        const shouldSkipRetry = shouldSkipRetryFn(message, statusCode);

        if (shouldSkipRetry) {
          // 4xx: host responded with a usable error body - host is alive,
          // the request was wrong. 5xx/transport/no-status with shouldSkipRetry
          // (e.g. callBackendPost short-circuits on every non-abort error) is
          // still a host-health failure even though we're not retrying.
          if (statusCode !== undefined && statusCode >= 400 && statusCode < 500) {
            slot.recordSuccess();
          } else {
            slot.recordFailure();
          }
          settled = true;
          throw new ApiServerError(buildFetchErrorMessage(method, urlString, message, i, statusCode), statusCode);
        }

        if (i < retries) {
          await pause(retryAfterMs ?? DEFAULT_ERROR_PAUSE * i);
        }
      }
    }

    // Same host-health classification as the in-loop branch above: a 4xx that
    // exhausted retries still means the host answered and is alive, so it must
    // not count toward tripping the breaker.
    if (statusCode !== undefined && statusCode >= 400 && statusCode < 500) {
      slot.recordSuccess();
    } else {
      slot.recordFailure();
    }
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

export async function fetchWithTimeout(url: string | URL, init?: RequestInit, timeout = DEFAULT_TIMEOUT) {
  const controller = new AbortController();
  const id = setTimeout(() => {
    controller.abort();
  }, timeout);

  try {
    return await fetchWithThrottledProvider(url, {
      ...init,
      signal: controller.signal,
    }, timeout);
  } finally {
    clearTimeout(id);
  }
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

function isNotTemporaryError(message?: string, statusCode?: number) {
  return statusCode && [400, 404].includes(statusCode);
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
