import { ApiBaseError, ApiServerError } from '../api/errors';
import { bucketKey, CircuitBreaker, CircuitOpenError } from './circuit-breaker';

describe('CircuitBreaker', () => {
  let currentTime: number;
  const now = () => currentTime;
  const advance = (ms: number) => {
    currentTime += ms;
  };

  beforeEach(() => {
    currentTime = 1_000_000;
  });

  describe('closed state', () => {
    it('returns a slot on acquire', () => {
      const cb = new CircuitBreaker({ now });
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('failures below threshold keep breaker closed', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, now });
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('opens exactly at threshold consecutive failures', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, now });
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
    });

    it('opens on first failure when threshold is 1', () => {
      const cb = new CircuitBreaker({ failureThreshold: 1, now });
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
    });

    it('success resets failure counter', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, now });
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordSuccess();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('cancelled is a no-op for non-probe slot', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, now });
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.cancelled();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
    });
  });

  describe('open state within cooldown', () => {
    const tripCircuit = (cb: CircuitBreaker) => {
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
    };

    it('returns undefined on acquire within cooldown', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(29999);
      expect(cb.acquire('host')).toBeUndefined();
    });
  });

  describe('half-open state', () => {
    const tripCircuit = (cb: CircuitBreaker) => {
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
    };

    it('returns a probe slot once cooldown elapses', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('blocks concurrent acquire while a probe is in flight', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      expect(cb.acquire('host')).not.toBeUndefined();
      expect(cb.acquire('host')).toBeUndefined();
    });

    it('probe success closes the breaker and resets counter', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      cb.acquire('host')!.recordSuccess();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('probe failure re-opens for a full cooldown', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
      advance(29999);
      expect(cb.acquire('host')).toBeUndefined();
      advance(1);
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('probe cancelled releases the slot without verdicting', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      cb.acquire('host')!.cancelled();
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('cancelled probe does not close the breaker', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      tripCircuit(cb);
      advance(30000);
      cb.acquire('host')!.cancelled();
      const probe2 = cb.acquire('host')!;
      probe2.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
    });
  });

  describe('in-flight call resolving after trip', () => {
    it('non-probe success during open does not close the breaker', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      const inFlight = cb.acquire('host')!;
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
      inFlight.recordSuccess();
      expect(cb.acquire('host')).toBeUndefined();
    });

    it('non-probe failure during open does not refresh cooldown', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      const inFlight = cb.acquire('host')!;
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
      advance(15000);
      inFlight.recordFailure();
      advance(15000);
      expect(cb.acquire('host')).not.toBeUndefined();
    });
  });

  describe('slot idempotency', () => {
    it('records the first verdict and ignores subsequent calls on the same slot', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      const slot = cb.acquire('host')!;
      slot.recordFailure();
      slot.recordSuccess();
      slot.cancelled();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
    });

    it('duplicate recordFailure on same slot counts once', () => {
      // Threshold 2: if duplicates leaked, the three calls on `slot` would
      // already trip the breaker before the second acquire even runs.
      const cb = new CircuitBreaker({ failureThreshold: 2, now });
      const slot = cb.acquire('host')!;
      slot.recordFailure();
      slot.recordFailure();
      slot.recordFailure();
      expect(cb.acquire('host')).not.toBeUndefined();
    });
  });

  describe('bucket isolation', () => {
    it('tripping one bucket does not affect another', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, now });
      for (let i = 0; i < 3; i++) cb.acquire('host-a')!.recordFailure();
      expect(cb.acquire('host-a')).toBeUndefined();
      expect(cb.acquire('host-b')).not.toBeUndefined();
    });

    it('half-open probe on one bucket does not block another', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      for (let i = 0; i < 3; i++) cb.acquire('host-a')!.recordFailure();
      advance(30000);
      expect(cb.acquire('host-a')).not.toBeUndefined();
      expect(cb.acquire('host-b')).not.toBeUndefined();
    });
  });

  describe('constructor validation', () => {
    it('rejects failureThreshold of 0', () => {
      expect(() => new CircuitBreaker({ failureThreshold: 0 })).toThrow(/failureThreshold/);
    });

    it('rejects negative failureThreshold', () => {
      expect(() => new CircuitBreaker({ failureThreshold: -1 })).toThrow(/failureThreshold/);
    });

    it('rejects non-integer failureThreshold', () => {
      expect(() => new CircuitBreaker({ failureThreshold: 2.5 })).toThrow(/failureThreshold/);
    });

    it('rejects NaN failureThreshold', () => {
      expect(() => new CircuitBreaker({ failureThreshold: NaN })).toThrow(/failureThreshold/);
    });

    it('rejects negative openMs', () => {
      expect(() => new CircuitBreaker({ openMs: -1 })).toThrow(/openMs/);
    });

    it('rejects NaN openMs', () => {
      expect(() => new CircuitBreaker({ openMs: NaN })).toThrow(/openMs/);
    });

    it('rejects Infinity openMs', () => {
      expect(() => new CircuitBreaker({ openMs: Infinity })).toThrow(/openMs/);
    });

    it('accepts openMs of 0', () => {
      expect(() => new CircuitBreaker({ openMs: 0 })).not.toThrow();
    });

    it('accepts failureThreshold of 1', () => {
      expect(() => new CircuitBreaker({ failureThreshold: 1 })).not.toThrow();
    });
  });

  describe('reset', () => {
    it('clears all bucket state', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).toBeUndefined();
      cb.reset();
      expect(cb.acquire('host')).not.toBeUndefined();
    });

    it('settling a stale slot after reset has no effect on new state', () => {
      const cb = new CircuitBreaker({ failureThreshold: 3, openMs: 30000, now });
      for (let i = 0; i < 3; i++) cb.acquire('host')!.recordFailure();
      advance(30000);
      const probe = cb.acquire('host')!;
      cb.reset();
      probe.recordFailure();
      cb.acquire('host')!.recordFailure();
      cb.acquire('host')!.recordFailure();
      expect(cb.acquire('host')).not.toBeUndefined();
    });
  });
});

describe('CircuitOpenError', () => {
  it('extends ApiBaseError', () => {
    expect(new CircuitOpenError('host')).toBeInstanceOf(ApiBaseError);
  });

  // Critical: many catches in the codebase narrow on `instanceof ApiServerError`
  // to fall back to offline behaviour (e.g. src/api/chains/ton/auth.ts cascade).
  // CircuitOpenError must NOT match that filter, otherwise a tripped breaker
  // would silently downgrade a wallet import into an offline-wallet result.
  it('is NOT an ApiServerError', () => {
    expect(new CircuitOpenError('host')).not.toBeInstanceOf(ApiServerError);
  });

  it('carries the bucket key', () => {
    expect(new CircuitOpenError('api.example.com').bucket).toBe('api.example.com');
  });
});

describe('bucketKey', () => {
  it('returns origin by default', () => {
    expect(bucketKey('https://toncenter.com/api/v2/getWalletInformation')).toBe('https://toncenter.com');
  });

  it('preserves port in origin', () => {
    expect(bucketKey('https://example.com:8443/foo')).toBe('https://example.com:8443');
  });

  it('appends first path segment when includePathPrefix is true', () => {
    expect(bucketKey('https://api.backend.example/swap/quote', { includePathPrefix: true }))
      .toBe('https://api.backend.example/swap');
  });

  it('falls back to origin when path has no segments', () => {
    expect(bucketKey('https://api.backend.example/', { includePathPrefix: true }))
      .toBe('https://api.backend.example');
  });

  it('accepts URL object', () => {
    expect(bucketKey(new URL('https://toncenter.com/api'))).toBe('https://toncenter.com');
  });

  it('throws on malformed input rather than collapsing into shared bucket', () => {
    expect(() => bucketKey('not-a-url')).toThrow();
  });
});
