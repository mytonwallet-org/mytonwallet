/**
 * @fileoverview Per-process replay cache for deterministic negative (4xx) fetch verdicts.
 *
 * Why this exists: a request whose upstream answer is a deterministic client error
 * (400/404/422 - a malformed or untrackable address) will keep failing identically no
 * matter how often it is re-issued. Trigger-driven re-issue loops (viewport catch-up,
 * polling re-arms) can hammer the same URL for minutes. This cache remembers the verdict
 * for a short TTL so a re-drive of the SAME URL is answered locally instead of contacting
 * the host - collapsing any such storm to <= 1 upstream call per URL per TTL, by construction.
 *
 * Scope: L1, in-process, GET-only (the caller enforces the method). Sibling to the circuit
 * breaker (src/util/circuit-breaker.ts): the breaker guards host health, this guards wasted
 * repeats of a known-terminal request. A replay carries no host-health signal, so the caller
 * must serve it WITHOUT acquiring a breaker slot. Bounded LRU (recency-bumped on read) so a
 * flood of distinct URLs cannot grow it without limit.
 */

export interface NegativeVerdict {
  statusCode: number;
  message: string;
}

interface Entry extends NegativeVerdict {
  expiresAt: number;
}

export interface NegativeVerdictCacheOptions {
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
}

const DEFAULT_TTL_MS = 60_000;
const DEFAULT_MAX_ENTRIES = 128;

export class NegativeVerdictCache {
  private readonly entries = new Map<string, Entry>();
  private readonly ttlMs: number;
  private readonly maxEntries: number;
  private readonly now: () => number;

  constructor(options: NegativeVerdictCacheOptions = {}) {
    this.ttlMs = options.ttlMs ?? DEFAULT_TTL_MS;
    this.maxEntries = options.maxEntries ?? DEFAULT_MAX_ENTRIES;
    this.now = options.now ?? Date.now;
  }

  get(key: string): NegativeVerdict | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;

    if (this.now() >= entry.expiresAt) {
      this.entries.delete(key);
      return undefined;
    }

    // Recency bump: re-insert so the hottest URLs survive eviction longest.
    this.entries.delete(key);
    this.entries.set(key, entry);

    return { statusCode: entry.statusCode, message: entry.message };
  }

  set(key: string, verdict: NegativeVerdict): void {
    if (this.entries.has(key)) {
      this.entries.delete(key);
    }
    this.entries.set(key, { ...verdict, expiresAt: this.now() + this.ttlMs });

    while (this.entries.size > this.maxEntries) {
      const oldest = this.entries.keys().next().value;
      if (oldest === undefined) break;
      this.entries.delete(oldest);
    }
  }

  reset(): void {
    this.entries.clear();
  }
}
