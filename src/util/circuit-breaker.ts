/**
 * @fileoverview Per-bucket circuit breaker for fetch retry storms.
 *
 * State machine per bucket key:
 *   closed -> open (after N consecutive failures)
 *   open -> half-open (after openMs cooldown)
 *   half-open + probe success -> closed
 *   half-open + probe failure -> open (cooldown refreshed)
 *
 * One probe at a time in the half-open window; concurrent acquire() during the
 * window returns undefined and the caller should fail fast by throwing
 * CircuitOpenError (exported from this module).
 *
 * CircuitOpenError extends ApiBaseError directly (NOT ApiServerError) - by
 * design. Many catches in the codebase narrow on `instanceof ApiServerError`
 * to fall back to offline behaviour (see src/api/chains/ton/auth.ts). A
 * breaker-open should propagate as a transient infrastructure error, not be
 * silently downgraded to "server returned an error".
 *
 * # Wiring contract (read before adding the first caller)
 *
 * acquire() is per logical call, NOT per retry attempt. The retry budget
 * belongs to the caller; the breaker counts one verdict per logical call.
 * Place acquire() OUTSIDE any retry loop and settle the slot exactly once
 * based on the final outcome.
 *
 * # Verdict semantics
 *
 * - recordSuccess()  - host responded with a usable answer (2xx, OR a 4xx
 *                      with a meaningful error body - host is alive, request
 *                      was wrong). Resets the failure counter.
 * - recordFailure()  - host did not respond, or responded with an unusable
 *                      error (5xx, timeout, transport failure). Counts toward
 *                      the trip threshold.
 * - cancelled()      - caller bailed and has no information about host health
 *                      (AbortError from caller's signal, component unmount,
 *                      account switch). Releases the slot without verdicting.
 *
 * AbortError from the CALLER's signal is NOT a host-health signal - use
 * cancelled(), not recordSuccess() or recordFailure(). A 4xx is a host-health
 * signal - use recordSuccess() even if the caller short-circuits the retry
 * budget (host responded, the request was wrong).
 *
 * # Canonical wiring pattern
 *
 *   const key = bucketKey(url);
 *   const slot = breaker.acquire(key);
 *   if (!slot) throw new CircuitOpenError(key);
 *   let settled = false;
 *   try {
 *     const response = await fetchWithRetry(url, init, options);
 *     slot.recordSuccess(); settled = true;
 *     return response;
 *   } catch (err) {
 *     if (isCallerAbort(err, init?.signal)) { slot.cancelled(); }
 *     else if (isClientError(err)) { slot.recordSuccess(); }     // 4xx
 *     else { slot.recordFailure(); }                              // 5xx, timeout, transport
 *     settled = true;
 *     throw err;
 *   } finally {
 *     if (!settled) slot.cancelled();                             // safety net
 *   }
 *
 * # Bucket key
 *
 * Use bucketKey(url) for shared-pool upstreams (toncenter - one bucket per
 * origin, since all endpoints share upstream rate-limit pools). Use
 * bucketKey(url, { includePathPrefix: true }) for our own backend
 * (per-endpoint SLA divergence - a slow /assets must not gate /currency-rates,
 * /swap, /referrer, etc.).
 *
 * # Known limitations
 *
 * - Slot leak: if a caller forgets to settle and bypasses the finally block
 *   (process crash, unhandled rejection), the probe slot stays held forever
 *   until reset(). No internal watchdog deadline.
 * - Bucket Map grows unbounded; reset() is the only eviction.
 * - now() defaults to Date.now which is non-monotonic; wall-clock jumps can
 *   skew the cooldown. Pass a monotonic clock if this matters.
 *
 * Pure in-process state. Each Worker/WebView instance has its own breakers;
 * this is not a cross-client coordination primitive.
 *
 * Peer artifact: src/util/fetch.ts (the sole intended production caller).
 */

import { ApiBaseError } from '../api/errors';

const DEFAULT_FAILURE_THRESHOLD = 5;
const DEFAULT_OPEN_MS = 30_000;

interface BucketState {
  consecutiveFailures: number;
  openedAt: number | undefined;
  currentProbeId: number;
}

export interface BreakerSlot {
  recordSuccess(): void;
  recordFailure(): void;
  cancelled(): void;
}

export interface CircuitBreakerOptions {
  failureThreshold?: number;
  openMs?: number;
  now?: () => number;
}

export class CircuitOpenError extends ApiBaseError {
  constructor(public readonly bucket: string) {
    super(`Circuit breaker open for ${bucket}`);
  }
}

export class CircuitBreaker {
  private readonly buckets = new Map<string, BucketState>();
  private nextProbeId = 1;
  private readonly failureThreshold: number;
  private readonly openMs: number;
  private readonly now: () => number;

  constructor(options: CircuitBreakerOptions = {}) {
    const failureThreshold = options.failureThreshold ?? DEFAULT_FAILURE_THRESHOLD;
    const openMs = options.openMs ?? DEFAULT_OPEN_MS;
    if (!Number.isInteger(failureThreshold) || failureThreshold < 1) {
      throw new Error(
        `CircuitBreaker: failureThreshold must be a positive integer, got ${failureThreshold}`,
      );
    }
    if (!Number.isFinite(openMs) || openMs < 0) {
      throw new Error(
        `CircuitBreaker: openMs must be a non-negative finite number, got ${openMs}`,
      );
    }
    this.failureThreshold = failureThreshold;
    this.openMs = openMs;
    this.now = options.now ?? Date.now;
  }

  acquire(key: string): BreakerSlot | undefined {
    const state = this.getState(key);

    if (state.openedAt !== undefined) {
      if (this.now() - state.openedAt < this.openMs) return undefined;
      if (state.currentProbeId !== 0) return undefined;
      const probeId = this.nextProbeId++;
      state.currentProbeId = probeId;
      return this.makeSlot(state, probeId);
    }

    return this.makeSlot(state, 0);
  }

  reset(): void {
    this.buckets.clear();
  }

  private getState(key: string): BucketState {
    let state = this.buckets.get(key);
    if (!state) {
      state = { consecutiveFailures: 0, openedAt: undefined, currentProbeId: 0 };
      this.buckets.set(key, state);
    }
    return state;
  }

  private makeSlot(state: BucketState, probeId: number): BreakerSlot {
    let settled = false;
    const isProbe = () => probeId !== 0 && state.currentProbeId === probeId;

    return {
      recordSuccess: () => {
        if (settled) return;
        settled = true;
        if (isProbe()) {
          state.currentProbeId = 0;
          state.consecutiveFailures = 0;
          state.openedAt = undefined;
          return;
        }
        // Non-probe call resolved during an open window: ignore. Only the
        // designated probe is allowed to verdict the breaker, otherwise a
        // pre-trip in-flight 2xx could silently close it.
        if (state.openedAt !== undefined) return;
        state.consecutiveFailures = 0;
      },

      recordFailure: () => {
        if (settled) return;
        settled = true;
        if (isProbe()) {
          state.currentProbeId = 0;
          state.openedAt = this.now();
          return;
        }
        if (state.openedAt !== undefined) return;
        state.consecutiveFailures += 1;
        if (state.consecutiveFailures >= this.failureThreshold) {
          state.openedAt = this.now();
        }
      },

      cancelled: () => {
        if (settled) return;
        settled = true;
        if (isProbe()) {
          state.currentProbeId = 0;
        }
      },
    };
  }
}

/**
 * Derives a bucket key from a URL. By default, the key is the origin - use
 * this for upstreams whose endpoints share a rate-limit pool. Pass
 * `includePathPrefix: true` for upstreams where per-endpoint SLAs diverge
 * (our own backend); the first path segment becomes part of the key.
 *
 * Throws on malformed input rather than collapsing distinct callers into a
 * shared bucket (a degenerate '' or 'null' key would couple unrelated hosts).
 */
export function bucketKey(
  url: string | URL,
  options: { includePathPrefix?: boolean } = {},
): string {
  const urlObject = typeof url === 'string' ? new URL(url) : url;
  if (!options.includePathPrefix) return urlObject.origin;
  const firstSegment = urlObject.pathname.split('/').find(Boolean);
  return firstSegment ? `${urlObject.origin}/${firstSegment}` : urlObject.origin;
}
