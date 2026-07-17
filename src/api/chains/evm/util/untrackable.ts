/**
 * @fileoverview Per-process registry of EVM wallet addresses Zerion deterministically rejects.
 *
 * Why this exists: Zerion answers a deterministic 4xx (400/404/422 - "untrackable wallet
 * address") for burn / malformed / unindexed addresses on BOTH the transactions and positions
 * endpoints. Without memory of that verdict, the swallow-and-retry activity/polling loops keep
 * re-issuing the same request forever (the 2026-07-15 storm). Marking the address terminal here
 * lets the EVM adapter return an empty, FINAL result (history end reached / no positions) so the
 * caller state converges and the re-drive loops stop on their own - the root fix, not a backstop.
 *
 * Keyed by (network, lowercased address) - it is an address-level verdict, shared across both
 * endpoints. TTL-bounded so a wallet that later becomes trackable recovers automatically. The
 * caller gates use of this registry behind the neg-verdict-cache feature flag; the registry
 * itself is pure. Sibling to the L1 fetch-level replay cache (src/util/negativeVerdictCache.ts):
 * that one saves network per URL, this one converges the activity state machine per address.
 */

export interface UntrackableRegistryOptions {
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
}

const DEFAULT_TTL_MS = 10 * 60_000;
const DEFAULT_MAX_ENTRIES = 2048;

export class UntrackableRegistry {
  private readonly expiries = new Map<string, number>();
  private readonly ttlMs: number;
  private readonly maxEntries: number;
  private readonly now: () => number;

  constructor(options: UntrackableRegistryOptions = {}) {
    this.ttlMs = options.ttlMs ?? DEFAULT_TTL_MS;
    this.maxEntries = options.maxEntries ?? DEFAULT_MAX_ENTRIES;
    this.now = options.now ?? Date.now;
  }

  mark(network: string, address: string): void {
    // Refresh recency (delete then set moves the key to the tail) so eviction drops the oldest.
    const key = keyOf(network, address);
    this.expiries.delete(key);
    this.expiries.set(key, this.now() + this.ttlMs);

    while (this.expiries.size > this.maxEntries) {
      const oldest = this.expiries.keys().next().value;
      if (oldest === undefined) break;
      this.expiries.delete(oldest);
    }
  }

  has(network: string, address: string): boolean {
    const key = keyOf(network, address);
    const expiresAt = this.expiries.get(key);
    if (expiresAt === undefined) return false;

    if (this.now() >= expiresAt) {
      this.expiries.delete(key);
      return false;
    }

    return true;
  }

  reset(): void {
    this.expiries.clear();
  }
}

function keyOf(network: string, address: string): string {
  return `${network}:${address.toLowerCase()}`;
}

/** Shared singleton used by the EVM fetch adapters. Tests construct their own instance. */
export const untrackableRegistry = new UntrackableRegistry();
