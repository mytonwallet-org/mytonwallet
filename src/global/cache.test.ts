import { CURRENCIES, GLOBAL_STATE_CACHE_KEY } from '../config';
import { loadCache } from './cache';
import { INITIAL_STATE, STATE_VERSION } from './initialState';

describe('loadCache', () => {
  afterEach(() => {
    localStorage.clear();
  });

  function cacheGlobal(partial: Record<string, unknown>) {
    localStorage.setItem(GLOBAL_STATE_CACHE_KEY, JSON.stringify({
      stateVersion: STATE_VERSION,
      ...partial,
    }));
  }

  it('replaces a cached rate that Big cannot parse', () => {
    cacheGlobal({ currencyRates: { ...INITIAL_STATE.currencyRates, TON: 'Infinity' } });

    expect(loadCache(INITIAL_STATE).currencyRates.TON).toBe(CURRENCIES.TON.fallbackRate);
  });

  it('keeps a cached rate that is usable', () => {
    cacheGlobal({ currencyRates: { ...INITIAL_STATE.currencyRates, TON: '0.734524104' } });

    expect(loadCache(INITIAL_STATE).currencyRates.TON).toBe('0.734524104');
  });

  it('restores every currency when the cache holds none', () => {
    cacheGlobal({ currencyRates: {} });

    expect(loadCache(INITIAL_STATE).currencyRates).toEqual(INITIAL_STATE.currencyRates);
  });
});
