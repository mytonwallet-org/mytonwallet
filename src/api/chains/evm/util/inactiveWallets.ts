/**
 * @fileoverview Short-lived memory of "this address has nothing on this chain yet".
 *
 * This is separate from `withCacheAsync` because the two verdicts of `getIsWalletActive` expire
 * differently. "Active" is monotonic - an address that has held a balance or received a transfer
 * can never stop having done so - so the truthy-only cache around it needs no expiry. "Inactive"
 * is revocable by the next block, and a verdict kept for the whole process would leave a wallet
 * that receives its first funds mid-session showing an empty feed until restart. Hence the TTL
 * here, and none on the positive half.
 *
 * Keyed by (network, chain, lowercased address) - unlike the untrackable registry this is a
 * per-chain fact, since an address can be busy on one chain and untouched on another. Bounded
 * LRU so a wallet holding many chains cannot grow it without limit.
 */

const DEFAULT_TTL_MS = 10 * 60_000;
const DEFAULT_MAX_ENTRIES = 512;

export interface InactiveWalletRegistryOptions {
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
}

export class InactiveWalletRegistry {
  private readonly expiries = new Map<string, number>();
  private readonly ttlMs: number;
  private readonly maxEntries: number;
  private readonly now: () => number;

  constructor(options: InactiveWalletRegistryOptions = {}) {
    this.ttlMs = options.ttlMs ?? DEFAULT_TTL_MS;
    this.maxEntries = options.maxEntries ?? DEFAULT_MAX_ENTRIES;
    this.now = options.now ?? Date.now;
  }

  mark(network: string, chain: string, address: string): void {
    const key = buildKey(network, chain, address);
    // Delete before set so the key moves to the tail: Map preserves insertion order, which
    // makes the first key the oldest and eviction below an LRU rather than an arbitrary drop.
    this.expiries.delete(key);
    this.expiries.set(key, this.now() + this.ttlMs);

    while (this.expiries.size > this.maxEntries) {
      const oldest = this.expiries.keys().next();
      if (oldest.done) break;
      this.expiries.delete(oldest.value);
    }
  }

  forget(network: string, chain: string, address: string): void {
    this.expiries.delete(buildKey(network, chain, address));
  }

  reset(): void {
    this.expiries.clear();
  }

  has(network: string, chain: string, address: string): boolean {
    const key = buildKey(network, chain, address);
    const expiresAt = this.expiries.get(key);
    if (expiresAt === undefined) {
      return false;
    }

    if (expiresAt <= this.now()) {
      this.expiries.delete(key);
      return false;
    }

    // Re-seat the key at the tail so the cap evicts by last use rather than by first mark.
    // The expiry travels unchanged: a read is evidence the entry is worth keeping, not evidence
    // that the address is still empty.
    this.expiries.delete(key);
    this.expiries.set(key, expiresAt);

    return true;
  }
}

function buildKey(network: string, chain: string, address: string): string {
  return `${network}:${chain}:${address.toLowerCase()}`;
}

export const inactiveWallets = new InactiveWalletRegistry();
