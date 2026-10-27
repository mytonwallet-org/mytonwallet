import type { ApiTransactionActivity } from '../api/types';

import { CURRENCIES, GLOBAL_STATE_CACHE_KEY } from '../config';
import { loadCache } from './cache';
import { INITIAL_STATE, STATE_VERSION } from './initialState';

const ACCOUNT_ID = '0-mainnet';

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

  it('keeps existing EVM NFT hide/show choices when provider keys become lowercase', () => {
    const legacyAddress = '0x000000000000888741B254d37e1b27128AfEAaBC/'
      + '5261405894391250505533265397778618870761357154713600';
    const tonAddress = 'EQ-caseSensitiveAddress';
    cacheGlobal({
      stateVersion: 65,
      byAccountId: {
        [ACCOUNT_ID]: {
          blacklistedNftAddresses: [legacyAddress, tonAddress],
          whitelistedNftAddresses: [legacyAddress],
          activities: { byId: { transfer: { kind: 'transaction', nft: { address: legacyAddress } } } },
        },
        'another-account': { whitelistedNftAddresses: [tonAddress] },
      },
    });

    const cached = loadCache(INITIAL_STATE);
    const state = cached.byAccountId[ACCOUNT_ID];
    expect(state.blacklistedNftAddresses).toEqual([legacyAddress.toLowerCase(), tonAddress]);
    expect(state.whitelistedNftAddresses).toEqual([legacyAddress.toLowerCase()]);
    expect((state.activities?.byId.transfer as ApiTransactionActivity).nft?.address).toBe(legacyAddress.toLowerCase());
    expect(cached.byAccountId['another-account'].whitelistedNftAddresses).toEqual([tonAddress]);
  });

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
