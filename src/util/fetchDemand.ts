// From the global symbol registry, so a demand created by another copy of this module is still recognized
const FETCH_DEMAND_BRAND = Symbol.for('myWallet.fetchDemand');

/**
 * Who waits for a provider request: a request the user is waiting for, or background work. A queued request is
 * dispatched ahead of background ones while its demand is urgent.
 *
 * Urgency is lent along the waits rather than fixed when a request is queued: a demand is urgent while it is urgent
 * itself or while an urgent demand waits for it. Work that several callers share (a cached promise) has a demand of its
 * own, and every caller that waits for that work lends its urgency through `waitFor`. Requests the shared work has
 * already queued, and the ones it queues later, move ahead while an urgent caller waits for them, and fall back once
 * it stops waiting.
 */
export class FetchDemand {
  readonly [FETCH_DEMAND_BRAND] = true;

  private readonly waiters = new Map<FetchDemand, number>();

  constructor(private readonly isUrgentItself = false) {
  }

  isUrgent(): boolean {
    return this.checkUrgent(new Set());
  }

  /** Lends this demand's urgency to `dependency` until `promise` settles */
  async waitFor<T>(dependency: FetchDemand, promise: Promise<T>): Promise<T> {
    if (dependency === this) {
      return promise;
    }

    dependency.waiters.set(this, (dependency.waiters.get(this) ?? 0) + 1);
    try {
      return await promise;
    } finally {
      const count = dependency.waiters.get(this)! - 1;
      if (count) {
        dependency.waiters.set(this, count);
      } else {
        dependency.waiters.delete(this);
      }
    }
  }

  private checkUrgent(visited: Set<FetchDemand>): boolean {
    if (this.isUrgentItself) {
      return true;
    }

    // Shared work can end up waiting for itself through a chain of caches; each demand is asked once
    visited.add(this);
    for (const waiter of this.waiters.keys()) {
      if (!visited.has(waiter) && waiter.checkUrgent(visited)) {
        return true;
      }
    }

    return false;
  }
}

export function createUrgentFetchDemand() {
  return new FetchDemand(true);
}

export function isFetchDemand(value: unknown): value is FetchDemand {
  return !!value
    && typeof value === 'object'
    && (value as { [FETCH_DEMAND_BRAND]?: unknown })[FETCH_DEMAND_BRAND] === true;
}
