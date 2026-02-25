import {
  DEFAULT_ERROR_PAUSE,
  DEFAULT_RETRIES,
  DEFAULT_TIMEOUT,
  IPFS_GATEWAY_BASE_URL,
  PROXY_API_BASE_URL,
} from '../config';
import { ApiServerError } from '../api/errors';
import { logDebug } from './logs';
import { pause } from './schedulers';

type FetchOptions = {
  retries?: number;
  timeouts?: number | number[];
  shouldSkipRetryFn?: (message?: string, statusCode?: number) => boolean;
};

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
  const {
    retries = DEFAULT_RETRIES,
    timeouts = DEFAULT_TIMEOUT,
    shouldSkipRetryFn = isNotTemporaryError,
  } = options ?? {};

  let message = 'Unknown error.';
  let statusCode: number | undefined;

  for (let i = 1; i <= retries; i++) {
    try {
      if (i > 1) {
        logDebug(`Retry request #${i}:`, url.toString(), statusCode);
      }

      const timeout = Array.isArray(timeouts)
        ? timeouts[i - 1] ?? timeouts[timeouts.length - 1]
        : Math.min(timeouts * i, MAX_TIMEOUT);
      const response = await fetchWithTimeout(url, init, timeout);
      statusCode = response.status;

      if (statusCode >= 400) {
        const { error } = await response.json().catch(() => {});
        throw new Error(error ?? `HTTP Error ${statusCode}`);
      }

      return response;
    } catch (err: any) {
      message = typeof err === 'string' ? err : err.message ?? message;

      const shouldSkipRetry = shouldSkipRetryFn(message, statusCode);

      if (shouldSkipRetry) {
        throw new ApiServerError(message, statusCode);
      }

      if (i < retries) {
        await pause(DEFAULT_ERROR_PAUSE * i);
      }
    }
  }

  throw new ApiServerError(message);
}

export async function fetchWithTimeout(url: string | URL, init?: RequestInit, timeout = DEFAULT_TIMEOUT) {
  const controller = new AbortController();
  const id = setTimeout(() => {
    controller.abort();
  }, timeout);

  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
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
