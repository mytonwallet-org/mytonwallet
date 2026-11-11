import type { ApiCurrencyRates, OnApiUpdate } from '../types';

import { DEFAULT_RETRIES } from '../../config';
import Deferred from '../../util/Deferred';
import { resetFetchStateForTests } from '../../util/fetch';
import { setIsAppFocused } from '../../util/focusAwareDelay';
import { logDebugError } from '../../util/logs';
import {
  checkIsTrustedCollection,
  checkIsTrustedSite,
  getKnownAddresses,
  getNftSuperCollectionsByCollectionAddress,
  getScamMarkers,
  tryUpdateKnownAddresses,
} from '../common/addresses';
import { callBackendGet } from '../common/backend';
import * as cache from '../common/cache';
import { tokensPreload } from '../common/tokens';
import { destroyPolling, initPolling } from './polling';
import { resolveDataPreloadPromise } from './preload';
import { initTokens, refreshTokens } from './tokens';

const mockFetch = jest.fn();
const mockUpdateTokensFromBackend = jest.fn();
const mockStakingCommon = jest.fn();
const mockOnUpdate = jest.fn<void, Parameters<OnApiUpdate>>();

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'), NO_EXTRA_FEATURES: false,
}));
jest.mock('../../util/ThrottledFetcher', () => ({
  fetchWithThrottledProvider: (...args: unknown[]) => mockFetch(...args),
  getProviderFetchRetryPolicy: () => undefined,
  getRetryAfterMs: () => undefined,
}));
jest.mock('../../util/abortSignal', () => ({
  ...jest.requireActual('../../util/abortSignal'),
  pauseWithAbortSignal: () => Promise.resolve(),
}));
jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: { staking: { getCommonData: () => mockStakingCommon() } },
    tron: {},
  },
}));
jest.mock('../../util/logs', () => ({
  ...jest.requireActual('../../util/logs'), logDebugError: jest.fn(),
}));
jest.mock('../environment', () => ({ getEnvironment: () => ({ apiHeaders: {} }) }));
jest.mock('../common/other', () => ({ getClientId: () => 'catalog-polling-test' }));
jest.mock('../common/accounts', () => ({ fetchStoredAccounts: () => Promise.resolve({}) }));
jest.mock('../common/heldTokens', () => ({
  getHeldSlugs: () => new Set(),
  forgetAllHeldTokens: jest.fn(),
  forgetHeldTokens: jest.fn(),
  forgetNetworkHeldTokens: jest.fn(),
  forgetOtherNetworksHeldTokens: jest.fn(),
  recordHeldTokens: jest.fn(),
}));
jest.mock('../common/tokens', () => ({
  ...jest.requireActual('../common/tokens'),
  updateTokensFromBackend: (...args: unknown[]) => mockUpdateTokensFromBackend(...args),
}));
jest.mock('../db', () => ({
  tokenRepository: jest.requireActual('../db/noopRepository').createNoopRepository(),
}));
jest.mock('../storages', () => ({ storage: { getItem: () => Promise.resolve(undefined) } }));
jest.mock('./optional', () => ({
  requireAgentV2Lifecycle: () => ({
    reconcileAgentV2ProtocolVersion: () => Promise.resolve(undefined),
    resolveAgentV2ProtocolVersionForRouting: (version?: string) => version,
  }),
  requireStakingMethods: () => ({
    tryUpdateStakingCommonData: () => jest.requireActual('./staking').tryUpdateStakingCommonData(),
  }),
  requireSwapMethods: () => ({
    swapGetAssetsText: () => jest.requireActual('../common/backend').callBackendGet(
      '/swap/assets', undefined, undefined, undefined, { shouldReturnText: true },
    ),
  }),
  requirePerpsAssets: () => ({ setPerpsAssetsUpdater: () => undefined }),
}));
jest.mock('./preload', () => ({ resolveDataPreloadPromise: jest.fn() }));

const MINUTE = 60_000;
const SWAP_PATH = '/swap/assets';
const KNOWN_PATH = '/known-addresses';
const CATALOGS = [
  { path: SWAP_PATH, period: 10 * MINUTE },
  { path: KNOWN_PATH, period: 5 * MINUTE },
];
const SWAP_TEXT = swapText('TON');
const KNOWN_TEXT = knownText('Known');
const CURRENCY_RATES: ApiCurrencyRates = { USD: '1', EUR: '0.9', RUB: '90', CNY: '7', BTC: '0.00001', TON: '0.3' };

type Reply = { text: string; status?: number; error?: Error; pending?: Promise<void> };
let replies: Record<string, Reply>;

beforeEach(() => {
  jest.useFakeTimers();
  setIsAppFocused(true);
  resetFetchStateForTests();
  mockOnUpdate.mockReset();
  jest.mocked(resolveDataPreloadPromise).mockClear();
  mockFetch.mockReset();
  mockUpdateTokensFromBackend.mockReset().mockImplementation(
    jest.requireActual('../common/tokens').updateTokensFromBackend,
  );
  mockStakingCommon.mockReset().mockImplementation(() => callBackendGet('/staking/common'));
  replies = {
    [SWAP_PATH]: { text: SWAP_TEXT },
    [KNOWN_PATH]: { text: KNOWN_TEXT },
    '/assets/prices': { text: JSON.stringify({ catalogVersion: 'empty', prices: {} }) },
    '/assets/catalog': { text: JSON.stringify({ version: 'empty', assets: [] }) },
    '/staking/common': { text: '{}' },
    '/currency-rates': { text: JSON.stringify({ rates: CURRENCY_RATES }) },
    '/utils/get-config': { text: JSON.stringify({ now: Date.now() }) },
  };
  mockFetch.mockImplementation((url: string | URL) => {
    const path = new URL(url).pathname;
    const reply = replies[path];
    if (!reply) return Promise.reject(new Error(`Unexpected backend path: ${path}`));
    if (reply.error) return Promise.reject(reply.error);
    const status = reply.status ?? 200;
    return Promise.resolve({
      status,
      ok: status >= 200 && status < 300,
      text: () => Promise.resolve(reply.pending).then(() => reply.text),
      json: () => Promise.resolve(reply.pending).then(() => JSON.parse(reply.text)),
      headers: { get: () => undefined },
    } as unknown as Response);
  });
});

afterEach(async () => {
  await destroyPolling();
  jest.clearAllTimers();
  setIsAppFocused(true);
  jest.restoreAllMocks();
  jest.useRealTimers();
});

it('polls common staking and config every five minutes while keeping assets and catalog periods', async () => {
  await startPolling();
  expectCounts([1, 1, 1, 1, 1, 1]);

  await jest.advanceTimersByTimeAsync(30_000);
  expectCounts([1, 1, 1, 1, 1, 1]);
  await jest.advanceTimersByTimeAsync(30_000);
  expectCounts([1, 1, 2, 1, 1, 2]);
  await jest.advanceTimersByTimeAsync(4 * MINUTE - 1);
  expectCounts([1, 1, 5, 1, 1, 5]);
  await jest.advanceTimersByTimeAsync(1);
  expectCounts([1, 2, 6, 2, 2, 6]);
  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expectCounts([1, 2, 10, 2, 2, 10]);
  await jest.advanceTimersByTimeAsync(1);
  expectCounts([2, 3, 11, 3, 3, 11]);

  await destroyPolling();
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expectCounts([2, 3, 11, 3, 3, 11]);
});

it('uses price response rates for five focused minutes and sends only changed rates', async () => {
  const pending = new Deferred();
  replies['/assets/prices'] = {
    text: JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: CURRENCY_RATES }), pending: pending.promise,
  };
  await startPolling();
  expect(requestCount('/currency-rates')).toBe(0);
  expect(resolveDataPreloadPromise).not.toHaveBeenCalled();

  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
  expect(resolveDataPreloadPromise).toHaveBeenCalledTimes(1);

  await jest.advanceTimersByTimeAsync(4 * MINUTE);
  expect(currencyRateUpdates()).toHaveLength(1);
  const changedRates = { ...CURRENCY_RATES, EUR: '0.95' };
  replies['/assets/prices'].text = JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: changedRates });
  await jest.advanceTimersByTimeAsync(MINUTE);

  expect(requestCount('/assets/prices')).toBe(6);
  expect(requestCount('/currency-rates')).toBe(0);
  expect(currencyRateUpdates()).toEqual([
    { type: 'updateCurrencyRates', rates: CURRENCY_RATES },
    { type: 'updateCurrencyRates', rates: changedRates },
  ]);
});

it('fetches fallback rates at five seconds while prices take thirty seconds, then stops fallback polling', async () => {
  const pending = new Deferred();
  const priceRates = { ...CURRENCY_RATES, EUR: '0.95' };
  replies['/assets/prices'] = {
    text: JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: priceRates }), pending: pending.promise,
  };
  setTimeout(() => pending.resolve(), 30_000);
  await startPolling();

  await jest.advanceTimersByTimeAsync(4999);
  expect(requestCount('/currency-rates')).toBe(0);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount('/currency-rates')).toBe(1);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);

  await jest.advanceTimersByTimeAsync(25_000);
  expect(currencyRateUpdates()).toEqual([
    { type: 'updateCurrencyRates', rates: CURRENCY_RATES },
    { type: 'updateCurrencyRates', rates: priceRates },
  ]);
  await jest.advanceTimersByTimeAsync(5 * MINUTE);
  expect(requestCount('/currency-rates')).toBe(1);
});

it('ignores a late fallback response after price rates arrive', async () => {
  const pricesPending = new Deferred();
  const ratesPending = new Deferred();
  const priceRates = { ...CURRENCY_RATES, EUR: '0.95' };
  replies['/assets/prices'] = {
    text: JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: priceRates }), pending: pricesPending.promise,
  };
  replies['/currency-rates'].pending = ratesPending.promise;
  await startPolling();
  await jest.advanceTimersByTimeAsync(5000);
  expect(requestCount('/currency-rates')).toBe(1);

  pricesPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: priceRates }]);
  ratesPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: priceRates }]);
  await jest.advanceTimersByTimeAsync(5 * MINUTE);
  expect(requestCount('/currency-rates')).toBe(1);
});

it('cancels the startup fallback timer when polling stops', async () => {
  const pending = new Deferred();
  replies['/assets/prices'].pending = pending.promise;
  await startPolling();
  await jest.advanceTimersByTimeAsync(4999);
  await destroyPolling();
  await jest.advanceTimersByTimeAsync(MINUTE);
  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);

  expect(requestCount('/currency-rates')).toBe(0);
  expect(currencyRateUpdates()).toEqual([]);
});

it.each(['0', '', 'NaN'])('fetches fallback rates when a price rate is unusable: %p', async (rate) => {
  replies['/assets/prices'].text = JSON.stringify({
    catalogVersion: 'empty', prices: {}, rates: { ...CURRENCY_RATES, EUR: rate },
  });
  await startPolling();

  expect(requestCount('/currency-rates')).toBe(1);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
});

it('resends unchanged price rates when a new UI initializes polling', async () => {
  replies['/assets/prices'].text = JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: CURRENCY_RATES });
  await startPolling();
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
  const nextOnUpdate = jest.fn<void, Parameters<OnApiUpdate>>();

  initPolling(nextOnUpdate);
  await jest.advanceTimersByTimeAsync(0);

  expect(nextOnUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updateCurrencyRates'))
    .toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
  expect(currencyRateUpdates()).toHaveLength(1);
  expect(requestCount('/currency-rates')).toBe(0);
});

it.each([true, false])('resends unchanged rates after clearing caches (price rates: %s)', async (hasPriceRates) => {
  replies['/assets/prices'].text = JSON.stringify({
    catalogVersion: 'empty', prices: {}, ...(hasPriceRates && { rates: CURRENCY_RATES }),
  });
  initTokens(mockOnUpdate);
  await startPolling();
  expect(currencyRateUpdates()).toHaveLength(1);

  await refreshTokens();
  await jest.advanceTimersByTimeAsync(0);

  expect(currencyRateUpdates()).toEqual([
    { type: 'updateCurrencyRates', rates: CURRENCY_RATES },
    { type: 'updateCurrencyRates', rates: CURRENCY_RATES },
  ]);
  expect(requestCount('/assets/prices')).toBe(2);
  expect(requestCount('/currency-rates')).toBe(hasPriceRates ? 0 : 2);
});

it.each([0, 5000])('waits for the initial fallback before preload resolves (price delay: %i ms)', async (delay) => {
  const pricesPending = new Deferred();
  const ratesPending = new Deferred();
  replies['/assets/prices'].pending = pricesPending.promise;
  replies['/currency-rates'].pending = ratesPending.promise;
  await startPolling();
  expect(requestCount('/currency-rates')).toBe(0);
  expect(resolveDataPreloadPromise).not.toHaveBeenCalled();

  await jest.advanceTimersByTimeAsync(delay);
  pricesPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(requestCount('/currency-rates')).toBe(1);
  expect(resolveDataPreloadPromise).not.toHaveBeenCalled();

  ratesPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
  expect(resolveDataPreloadPromise).toHaveBeenCalledTimes(1);
});

it.each(['failure', 'undefined'])('fetches fallback immediately after a price update %s', async (result) => {
  if (result === 'failure') replies['/assets/prices'].error = new Error('Offline');
  else mockUpdateTokensFromBackend.mockResolvedValueOnce(undefined);

  await startPolling();

  expect(requestCount('/currency-rates')).toBe(1);
  expect(currencyRateUpdates()).toEqual([{ type: 'updateCurrencyRates', rates: CURRENCY_RATES }]);
  expect(resolveDataPreloadPromise).toHaveBeenCalledTimes(1);
  if (result === 'failure') expect(requestCount('/assets/prices')).toBe(DEFAULT_RETRIES);
});

it('stops fallback when price rates arrive and resumes immediately when they disappear in the background', async () => {
  setIsAppFocused(false);
  await startPolling();
  expect(requestCount('/currency-rates')).toBe(1);

  const priceRates = { ...CURRENCY_RATES, EUR: '0.95' };
  replies['/assets/prices'].text = JSON.stringify({ catalogVersion: 'empty', prices: {}, rates: priceRates });
  await jest.advanceTimersByTimeAsync(MINUTE + 1);
  expect(currencyRateUpdates().at(-1)).toEqual({ type: 'updateCurrencyRates', rates: priceRates });

  await jest.advanceTimersByTimeAsync(5 * (MINUTE + 1));
  expect(requestCount('/currency-rates')).toBe(1);
  replies['/assets/prices'].text = JSON.stringify({ catalogVersion: 'empty', prices: {} });
  await jest.advanceTimersByTimeAsync(MINUTE + 1);
  expect(requestCount('/currency-rates')).toBe(2);
  expect(currencyRateUpdates().at(-1)).toEqual({ type: 'updateCurrencyRates', rates: CURRENCY_RATES });

  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expect(requestCount('/currency-rates')).toBe(2);
  await jest.advanceTimersByTimeAsync(2);
  expect(requestCount('/currency-rates')).toBe(3);
});

it('keeps common staking and config on failure and retries both at the next five-minute poll', async () => {
  await startPolling();
  const staking = await cache.getStakingCommonCache('ton');
  const config = cache.getBackendConfigCacheSync();
  const error = new Error('Offline');
  replies['/staking/common'].error = error;
  replies['/utils/get-config'].error = error;
  mockOnUpdate.mockClear();

  await jest.advanceTimersByTimeAsync(5 * MINUTE);

  expect(requestCount('/staking/common')).toBe(1 + DEFAULT_RETRIES);
  expect(requestCount('/utils/get-config')).toBe(1 + DEFAULT_RETRIES);
  expect(await cache.getStakingCommonCache('ton')).toBe(staking);
  expect(cache.getBackendConfigCacheSync()).toBe(config);
  expect(mockOnUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'updateConfig' }));
  expect(logDebugError).toHaveBeenCalledWith('tryUpdateStakingCommonData', expect.objectContaining({
    message: expect.stringContaining(`/staking/common | attempts=${DEFAULT_RETRIES} | Offline`),
  }));
  expect(logDebugError).toHaveBeenCalledWith('tryUpdateConfig', expect.objectContaining({
    message: expect.stringContaining(`/utils/get-config | attempts=${DEFAULT_RETRIES} | Offline`),
  }));

  delete replies['/staking/common'].error;
  delete replies['/utils/get-config'].error;
  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expect(requestCount('/staking/common')).toBe(1 + DEFAULT_RETRIES);
  expect(requestCount('/utils/get-config')).toBe(1 + DEFAULT_RETRIES);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount('/staking/common')).toBe(2 + DEFAULT_RETRIES);
  expect(requestCount('/utils/get-config')).toBe(2 + DEFAULT_RETRIES);
  expect(await cache.getStakingCommonCache('ton')).not.toBe(staking);
  expect(cache.getBackendConfigCacheSync()).not.toBe(config);
  expect(mockOnUpdate).toHaveBeenCalledWith(expect.objectContaining({ type: 'updateConfig' }));
});

it.each(['/utils/get-config', '/staking/common'])(
  'retries missing initial %s data after one minute and resumes five-minute polling after success',
  async (path) => {
    const readConfig = cache.getBackendConfigCacheSync;
    const readStaking = cache.getStakingCommonCacheSync;
    const configWrites = jest.spyOn(cache, 'setBackendConfigCache');
    const stakingWrites = jest.spyOn(cache, 'setStakingCommonCache');
    jest.spyOn(cache, 'getBackendConfigCacheSync').mockImplementation(() => (
      configWrites.mock.calls.length ? readConfig() : undefined
    ));
    const readStakingSpy = jest.spyOn(cache, 'getStakingCommonCacheSync').mockImplementation((chain) => (
      stakingWrites.mock.calls.some(([storedChain]) => storedChain === chain) ? readStaking(chain) : undefined
    ));
    replies[path].error = new Error('Offline');
    await startPolling();
    expect(requestCount(path)).toBe(DEFAULT_RETRIES);

    delete replies[path].error;
    await jest.advanceTimersByTimeAsync(MINUTE - 1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES);
    await jest.advanceTimersByTimeAsync(1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES + 1);

    await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES + 1);
    await jest.advanceTimersByTimeAsync(1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES + 2);
    await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES + 2);
    await jest.advanceTimersByTimeAsync(1);
    expect(requestCount(path)).toBe(DEFAULT_RETRIES + 3);
    expect(readStakingSpy).not.toHaveBeenCalledWith('tron');
  },
);

it('keeps catalog polling infrequent while the app is unfocused', async () => {
  setIsAppFocused(false);
  await startPolling();

  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expect(requestCount(SWAP_PATH)).toBe(1);
  expect(requestCount(KNOWN_PATH)).toBe(1);
  expect(requestCount('/currency-rates')).toBe(1);
  await jest.advanceTimersByTimeAsync(2);
  expect(requestCount(SWAP_PATH)).toBe(1);
  expect(requestCount(KNOWN_PATH)).toBe(2);
  expect(requestCount('/currency-rates')).toBe(2);
  await jest.advanceTimersByTimeAsync(5 * MINUTE + 1);
  expect(requestCount(SWAP_PATH)).toBe(2);
  expect(requestCount(KNOWN_PATH)).toBe(3);
  expect(requestCount('/currency-rates')).toBe(3);
});

it.each(CATALOGS)('retries an initial failure after one minute for $path', async ({ path, period }) => {
  const recoveredText = path === SWAP_PATH ? swapText('RECOVERED') : knownText('Recovered');
  replies[path] = { text: recoveredText, error: new Error('Offline') };
  await startPolling();
  const addresses = getKnownAddresses();
  expect(requestCount(path)).toBe(DEFAULT_RETRIES);
  if (path === SWAP_PATH) expect(swapUpdates()).toHaveLength(0);
  delete replies[path].error;

  await jest.advanceTimersByTimeAsync(MINUTE - 1);
  expect(requestCount(path)).toBe(DEFAULT_RETRIES);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount(path)).toBe(DEFAULT_RETRIES + 1);
  if (path === SWAP_PATH) {
    expect(swapUpdates()).toHaveLength(1);
    expect(swapUpdates()[0].tokens.toncoin.symbol).toBe('RECOVERED');
  } else {
    expect(getKnownAddresses()).not.toBe(addresses);
    expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Recovered' } });
  }

  await jest.advanceTimersByTimeAsync(period - 1);
  expect(requestCount(path)).toBe(DEFAULT_RETRIES + 1);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount(path)).toBe(DEFAULT_RETRIES + 2);
});

it.each(CATALOGS)('does not overlap initial or retry requests for $path', async ({ path, period }) => {
  const initialPending = new Deferred();
  replies[path] = { text: '{invalid-json', pending: initialPending.promise };
  await startPolling();
  await jest.advanceTimersByTimeAsync(period - MINUTE);
  expect(requestCount(path)).toBe(1);
  initialPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  await jest.advanceTimersByTimeAsync(MINUTE);
  expect(requestCount(path)).toBe(2);

  const retryPending = new Deferred();
  replies[path] = {
    text: path === SWAP_PATH ? swapText('RECOVERED') : knownText('Recovered'),
    pending: retryPending.promise,
  };
  await jest.advanceTimersByTimeAsync(MINUTE);
  expect(requestCount(path)).toBe(3);
  await jest.advanceTimersByTimeAsync(period);
  expect(requestCount(path)).toBe(3);
  expect(requestCount('/assets/prices')).toBe(2 + 2 * period / MINUTE);

  retryPending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  await jest.advanceTimersByTimeAsync(period - 1);
  expect(requestCount(path)).toBe(3);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount(path)).toBe(4);
});

it('skips parsing, swap updates and known-address reconstruction for unchanged text', async () => {
  await startPolling();
  const addresses = getKnownAddresses();
  const markers = getScamMarkers();
  const collections = await getNftSuperCollectionsByCollectionAddress();
  const parse = jest.spyOn(JSON, 'parse');
  mockOnUpdate.mockClear();

  await jest.advanceTimersByTimeAsync(20 * MINUTE);

  expect(requestCount(SWAP_PATH)).toBe(3);
  expect(requestCount(KNOWN_PATH)).toBe(5);
  expect(parse.mock.calls.filter(([text]) => text === SWAP_TEXT || text === KNOWN_TEXT)).toHaveLength(0);
  expect(swapUpdates()).toHaveLength(0);
  expect(getKnownAddresses()).toBe(addresses);
  expect(getScamMarkers()).toBe(markers);
  expect(await getNftSuperCollectionsByCollectionAddress()).toBe(collections);
  expect(checkIsTrustedSite('trusted.example')).toBe(true);
  expect(checkIsTrustedCollection('EQCollection')).toBe(true);
});

it('applies changed catalogs and compares their exact text including whitespace', async () => {
  await startPolling();
  const initialAddresses = getKnownAddresses();
  replies[SWAP_PATH].text = swapText('NEW');
  replies[KNOWN_PATH].text = knownText('Updated');

  await jest.advanceTimersByTimeAsync(10 * MINUTE);

  expect(swapUpdates()).toHaveLength(2);
  expect(swapUpdates().at(-1)?.tokens.toncoin.symbol).toBe('NEW');
  expect(getKnownAddresses()).not.toBe(initialAddresses);
  expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Updated' } });
  const changedAddresses = getKnownAddresses();
  replies[SWAP_PATH].text += '\n';
  replies[KNOWN_PATH].text += '\n';

  await jest.advanceTimersByTimeAsync(10 * MINUTE);

  expect(swapUpdates()).toHaveLength(3);
  expect(getKnownAddresses()).not.toBe(changedAddresses);
  expect(getKnownAddresses()).toEqual(changedAddresses);
});

it('always requests and applies initial catalogs, including repeated initialization', async () => {
  await startPolling();
  const addresses = getKnownAddresses();
  const firstUpdates = swapUpdates();
  const nextOnUpdate = jest.fn<void, Parameters<OnApiUpdate>>();

  initPolling(nextOnUpdate);
  await jest.advanceTimersByTimeAsync(0);

  expect(requestCount(SWAP_PATH)).toBe(2);
  expect(requestCount(KNOWN_PATH)).toBe(2);
  expect(firstUpdates).toHaveLength(1);
  expect(nextOnUpdate.mock.calls.filter(([update]) => update.type === 'updateSwapTokens')).toHaveLength(1);
  expect(getKnownAddresses()).not.toBe(addresses);
});

it.each([true, false])('ignores old initial responses after restarting with destroy=%s', async (shouldDestroy) => {
  const pending = new Deferred();
  const oldSwapText = swapText('OLD');
  const oldKnownText = knownText('Old', 'old-scam');
  replies[SWAP_PATH] = { text: oldSwapText, pending: pending.promise };
  replies[KNOWN_PATH] = { text: oldKnownText, pending: pending.promise };
  await startPolling();
  expect(swapUpdates()).toHaveLength(0);
  if (shouldDestroy) await destroyPolling();
  const currentSwapText = swapText('CURRENT');
  const currentKnownText = knownText('Current', 'current-scam');
  replies[SWAP_PATH] = { text: currentSwapText };
  replies[KNOWN_PATH] = { text: currentKnownText };
  await startPolling();
  const addresses = getKnownAddresses();
  const markers = getScamMarkers();
  const collections = await getNftSuperCollectionsByCollectionAddress();
  const parse = jest.spyOn(JSON, 'parse');

  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);
  expect(swapUpdates()).toHaveLength(1);
  expect(swapUpdates()[0].tokens.toncoin.symbol).toBe('CURRENT');
  expect(getKnownAddresses()).toBe(addresses);
  expect(getScamMarkers()).toBe(markers);
  expect(await getNftSuperCollectionsByCollectionAddress()).toBe(collections);
  await jest.advanceTimersByTimeAsync(20 * MINUTE);

  expect(requestCount(SWAP_PATH)).toBe(4);
  expect(requestCount(KNOWN_PATH)).toBe(6);
  expect(swapUpdates()).toHaveLength(1);
  expect(swapUpdates()[0].tokens.toncoin.symbol).toBe('CURRENT');
  expect(getKnownAddresses()).toBe(addresses);
  expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Current' } });
  expect(getScamMarkers()).toBe(markers);
  expect(getScamMarkers()[0].source).toBe('current-scam');
  expect(await getNftSuperCollectionsByCollectionAddress()).toBe(collections);
  expect(parse.mock.calls.filter(([text]) => [
    oldSwapText, oldKnownText, currentSwapText, currentKnownText,
  ].includes(text))).toHaveLength(0);
});

it('ignores pending periodic catalog responses after destroy without a successor', async () => {
  await startPolling();
  const addresses = getKnownAddresses();
  const markers = getScamMarkers();
  const collections = await getNftSuperCollectionsByCollectionAddress();
  const pending = new Deferred();
  const oldSwapText = swapText('OLD');
  const oldKnownText = knownText('Old', 'old-scam');
  replies[SWAP_PATH] = { text: oldSwapText, pending: pending.promise };
  replies[KNOWN_PATH] = { text: oldKnownText, pending: pending.promise };
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expect(requestCount(SWAP_PATH)).toBe(2);
  expect(requestCount(KNOWN_PATH)).toBe(2);
  await destroyPolling();
  const parse = jest.spyOn(JSON, 'parse');

  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);

  expect(swapUpdates()).toHaveLength(1);
  expect(getKnownAddresses()).toBe(addresses);
  expect(getScamMarkers()).toBe(markers);
  expect(await getNftSuperCollectionsByCollectionAddress()).toBe(collections);
  expect(parse.mock.calls.filter(([text]) => text === oldSwapText || text === oldKnownText)).toHaveLength(0);
});

it('settles initial NFT collection readiness when the known-address response arrives after destroy', async () => {
  let isolatedAddresses!: typeof import('../common/addresses');
  let isolatedPolling!: typeof import('./polling');
  jest.isolateModules(() => {
    isolatedAddresses = jest.requireActual('../common/addresses');
    isolatedPolling = jest.requireActual('./polling');
  });
  const pending = new Deferred();
  replies[KNOWN_PATH] = { text: knownText('Stale'), pending: pending.promise };
  const addresses = isolatedAddresses.getKnownAddresses();
  const collections = isolatedAddresses.getNftSuperCollectionsByCollectionAddress();
  const onCollectionsReady = jest.fn();
  void collections.then(onCollectionsReady);
  isolatedPolling.initPolling(mockOnUpdate);
  await jest.advanceTimersByTimeAsync(0);
  expect(requestCount(KNOWN_PATH)).toBe(1);
  expect(onCollectionsReady).not.toHaveBeenCalled();
  await isolatedPolling.destroyPolling();

  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);

  expect(onCollectionsReady).toHaveBeenCalledTimes(1);
  expect(await collections).toEqual({});
  expect(isolatedAddresses.getKnownAddresses()).toBe(addresses);
  expect(isolatedAddresses.getKnownAddresses()).toEqual({});
});

it('ignores a swap response when polling stops while waiting for token preload', async () => {
  await startPolling();
  const pending = new Deferred();
  jest.replaceProperty(tokensPreload, 'promise', pending.promise);
  replies[SWAP_PATH].text = swapText('OLD');
  const parse = jest.spyOn(JSON, 'parse');
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expect(parse.mock.calls.filter(([text]) => text === replies[SWAP_PATH].text)).toHaveLength(1);
  expect(swapUpdates()).toHaveLength(1);
  await destroyPolling();

  pending.resolve();
  await jest.advanceTimersByTimeAsync(0);

  expect(swapUpdates()).toHaveLength(1);
});

it('keeps direct known-address refreshes unconditional', async () => {
  await startPolling();
  const addresses = getKnownAddresses();

  await tryUpdateKnownAddresses();

  expect(requestCount(KNOWN_PATH)).toBe(2);
  expect(getKnownAddresses()).not.toBe(addresses);
  expect(getKnownAddresses()).toEqual(addresses);
});

it('starts with empty response caches after destroy even if the next initial requests fail', async () => {
  await startPolling();
  const addresses = getKnownAddresses();
  await destroyPolling();
  replies[SWAP_PATH].error = new Error('Offline');
  replies[KNOWN_PATH].error = new Error('Offline');
  mockOnUpdate.mockClear();

  await startPolling();
  expect(swapUpdates()).toHaveLength(0);
  expect(getKnownAddresses()).toBe(addresses);
  delete replies[SWAP_PATH].error;
  delete replies[KNOWN_PATH].error;

  await jest.advanceTimersByTimeAsync(10 * MINUTE);

  expect(swapUpdates()).toHaveLength(1);
  expect(getKnownAddresses()).not.toBe(addresses);
});

it.each(CATALOGS)('retries malformed JSON without remembering it for $path', async ({ path, period }) => {
  await startPolling();
  const addresses = getKnownAddresses();
  const invalidText = '{invalid-json';
  replies[path].text = invalidText;
  const parse = jest.spyOn(JSON, 'parse');

  await jest.advanceTimersByTimeAsync(2 * period);

  expect(parse.mock.calls.filter(([text]) => text === invalidText)).toHaveLength(2);
  expect(swapUpdates()).toHaveLength(1);
  expect(getKnownAddresses()).toBe(addresses);
  replies[path].text = path === SWAP_PATH ? swapText('RECOVERED') : knownText('Recovered');
  await jest.advanceTimersByTimeAsync(period);
  if (path === SWAP_PATH) {
    expect(swapUpdates()).toHaveLength(2);
    expect(swapUpdates().at(-1)?.tokens.toncoin.symbol).toBe('RECOVERED');
  } else {
    expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Recovered' } });
  }
});

it.each(CATALOGS.flatMap((catalog) => [
  { ...catalog, failure: 'network', attempts: DEFAULT_RETRIES },
  { ...catalog, failure: '503', attempts: DEFAULT_RETRIES },
  { ...catalog, failure: '304', attempts: 1 },
]))('keeps the last applied text after $failure for $path', async ({ path, period, failure, attempts }) => {
  await startPolling();
  const addresses = getKnownAddresses();
  const originalText = replies[path].text;
  const changedText = path === SWAP_PATH ? swapText('RECOVERED') : knownText('Recovered');
  replies[path] = {
    text: changedText,
    ...(failure === 'network' ? { error: new Error('Offline') } : { status: Number(failure) }),
  };

  await jest.advanceTimersByTimeAsync(period);

  expect(requestCount(path)).toBe(1 + attempts);
  expect(swapUpdates()).toHaveLength(1);
  expect(getKnownAddresses()).toBe(addresses);
  replies[path] = { text: originalText };
  await jest.advanceTimersByTimeAsync(period - 1);
  expect(requestCount(path)).toBe(1 + attempts);
  await jest.advanceTimersByTimeAsync(1);
  expect(requestCount(path)).toBe(2 + attempts);
  expect(swapUpdates()).toHaveLength(1);
  expect(getKnownAddresses()).toBe(addresses);
  replies[path] = { text: changedText };
  await jest.advanceTimersByTimeAsync(period);
  if (path === SWAP_PATH) {
    expect(swapUpdates()).toHaveLength(2);
    expect(swapUpdates().at(-1)?.tokens.toncoin.symbol).toBe('RECOVERED');
  } else {
    expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Recovered' } });
  }
});

it('retries swap text after its update callback fails', async () => {
  await startPolling();
  replies[SWAP_PATH].text = swapText('RETRY');
  let shouldThrow = true;
  mockOnUpdate.mockImplementation((update) => {
    if (update.type === 'updateSwapTokens' && shouldThrow) throw new Error('Update failed');
  });

  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expect(swapUpdates()).toHaveLength(2);
  shouldThrow = false;
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expect(swapUpdates()).toHaveLength(3);
  expect(swapUpdates().at(-1)?.tokens.toncoin.symbol).toBe('RETRY');
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expect(swapUpdates()).toHaveLength(3);
});

it('preserves known-address structures and retries text whose scam markers cannot be applied', async () => {
  await startPolling();
  const addresses = getKnownAddresses();
  const markers = getScamMarkers();
  const collections = await getNftSuperCollectionsByCollectionAddress();
  const invalidText = JSON.stringify({ ...JSON.parse(knownText('Invalid')), scamMarkers: ['['] });
  replies[KNOWN_PATH].text = invalidText;
  const parse = jest.spyOn(JSON, 'parse');

  await jest.advanceTimersByTimeAsync(10 * MINUTE);

  expect(parse.mock.calls.filter(([text]) => text === invalidText)).toHaveLength(2);
  expect(getKnownAddresses()).toBe(addresses);
  expect(getScamMarkers()).toBe(markers);
  expect(await getNftSuperCollectionsByCollectionAddress()).toBe(collections);
  replies[KNOWN_PATH].text = knownText('Recovered');
  await jest.advanceTimersByTimeAsync(5 * MINUTE);
  expect(getKnownAddresses()).toEqual({ EQKnown: { name: 'Recovered' } });
});

async function startPolling() {
  initPolling(mockOnUpdate);
  await jest.advanceTimersByTimeAsync(0);
}

function requestCount(path: string) {
  return mockFetch.mock.calls.filter(([url]) => new URL(url).pathname === path).length;
}

function expectCounts(counts: number[]) {
  expect([
    SWAP_PATH, KNOWN_PATH, '/assets/prices', '/staking/common', '/utils/get-config', '/currency-rates',
  ].map(requestCount)).toEqual(counts);
}

function swapUpdates() {
  return mockOnUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updateSwapTokens');
}

function currencyRateUpdates() {
  return mockOnUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updateCurrencyRates');
}

function swapText(symbol: string) {
  return JSON.stringify([{ slug: 'toncoin', chain: 'ton', symbol, name: 'Toncoin', decimals: 9 }]);
}

function knownText(name: string, scamMarker = 'scam') {
  return JSON.stringify({
    knownAddresses: { EQKnown: { name } },
    scamMarkers: [scamMarker],
    trustedSites: ['trusted.example'],
    trustedCollections: ['EQCollection'],
    tonNftSuperCollections: [{ name, collections: ['EQCollection'] }],
  });
}
