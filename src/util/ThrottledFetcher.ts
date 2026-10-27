import type { FetchDemand } from './fetchDemand';

import {
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
} from '../config';
import {
  getAbortReason,
  mergeAbortSignals,
  throwIfAborted,
} from './abortSignal';
import { pause } from './schedulers';

type FetchInput = string | URL | Request;

type QueueEntry = {
  demand?: FetchDemand;
  dispatch: NoneToVoidFunction;
};

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

/**
 * Spaces the requests to one origin. A slot goes to the oldest queued request whose demand is urgent, and otherwise to
 * the oldest queued request. Urgency is read when the slot frees up, so a request that becomes urgent while it waits
 * (see `FetchDemand`) moves ahead of the ones queued before it.
 */
export class ThrottledFetcher {
  private lastRequestAt: number | undefined;
  private nextAllowedAt = 0;
  private queue: QueueEntry[] = [];
  private isDispatching = false;

  constructor(
    private readonly minDelayMs: number,
    private readonly timeoutMs: number = DEFAULT_TIMEOUT_MS,
    private readonly onResult?: (isSuccess: boolean) => void,
  ) {}

  async fetch(
    input: FetchInput,
    init?: RequestInit,
    timeoutMs = this.timeoutMs,
    demand?: FetchDemand,
  ): Promise<Response> {
    // The timer starts before the queue wait, not after it: the caller asked for a deadline on the
    // whole call, and a request parked behind another origin's back-pressure would otherwise wait
    // without any bound of its own.
    const controller = new AbortController();
    const timeoutId = setTimeout(() => {
      controller.abort(new DOMException('Request timed out.', 'TimeoutError'));
    }, timeoutMs);
    const { signal, cleanup } = mergeAbortSignals(init?.signal, controller.signal);

    try {
      await this.waitForSlot(signal, demand);
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

  private waitForSlot(signal?: AbortSignal, demand?: FetchDemand) {
    throwIfAborted(signal);

    return new Promise<void>((resolve, reject) => {
      const handleAbort = () => {
        // A request abandoned in the queue gives its place up without taking a slot
        this.queue = this.queue.filter((queued) => queued !== entry);
        reject(getAbortReason(signal!));
      };
      const entry: QueueEntry = {
        demand,
        dispatch: () => {
          signal?.removeEventListener('abort', handleAbort);
          resolve();
        },
      };

      signal?.addEventListener('abort', handleAbort, { once: true });
      this.queue.push(entry);
      void this.dispatchQueued();
    });
  }

  private async dispatchQueued() {
    if (this.isDispatching) {
      return;
    }

    this.isDispatching = true;
    try {
      while (this.queue.length) {
        // Checked again after every pause, since a 429 can push the next slot further while the queue waits
        const waitMs = this.getWaitMs();
        if (waitMs > 0) {
          await pause(waitMs);
          continue;
        }

        const index = this.queue.findIndex(({ demand }) => demand?.isUrgent());
        const [entry] = this.queue.splice(Math.max(index, 0), 1);
        this.lastRequestAt = Date.now();
        this.nextAllowedAt = this.lastRequestAt;
        entry.dispatch();
      }
    } finally {
      this.isDispatching = false;
    }
  }

  private getWaitMs() {
    const now = Date.now();
    const minDelayRemainingMs = this.lastRequestAt === undefined
      ? 0
      : this.minDelayMs - (now - this.lastRequestAt);

    return Math.max(0, minDelayRemainingMs, this.nextAllowedAt - now);
  }
}

export async function fetchWithThrottledProvider(
  input: FetchInput,
  init?: RequestInit,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  demand?: FetchDemand,
): Promise<Response> {
  const url = getUrl(input);
  if (!url || !shouldThrottleUrl(url)) {
    return new ThrottledFetcher(0, timeoutMs).fetch(input, init, timeoutMs);
  }

  const fetcher = getProviderFetcher(url.origin);
  const response = await fetcher.fetch(input, init, timeoutMs, demand);
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
