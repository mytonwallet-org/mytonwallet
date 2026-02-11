import { APP_ENV, APP_VERSION, BRILLIANT_API_BASE_URL } from '../../config';
import { fetchJson, fetchWithRetry, fetchWithTimeout, handleFetchErrors } from '../../util/fetch';
import { getEnvironment } from '../environment';
import { getClientId } from './other';

const BAD_REQUEST_CODE = 400;

export async function callBackendPost<T>(path: string, data: AnyLiteral, options?: {
  authToken?: string;
  isAllowBadRequest?: boolean;
  method?: string;
  shouldRetry?: boolean;
  timeout?: number;
}): Promise<T> {
  const {
    authToken, isAllowBadRequest, method, shouldRetry, timeout,
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
  };

  const response = shouldRetry
    ? await fetchWithRetry(url, init, {
      timeouts: timeout,
      shouldSkipRetryFn: (message) => !message?.includes('signal is aborted'),
    })
    : await fetchWithTimeout(url.toString(), init, timeout);

  await handleFetchErrors(response, isAllowBadRequest ? [BAD_REQUEST_CODE] : undefined);

  return response.json();
}

export function callBackendGet<T extends AnyLiteral>(path: string, data?: AnyLiteral, headers?: HeadersInit) {
  const url = new URL(`${BRILLIANT_API_BASE_URL}${path}`);

  return fetchJson<T>(url, data, {
    headers: {
      ...headers,
      ...getBackendHeaders(),
    },
  });
}

export function getBackendHeaders() {
  return {
    ...getEnvironment().apiHeaders,
    'X-App-ClientID': getClientId(),
    'X-App-Version': APP_VERSION,
    'X-App-Env': APP_ENV,
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
