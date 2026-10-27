import type { OnApiUpdate } from '../types';

import { DEFAULT_RETRIES } from '../../config';
import Deferred from '../../util/Deferred';
import { resetFetchStateForTests } from '../../util/fetch';
import { setIsAppFocused } from '../../util/focusAwareDelay';
import {
  checkIsTrustedCollection,
  checkIsTrustedSite,
  getKnownAddresses,
  getNftSuperCollectionsByCollectionAddress,
  getScamMarkers,
  tryUpdateKnownAddresses,
} from '../common/addresses';
import { callBackendGet } from '../common/backend';
import { tokensPreload } from '../common/tokens';
import { destroyPolling, initPolling } from './polling';

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
jest.mock('../chains', () => ({ __esModule: true, default: {} }));
jest.mock('../environment', () => ({ getEnvironment: () => ({ apiHeaders: {} }) }));
jest.mock('../common/other', () => ({ getClientId: () => 'catalog-polling-test' }));
jest.mock('../common/accounts', () => ({ fetchStoredAccounts: () => Promise.resolve({}) }));
jest.mock('../common/heldTokens', () => ({
  forgetAllHeldTokens: jest.fn(),
  forgetHeldTokens: jest.fn(),
  forgetNetworkHeldTokens: jest.fn(),
  forgetOtherNetworksHeldTokens: jest.fn(),
  recordHeldTokens: jest.fn(),
}));
jest.mock('../common/tokens', () => ({
  fetchNonBackendTokenDetails: jest.fn(),
  loadTokensCache: jest.fn(),
  pauseTokenUpdates: jest.fn(),
  resumeTokenUpdates: jest.fn(),
  sendUpdateTokens: jest.fn(),
  tokensPreload: { promise: Promise.resolve() },
  updateTokens: jest.fn(),
  updateTokensFromBackend: (...args: unknown[]) => mockUpdateTokensFromBackend(...args),
}));
jest.mock('../storages', () => ({ storage: { getItem: () => Promise.resolve(undefined) } }));
jest.mock('./optional', () => ({
  requireAgentV2Lifecycle: () => ({
    reconcileAgentV2ProtocolVersion: () => Promise.resolve(undefined),
    resolveAgentV2ProtocolVersionForRouting: (version?: string) => version,
  }),
  requireStakingMethods: () => ({
    tryUpdateStakingCommonData: () => mockStakingCommon(),
  }),
  requireSwapMethods: () => ({
    swapGetAssetsText: () => jest.requireActual('../common/backend').callBackendGet(
      '/swap/assets', undefined, undefined, undefined, { shouldReturnText: true },
    ),
  }),
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

type Reply = { text: string; status?: number; error?: Error; pending?: Promise<void> };
let replies: Record<string, Reply>;

beforeEach(() => {
  jest.useFakeTimers();
  setIsAppFocused(true);
  resetFetchStateForTests();
  mockOnUpdate.mockReset();
  mockFetch.mockReset();
  mockUpdateTokensFromBackend.mockReset().mockImplementation(() => callBackendGet('/assets'));
  mockStakingCommon.mockReset().mockImplementation(() => callBackendGet('/staking/common'));
  replies = {
    [SWAP_PATH]: { text: SWAP_TEXT },
    [KNOWN_PATH]: { text: KNOWN_TEXT },
    '/assets': { text: '{}' },
    '/staking/common': { text: '{}' },
    '/currency-rates': { text: '{"rates":{}}' },
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
      json: () => Promise.resolve(reply.text).then((text) => JSON.parse(text)),
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

it('keeps catalog periods and the existing periods of the other endpoints', async () => {
  await startPolling();
  expectCounts([1, 1, 1, 1, 1, 1]);

  await jest.advanceTimersByTimeAsync(30_000);
  expectCounts([1, 1, 1, 1, 1, 2]);
  await jest.advanceTimersByTimeAsync(30_000);
  expectCounts([1, 1, 2, 2, 2, 3]);
  await jest.advanceTimersByTimeAsync(4 * MINUTE - 1);
  expectCounts([1, 1, 5, 5, 5, 10]);
  await jest.advanceTimersByTimeAsync(1);
  expectCounts([1, 2, 6, 6, 6, 11]);
  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expectCounts([1, 2, 10, 10, 10, 20]);
  await jest.advanceTimersByTimeAsync(1);
  expectCounts([2, 3, 11, 11, 11, 21]);

  await destroyPolling();
  await jest.advanceTimersByTimeAsync(10 * MINUTE);
  expectCounts([2, 3, 11, 11, 11, 21]);
});

it('keeps catalog polling infrequent while the app is unfocused', async () => {
  setIsAppFocused(false);
  await startPolling();

  await jest.advanceTimersByTimeAsync(5 * MINUTE - 1);
  expect(requestCount(SWAP_PATH)).toBe(1);
  expect(requestCount(KNOWN_PATH)).toBe(1);
  await jest.advanceTimersByTimeAsync(2);
  expect(requestCount(SWAP_PATH)).toBe(1);
  expect(requestCount(KNOWN_PATH)).toBe(2);
  await jest.advanceTimersByTimeAsync(5 * MINUTE + 1);
  expect(requestCount(SWAP_PATH)).toBe(2);
  expect(requestCount(KNOWN_PATH)).toBe(3);
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
  expect(requestCount('/assets')).toBe(2 + 2 * period / MINUTE);

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
    SWAP_PATH, KNOWN_PATH, '/assets', '/staking/common', '/utils/get-config', '/currency-rates',
  ].map(requestCount)).toEqual(counts);
}

function swapUpdates() {
  return mockOnUpdate.mock.calls.map(([update]) => update).filter((update) => update.type === 'updateSwapTokens');
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
