import { NegativeVerdictCache } from './negativeVerdictCache';

describe('NegativeVerdictCache', () => {
  let currentTime: number;
  const now = () => currentTime;
  const advance = (ms: number) => {
    currentTime += ms;
  };

  beforeEach(() => {
    currentTime = 1_000_000;
  });

  it('returns undefined for an unknown key', () => {
    const cache = new NegativeVerdictCache({ now });
    expect(cache.get('missing')).toBeUndefined();
  });

  it('replays a stored verdict within the TTL', () => {
    const cache = new NegativeVerdictCache({ ttlMs: 1000, now });
    cache.set('k', { statusCode: 400, message: 'bad request' });
    advance(999);
    expect(cache.get('k')).toEqual({ statusCode: 400, message: 'bad request' });
  });

  it('drops the entry once the TTL elapses', () => {
    const cache = new NegativeVerdictCache({ ttlMs: 1000, now });
    cache.set('k', { statusCode: 404, message: 'nope' });
    advance(1000);
    expect(cache.get('k')).toBeUndefined();
    // Second lookup confirms the expired entry was purged, not just skipped.
    expect(cache.get('k')).toBeUndefined();
  });

  it('evicts the oldest entry when over capacity', () => {
    const cache = new NegativeVerdictCache({ maxEntries: 2, now });
    cache.set('a', { statusCode: 400, message: 'a' });
    cache.set('b', { statusCode: 400, message: 'b' });
    cache.set('c', { statusCode: 400, message: 'c' });
    expect(cache.get('a')).toBeUndefined();
    expect(cache.get('b')).toEqual({ statusCode: 400, message: 'b' });
    expect(cache.get('c')).toEqual({ statusCode: 400, message: 'c' });
  });

  it('bumps recency on read so a hot key survives eviction', () => {
    const cache = new NegativeVerdictCache({ maxEntries: 2, now });
    cache.set('a', { statusCode: 400, message: 'a' });
    cache.set('b', { statusCode: 400, message: 'b' });
    cache.get('a'); // touch a -> a becomes most-recent
    cache.set('c', { statusCode: 400, message: 'c' }); // evicts b, not a
    expect(cache.get('a')).toEqual({ statusCode: 400, message: 'a' });
    expect(cache.get('b')).toBeUndefined();
  });

  it('reset clears all entries', () => {
    const cache = new NegativeVerdictCache({ now });
    cache.set('k', { statusCode: 422, message: 'x' });
    cache.reset();
    expect(cache.get('k')).toBeUndefined();
  });
});
