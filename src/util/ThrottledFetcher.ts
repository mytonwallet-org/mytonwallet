import {
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
} from '../config';
import {
  mergeAbortSignals,
  pauseWithAbortSignal,
  raceWithAbortSignal,
  throwIfAborted,
} from './abortSignal';

type FetchInput = string | URL | Request;

const DEFAULT_TIMEOUT_MS = 30000;
const PROVIDER_MIN_DELAY_MS = 100;
const PROVIDER_RETRIES = 6;
const PROVIDER_FALLBACK_RETRY_AFTER_MS = 5000;
// A 429 is provider-controlled back-pressure, so the pause it asks for is provider-controlled
// too. Without a ceiling one response parks every later request to that origin for as long as
// the header says - an hour-long Retry-After would take the origin out of service for an hour.
const MAX_PROVIDER_RETRY_AFTER_MS = 30000;
// Origins throttled per-provider: spaced requests, Retry-After back-pressure on 429.
const THROTTLED_PROVIDER_ORIGINS = new Set([
  new URL(TONCENTER_MAINNET_URL).origin,
  new URL(TONCENTER_TESTNET_URL).origin,
  new URL(TONAPIIO_MAINNET_URL).origin,
  new URL(TONAPIIO_TESTNET_URL).origin,
]);
const throttledFetchers = new Map<string, ThrottledFetcher>();

export type ProviderFetchRetryPolicy = {
  retries: number;
  fallbackRetryAfterMs?: number;
};

export class ThrottledFetcher {
  private lastRequestAt: number | undefined;
  private nextAllowedAt = 0;
  private pending: Promise<void> = Promise.resolve();

  constructor(
    private readonly minDelayMs: number,
    private readonly timeoutMs: number = DEFAULT_TIMEOUT_MS,
    private readonly onResult?: (isSuccess: boolean) => void,
  ) {}

  async fetch(input: FetchInput, init?: RequestInit, timeoutMs = this.timeoutMs): Promise<Response> {
    // The timer starts before the queue wait, not after it: the caller asked for a deadline on the
    // whole call, and a request parked behind another origin's back-pressure would otherwise wait
    // without any bound of its own.
    const controller = new AbortController();
    const timeoutId = setTimeout(() => {
      controller.abort(new DOMException('Request timed out.', 'TimeoutError'));
    }, timeoutMs);
    const { signal, cleanup } = mergeAbortSignals(init?.signal, controller.signal);

    try {
      await this.throttle(signal);
      throwIfAborted(signal);

      // Only the network call reports provider health: a request abandoned in the queue never
      // reached the provider and says nothing about it.
      try {
        const response = await fetch(input, {
          ...init,
          signal,
        });
        this.onResult?.(response.ok);
        return response;
      } catch (err) {
        this.onResult?.(false);
        throw err;
      }
    } finally {
      clearTimeout(timeoutId);
      cleanup();
    }
  }

  delayNextRequest(delayMs: number) {
    this.nextAllowedAt = Math.max(this.nextAllowedAt, Date.now() + delayMs);
  }

  private async throttle(signal?: AbortSignal | null) {
    const pending = this.pending.then(async () => {
      throwIfAborted(signal);
      const now = Date.now();
      const sinceLastRequestMs = this.lastRequestAt === undefined ? undefined : now - this.lastRequestAt;
      const minDelayRemainingMs = sinceLastRequestMs === undefined
        ? 0
        : this.minDelayMs - sinceLastRequestMs;
      const explicitDelayRemainingMs = this.nextAllowedAt - now;
      const waitMs = Math.max(0, minDelayRemainingMs, explicitDelayRemainingMs);

      if (waitMs > 0) {
        await pauseWithAbortSignal(waitMs, signal);
      }

      throwIfAborted(signal);
      this.lastRequestAt = Date.now();
      this.nextAllowedAt = this.lastRequestAt;
    });
    this.pending = pending.catch(() => undefined);

    await raceWithAbortSignal(pending, signal);
  }
}

export async function fetchWithThrottledProvider(
  input: FetchInput,
  init?: RequestInit,
  timeoutMs = DEFAULT_TIMEOUT_MS,
): Promise<Response> {
  const url = getUrl(input);
  if (!url || !shouldThrottleUrl(url)) {
    return new ThrottledFetcher(0, timeoutMs).fetch(input, init, timeoutMs);
  }

  const fetcher = getProviderFetcher(url.origin);
  const response = await fetcher.fetch(input, init, timeoutMs);
  adjustProviderDelay(url.origin, response);
  return response;
}

export function getProviderFetchRetryPolicy(input: FetchInput): ProviderFetchRetryPolicy | undefined {
  const url = getUrl(input);
  if (!url || !shouldThrottleUrl(url)) {
    return undefined;
  }

  return {
    retries: PROVIDER_RETRIES,
    fallbackRetryAfterMs: PROVIDER_FALLBACK_RETRY_AFTER_MS,
  };
}

export function getRetryAfterMs(headers: Pick<Headers, 'get'>) {
  const header = headers.get('Retry-After');
  if (!header) {
    return undefined;
  }

  const seconds = Number(header);
  if (Number.isFinite(seconds)) {
    return Math.max(0, seconds * 1000);
  }

  const timestamp = Date.parse(header);
  if (!Number.isNaN(timestamp)) {
    return Math.max(0, timestamp - Date.now());
  }

  return undefined;
}

export function resetThrottledProviderFetchers() {
  throttledFetchers.clear();
}

function shouldThrottleUrl(url: URL) {
  return THROTTLED_PROVIDER_ORIGINS.has(url.origin);
}

function getProviderFetcher(origin: string) {
  let fetcher = throttledFetchers.get(origin);
  if (!fetcher) {
    fetcher = new ThrottledFetcher(PROVIDER_MIN_DELAY_MS);
    throttledFetchers.set(origin, fetcher);
  }

  return fetcher;
}

function adjustProviderDelay(origin: string, response: Response) {
  if (response.status !== 429) {
    return;
  }

  const retryAfterMs = getRetryAfterMs(response.headers) ?? PROVIDER_FALLBACK_RETRY_AFTER_MS;
  const fetcher = throttledFetchers.get(origin);
  if (!fetcher) {
    return;
  }

  fetcher.delayNextRequest(
    Math.min(MAX_PROVIDER_RETRY_AFTER_MS, Math.max(PROVIDER_MIN_DELAY_MS, retryAfterMs)),
  );
}

function getUrl(input: FetchInput): URL | undefined {
  try {
    if (typeof input === 'string' || input instanceof URL) {
      return new URL(input.toString());
    }

    return new URL(input.url);
  } catch {
    return undefined;
  }
}
