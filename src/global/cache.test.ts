import '../util/bigintPatch';

import type { ApiHistoryList, ApiPerpsOperation, ApiTransactionActivity } from '../api/types';
import type { GlobalState } from './types';

import { CURRENCIES, GLOBAL_STATE_CACHE_KEY, TONCOIN } from '../config';
import { DAY, HOUR, MINUTE, SECOND } from '../util/dateFormat';
import { loadCache, persistCache } from './cache';
import { setGlobal } from './index';
import { INITIAL_STATE, STATE_VERSION } from './initialState';

const ACCOUNT_ID = '0-mainnet';
const CURRENT_TOKEN_SLUG = 'ton-current-token';
const UNUSED_TOKEN_SLUG = 'ton-unused-token';

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

  it('accepts account caches from before Perps operation persistence', () => {
    cacheGlobal({ byAccountId: { [ACCOUNT_ID]: { savedAddresses: [] } } });
    expect(loadCache(INITIAL_STATE).byAccountId[ACCOUNT_ID].perpsOperations).toBeUndefined();
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

  it('restores only fresh price history, apart from the history of this session', () => {
    const freshHistory = buildPriceHistory(HOUR);
    cacheGlobal({
      tokenPriceHistory: {
        bySlug: {
          [TONCOIN.slug]: { '1Y': freshHistory, '1D': buildPriceHistory(DAY) },
          [UNUSED_TOKEN_SLUG]: { '1Y': [] },
        },
      },
    });

    expect(loadCache(INITIAL_STATE).tokenPriceHistory).toEqual({
      bySlug: {},
      restoredBySlug: { [TONCOIN.slug]: { '1Y': freshHistory } },
    });
  });
});

describe('persistCache', () => {
  afterEach(() => {
    localStorage.clear();
  });

  it('restores pending Perps operations and exact reduction amounts after relaunch', () => {
    const operation: ApiPerpsOperation = {
      id: 'reduce-1', accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'reduce',
      state: 'partial', stage: 'withdrawal', createdAt: 1, orderId: 123,
      withdrawalRequestedAmount: '5.123456',
    };
    setGlobal({
      ...INITIAL_STATE,
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: { perpsOperations: { [operation.id]: operation } } },
    });

    persistCache();

    expect(loadCache(INITIAL_STATE).byAccountId[ACCOUNT_ID].perpsOperations).toEqual({
      [operation.id]: operation,
    });
  });

  it.each([undefined, { dislike: true }])('keeps agent and support reaction toasts after relaunch (%j)', (
    shownSupport,
  ) => {
    setGlobal({
      ...INITIAL_STATE,
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
      settings: {
        ...INITIAL_STATE.settings,
        shownAgentFeedbackToasts: { like: true },
        shownAgentSupportFeedbackToasts: shownSupport,
      },
    });

    persistCache();

    const { settings } = loadCache(INITIAL_STATE);
    expect(settings.shownAgentFeedbackToasts).toEqual({ like: true });
    expect(settings.shownAgentSupportFeedbackToasts).toEqual(shownSupport);
  });

  it('stores price history of the selected period, preferring the history of this session', () => {
    const sessionHistory = buildPriceHistory(MINUTE);
    const restoredHistory = buildPriceHistory(HOUR);
    setGlobal({
      ...INITIAL_STATE,
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: {} } } },
      byAccountId: { [ACCOUNT_ID]: { currentTokenSlug: CURRENT_TOKEN_SLUG, currentTokenPeriod: '1Y' } },
      tokenPriceHistory: {
        bySlug: {
          [TONCOIN.slug]: { '1Y': sessionHistory, '1D': sessionHistory },
        },
        restoredBySlug: {
          [TONCOIN.slug]: { '1Y': restoredHistory },
          [CURRENT_TOKEN_SLUG]: { '1Y': restoredHistory },
          [UNUSED_TOKEN_SLUG]: { '1Y': restoredHistory },
        },
      },
    });

    persistCache();

    const cached = JSON.parse(localStorage.getItem(GLOBAL_STATE_CACHE_KEY)!) as GlobalState;
    expect(cached.tokenPriceHistory).toEqual({
      bySlug: {
        [TONCOIN.slug]: { '1Y': sessionHistory },
        [CURRENT_TOKEN_SLUG]: { '1Y': restoredHistory },
      },
      restoredBySlug: {},
    });
  });
});

function buildPriceHistory(age: number): ApiHistoryList {
  const lastTimestamp = Math.round((Date.now() - age) / SECOND);

  return [[lastTimestamp - DAY / SECOND, 1], [lastTimestamp, 2]];
}
