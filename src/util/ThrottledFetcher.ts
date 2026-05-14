import {
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
} from '../config';
import { pause } from './schedulers';

type FetchInput = string | URL | Request;

type CleanupAbortSignal = AbortSignal & { cleanup?: () => void };

const DEFAULT_TIMEOUT_MS = 30000;
const TONCENTER_MIN_DELAY_MS = 250;
const TONCENTER_RETRIES = 6;
const TONCENTER_FALLBACK_RETRY_AFTER_MS = 5000;
const TONCENTER_ORIGINS = new Set([
  new URL(TONCENTER_MAINNET_URL).origin,
  new URL(TONCENTER_TESTNET_URL).origin,
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
    await this.throttle();

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    const signal = mergeAbortSignals(init?.signal, controller.signal);

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
    } finally {
      clearTimeout(timeoutId);
      signal.cleanup?.();
    }
  }

  delayNextRequest(delayMs: number) {
    this.nextAllowedAt = Math.max(this.nextAllowedAt, Date.now() + delayMs);
  }

  private async throttle() {
    this.pending = this.pending.then(async () => {
      const now = Date.now();
      const sinceLastRequestMs = this.lastRequestAt === undefined ? undefined : now - this.lastRequestAt;
      const minDelayRemainingMs = sinceLastRequestMs === undefined
        ? 0
        : this.minDelayMs - sinceLastRequestMs;
      const explicitDelayRemainingMs = this.nextAllowedAt - now;
      const waitMs = Math.max(0, minDelayRemainingMs, explicitDelayRemainingMs);

      if (waitMs > 0) {
        await pause(waitMs);
      }

      this.lastRequestAt = Date.now();
      this.nextAllowedAt = this.lastRequestAt;
    });

    await this.pending;
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
    retries: TONCENTER_RETRIES,
    fallbackRetryAfterMs: TONCENTER_FALLBACK_RETRY_AFTER_MS,
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
  return TONCENTER_ORIGINS.has(url.origin);
}

function getProviderFetcher(origin: string) {
  let fetcher = throttledFetchers.get(origin);
  if (!fetcher) {
    fetcher = new ThrottledFetcher(TONCENTER_MIN_DELAY_MS);
    throttledFetchers.set(origin, fetcher);
  }

  return fetcher;
}

function adjustProviderDelay(origin: string, response: Response) {
  if (response.status !== 429) {
    return;
  }

  const retryAfterMs = getRetryAfterMs(response.headers) ?? TONCENTER_FALLBACK_RETRY_AFTER_MS;
  const fetcher = throttledFetchers.get(origin);
  if (!fetcher) {
    return;
  }

  fetcher.delayNextRequest(Math.max(TONCENTER_MIN_DELAY_MS, retryAfterMs));
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

function mergeAbortSignals(
  signalA?: AbortSignal | null,
  signalB?: AbortSignal | null,
): CleanupAbortSignal {
  if (!signalA) {
    return signalB as CleanupAbortSignal;
  }

  if (!signalB) {
    return signalA as CleanupAbortSignal;
  }

  const controller = new AbortController();
  const abort = () => controller.abort();

  if (signalA.aborted || signalB.aborted) {
    controller.abort();
  } else {
    signalA.addEventListener('abort', abort, { once: true });
    signalB.addEventListener('abort', abort, { once: true });
  }

  const signal = controller.signal as CleanupAbortSignal;
  signal.cleanup = () => {
    signalA.removeEventListener('abort', abort);
    signalB.removeEventListener('abort', abort);
  };

  return signal;
}
