import { APP_ENV, APP_NAME, APP_VERSION, BRILLIANT_API_BASE_URL } from '../../config';
import { bucketKey } from '../../util/circuitBreaker';
import { fetchJson, fetchWithRetry, fetchWithTimeout, handleFetchErrors } from '../../util/fetch';
import { getEnvironment } from '../environment';
import { getClientId } from './other';

const BAD_REQUEST_CODE = 400;

export async function callBackendPost<T>(path: string, data: AnyLiteral, options?: {
  authToken?: string;
  isAllowBadRequest?: boolean;
  method?: string;
  shouldRetry?: boolean;
  signal?: AbortSignal;
  timeout?: number;
  /** Reports headers separately from body consumption for request lifecycle diagnostics. */
  onHeaders?: (status: number) => void;
}): Promise<T> {
  const {
    authToken, isAllowBadRequest, method, shouldRetry, signal, timeout, onHeaders,
  } = options ?? {};

  const url = new URL(`${BRILLIANT_API_BASE_URL}${path}`);

  const init: RequestInit = {
    method: method ?? 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...getBackendHeaders(),
      ...(authToken && { 'X-Auth-Token': authToken }),
    },
    body: JSON.stringify(data),
    signal,
  };

  const response = shouldRetry
    ? await fetchWithRetry(url, init, {
      timeouts: timeout,
      shouldSkipRetryFn: (message) => !message?.includes('signal is aborted'),
      // Per-endpoint bucket: a slow /assets must not gate /swap or /currency-rates.
      bucketKey: bucketKey(url, { includePathPrefix: true }),
    })
    : await fetchWithTimeout(url.toString(), init, timeout);

  onHeaders?.(response.status);
  await handleFetchErrors(response, isAllowBadRequest ? [BAD_REQUEST_CODE] : undefined);

  return response.json();
}

export function callBackendGet(
  path: string,
  data: AnyLiteral | undefined,
  headers: HeadersInit | undefined,
  signal: AbortSignal | undefined,
  options: { shouldReturnText: true },
): Promise<string>;
export function callBackendGet<T extends AnyLiteral>(
  path: string,
  data?: AnyLiteral,
  headers?: HeadersInit,
  signal?: AbortSignal,
): Promise<T>;
export function callBackendGet<T extends AnyLiteral>(
  path: string,
  data?: AnyLiteral,
  headers?: HeadersInit,
  signal?: AbortSignal,
  options?: { shouldReturnText: true },
): Promise<T | string> {
  const url = new URL(`${BRILLIANT_API_BASE_URL}${path}`);
  const init: RequestInit = {
    headers: {
      ...headers,
      ...getBackendHeaders(),
    },
    signal,
  };
  const fetchOptions = {
    bucketKey: bucketKey(url, { includePathPrefix: true }),
  };

  if (options?.shouldReturnText) {
    return fetchJson(url, data, init, { ...fetchOptions, shouldReturnText: true });
  }

  return fetchJson<T>(url, data, init, fetchOptions);
}

export function getBackendHeaders() {
  return {
    ...getEnvironment().apiHeaders,
    'X-App-ClientID': getClientId(),
    ...(APP_VERSION && APP_VERSION !== 'undefined' && { 'X-App-Version': APP_VERSION }),
    'X-App-Env': APP_ENV,
    'X-App-Name': APP_NAME,
    'X-App-Timezone': Intl.DateTimeFormat().resolvedOptions().timeZone,
  } as Record<string, string>;
}

export function addBackendHeadersToSocketUrl(url: URL) {
  for (const [name, value] of Object.entries(getBackendHeaders())) {
    const match = /^X-App-(.+)$/i.exec(name);
    if (match) {
      url.searchParams.append(match[1].toLowerCase(), value);
    }
  }
}

export async function fetchBackendReferrer() {
  return (await callBackendGet<{ referrer?: string }>('/referrer/get')).referrer;
}
