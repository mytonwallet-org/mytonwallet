import * as idb from 'idb-keyval';

import type { NftItemWire, NftSyncSnapshot } from './nftSync';

import { CircuitOpenError } from '../../util/circuitBreaker';
import Deferred from '../../util/Deferred';
import { logDebugError } from '../../util/logs';
import { MINUTE, SEC } from '../constants';
import { ApiServerError } from '../errors';
import { getCurrentStorage } from '../storages';
import { callBackendGet } from './backend';
import { createNftSync, removeNftSyncSnapshots } from './nftSync';

jest.mock('idb-keyval', () => ({
  createStore: jest.fn(() => jest.fn()),
  get: jest.fn(), set: jest.fn(), keys: jest.fn(), del: jest.fn(), delMany: jest.fn(),
}));
jest.mock('../storages', () => ({ getCurrentStorage: jest.fn() }));
jest.mock('./backend', () => ({ callBackendGet: jest.fn() }));
jest.mock('../environment', () => ({ getEnvironment: () => ({ apiHeaders: {} }) }));
jest.mock('./other', () => ({ getClientId: () => 'test-client-id' }));
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));

const ACCOUNT_ID = '0-mainnet';
const OWNER = 'owner';
const SNAPSHOT_KEY = `${ACCOUNT_ID}:ton`;
const ITEM: NftItemWire = { address: 'raw-nft', init: true, index: '1', collection_address: 'raw-collection' };
const METADATA = { is_indexed: true, token_info: [{ type: 'nft_items', name: 'NFT' }] };
const SNAPSHOT: NftSyncSnapshot = {
  schemaVersion: 1,
  syncToken: 'initial-token',
  items: { [ITEM.address]: ITEM },
  metadata: { [ITEM.address]: METADATA },
};

let db: Record<string, any>;
let accounts: Record<string, unknown>;
let persistentStorage: {
  getItem: jest.Mock;
  setItem: jest.Mock;
  removeItem: jest.Mock;
  clear: jest.Mock;
};

function start(owner = OWNER) {
  return createNftSync(ACCOUNT_ID, 'ton', 'mainnet', owner);
}

function respond(overrides: Record<string, unknown> = {}, status = 200) {
  const body = {
    syncToken: 'next-token', reset: false, hasMore: false, items: [], removed: [], metadata: {}, ...overrides,
  };
  jest.mocked(callBackendGet).mockResolvedValueOnce({ status, json: () => Promise.resolve(body) } as Response);
}

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(callBackendGet).mockReset();
  accounts = { [ACCOUNT_ID]: { byChain: { ton: { address: OWNER } } } };
  db = { [SNAPSHOT_KEY]: SNAPSHOT };
  jest.mocked(idb.get).mockReset().mockImplementation((key) => Promise.resolve(db[key as string]));
  jest.mocked(idb.set).mockReset().mockImplementation((key, value) => {
    db[key as string] = value;
    return Promise.resolve();
  });
  jest.mocked(idb.keys).mockReset().mockImplementation(() => Promise.resolve(Object.keys(db) as never));
  jest.mocked(idb.del).mockReset().mockImplementation((key) => {
    delete db[key as string];
    return Promise.resolve();
  });
  jest.mocked(idb.delMany).mockReset().mockImplementation((keys) => {
    keys.forEach((key) => delete db[key as string]);
    return Promise.resolve();
  });
  persistentStorage = {
    getItem: jest.fn((key: string) => Promise.resolve(key === 'accounts' ? accounts : undefined)),
    setItem: jest.fn(),
    removeItem: jest.fn(),
    clear: jest.fn(),
  };
  jest.mocked(getCurrentStorage).mockReturnValue(persistentStorage);
});

it('restores wire data, requests since, persists the token and retains only referenced metadata', async () => {
  const client = start();
  expect(await client.load()).toEqual(SNAPSHOT);
  respond({
    items: [{ ...ITEM, on_sale: true }],
    metadata: { 'raw-nft': METADATA, 'raw-collection': METADATA, unused: METADATA },
  });

  const result = await client.sync();

  expect(callBackendGet).toHaveBeenCalledWith('/nfts/ton/mainnet/owner', { since: 'initial-token' },
    undefined, expect.any(AbortSignal), { shouldReturnResponse: true, shouldRetry: false, timeout: 25000 });
  expect(result?.previous).toEqual(SNAPSHOT);
  expect(result?.snapshot).toEqual({
    ...SNAPSHOT, syncToken: 'next-token', items: { 'raw-nft': { ...ITEM, on_sale: true } },
    metadata: { 'raw-nft': METADATA, 'raw-collection': METADATA },
  });
  expect(db[SNAPSHOT_KEY]).toEqual(result?.snapshot);
  expect(result?.changedAddresses).toEqual([ITEM.address]);
  expect(SNAPSHOT.items[ITEM.address].on_sale).toBeUndefined();
});

it('does nothing for unchanged empty pages after loading the saved snapshot', async () => {
  const validate = jest.fn();
  const client = createNftSync(ACCOUNT_ID, 'ton', 'mainnet', OWNER, validate);
  expect(await client.load()).toBe(SNAPSHOT);
  jest.clearAllMocks();
  respond({ syncToken: 'page-token', hasMore: true });
  respond({ syncToken: SNAPSHOT.syncToken });

  const result = await client.sync();

  expect(result?.snapshot).toBe(SNAPSHOT);
  expect(result?.changedAddresses).toEqual([]);
  expect(persistentStorage.getItem).not.toHaveBeenCalled();
  expect(idb.get).not.toHaveBeenCalled();
  expect(idb.set).not.toHaveBeenCalled();
  expect(idb.del).not.toHaveBeenCalled();
  expect(validate).not.toHaveBeenCalled();
});

it('writes only the changed account and chain snapshot in its dedicated store', async () => {
  const otherKeys = ['1-mainnet:ton', `${ACCOUNT_ID}:ethereum`];
  for (const key of otherKeys) db[key] = SNAPSHOT;
  respond({ items: [{ ...ITEM, on_sale: true }] });

  const result = await start().sync();

  expect(idb.set).toHaveBeenCalledTimes(1);
  expect(idb.set).toHaveBeenCalledWith(SNAPSHOT_KEY, result?.snapshot, expect.any(Function));
  expect(persistentStorage.setItem).not.toHaveBeenCalled();
  expect(persistentStorage.getItem.mock.calls.every(([key]) => key === 'accounts')).toBe(true);
  for (const key of otherKeys) {
    expect(db[key]).toBe(SNAPSHOT);
    expect(idb.get).not.toHaveBeenCalledWith(key, expect.any(Function));
  }
});

it('commits a paginated snapshot only after its last page and then requests deltas', async () => {
  delete db[SNAPSHOT_KEY];
  const client = start();
  respond({ reset: true, hasMore: true, syncToken: 'page-2', items: [ITEM] });
  const lastPage = new Deferred<Response>();
  jest.mocked(callBackendGet).mockReturnValueOnce(lastPage.promise);
  const request = client.sync();
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(callBackendGet).toHaveBeenCalledTimes(2);
  expect(idb.set).not.toHaveBeenCalled();
  lastPage.resolve({ status: 200, json: () => Promise.resolve({
    reset: false, hasMore: false, syncToken: 'snapshot-version',
    items: [{ ...ITEM, address: 'raw-second' }], removed: [], metadata: {},
  }) } as Response);
  const result = await request;

  expect(result?.reset).toBe(true);
  expect(Object.keys(result!.snapshot.items)).toEqual(['raw-nft', 'raw-second']);
  expect(result?.changedAddresses).toEqual(['raw-nft', 'raw-second']);
  expect(idb.set).toHaveBeenCalledWith(SNAPSHOT_KEY, result?.snapshot, expect.any(Function));
  respond({ syncToken: 'latest', items: [{ ...ITEM, on_sale: true }] });
  const delta = await client.sync();
  expect(jest.mocked(callBackendGet).mock.calls[2][1]).toEqual({ since: 'snapshot-version' });
  expect(delta?.reset).toBe(false);
  expect(delta?.snapshot.items[ITEM.address].on_sale).toBe(true);
  expect(idb.set).toHaveBeenCalledTimes(2);
});

it.each(['stale-token', 'other-network-token'])('replaces the snapshot after reset for %s', async (token) => {
  db[SNAPSHOT_KEY] = { ...SNAPSHOT, syncToken: token };
  respond({ reset: true, items: [{ ...ITEM, address: 'raw-new' }] });
  const result = await start().sync();
  expect(jest.mocked(callBackendGet).mock.calls[0][1]).toEqual({ since: token });
  expect(result?.reset).toBe(true);
  expect(Object.keys(result!.snapshot.items)).toEqual(['raw-new']);
});

it('discards unfinished pages when snapshot pagination restarts with reset', async () => {
  respond({ reset: true, hasMore: true, syncToken: 'old-page', items: [ITEM] });
  respond({ reset: true, syncToken: 'rebuilt', items: [{ ...ITEM, address: 'raw-rebuilt' }] });
  const result = await start().sync();
  expect(Object.keys(result!.snapshot.items)).toEqual(['raw-rebuilt']);
  expect(result?.reset).toBe(true);
});

it('keeps snapshot and token untouched if a later page fails', async () => {
  respond({ hasMore: true, syncToken: 'partial', removed: [ITEM.address] });
  jest.mocked(callBackendGet).mockRejectedValueOnce(new Error('Offline'));
  expect(await start().sync()).toBeUndefined();
  expect(db[SNAPSHOT_KEY]).toEqual(SNAPSHOT);
  expect(idb.set).not.toHaveBeenCalled();
});

it('times out a stalled 200 response body and preserves the snapshot for fallback', async () => {
  jest.useFakeTimers();
  try {
    const body = new Deferred<unknown>();
    jest.mocked(callBackendGet).mockResolvedValueOnce({ status: 200, json: () => body.promise } as Response);
    const client = start();
    const request = client.sync();
    await jest.advanceTimersByTimeAsync(0);
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(idb.set).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(25000);

    expect(await request).toBeUndefined();
    expect(await client.sync()).toBeUndefined();
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(db[SNAPSHOT_KEY]).toEqual(SNAPSHOT);
    expect(idb.set).not.toHaveBeenCalled();
    expect(logDebugError).toHaveBeenCalledWith('nftSync request', expect.objectContaining({ name: 'TimeoutError' }));
    expect(jest.getTimerCount()).toBe(0);
    expect(client.getRetryAt()).toBe(Date.now() + 5 * MINUTE);
    await jest.advanceTimersByTimeAsync(5 * MINUTE);
    respond();
    expect(await client.sync()).toBeDefined();
    expect(client.getRetryAt()).toBeUndefined();
  } finally {
    jest.useRealTimers();
  }
});

it.each([
  ['202', () => respond({}, 202), MINUTE],
  ['202 with retryAfter 1', () => respond({ retryAfter: 1 }, 202), 5 * SEC],
  ['202 with retryAfter 3600', () => respond({ retryAfter: 3600 }, 202), 5 * MINUTE],
  ['202 with invalid retryAfter', () => respond({ retryAfter: Infinity }, 202), MINUTE],
  ['5xx', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('Unavailable', 503));
  }, 5 * MINUTE],
  ['408', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('Request Timeout', 408));
  }, 5 * MINUTE],
  ['429', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('Too Many Requests', 429));
  }, 5 * MINUTE],
  ['timeout', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new Error('Request timed out'));
  }, 5 * MINUTE],
  ['transport', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new TypeError('Failed to fetch'));
  }, 5 * MINUTE],
  ['open circuit', () => {
    jest.mocked(callBackendGet).mockRejectedValueOnce(new CircuitOpenError('nfts'));
  }, 5 * MINUTE],
] as const)('retries %s after its account pause without changing durable state', async (_outcome, setup, delay) => {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  try {
    setup();
    const client = start();
    expect(await client.sync()).toBeUndefined();
    expect(client.getRetryAt()).toBe(1000 + delay);
    clock.mockReturnValue(1000 + delay - 1);
    expect(await client.sync()).toBeUndefined();
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(db[SNAPSHOT_KEY]).toEqual(SNAPSHOT);
    expect(idb.set).not.toHaveBeenCalled();
    expect(logDebugError).toHaveBeenCalled();

    clock.mockReturnValue(1000 + delay);
    respond();
    expect(await client.sync()).toBeDefined();
    expect(callBackendGet).toHaveBeenCalledTimes(2);
    expect(client.getRetryAt()).toBeUndefined();
  } finally {
    clock.mockRestore();
  }
});

it('retries a transport failure wrapped by the real backend after five minutes', async () => {
  const backend = jest.requireActual<typeof import('./backend')>('./backend');
  const originalFetch = global.fetch;
  const fetchMock = jest.fn().mockRejectedValueOnce(new TypeError('Failed to fetch'));
  global.fetch = fetchMock;
  jest.mocked(callBackendGet).mockImplementation(backend.callBackendGet);
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  try {
    const client = start();
    expect(await client.sync()).toBeUndefined();
    expect(logDebugError).toHaveBeenCalledWith('nftSync request', expect.any(ApiServerError));
    expect(jest.mocked(logDebugError).mock.calls[0][1]).toMatchObject({ statusCode: undefined });
    expect(client.getRetryAt()).toBe(1000 + 5 * MINUTE);

    clock.mockReturnValue(1000 + 5 * MINUTE - 1);
    expect(await client.sync()).toBeUndefined();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(db[SNAPSHOT_KEY]).toBe(SNAPSHOT);
    expect(await client.load()).toBe(SNAPSHOT);
    expect(idb.set).not.toHaveBeenCalled();

    clock.mockReturnValue(1000 + 5 * MINUTE);
    fetchMock.mockResolvedValueOnce({ status: 200, json: () => Promise.resolve({
      syncToken: SNAPSHOT.syncToken, reset: false, hasMore: false, items: [], removed: [], metadata: {},
    }) });
    expect((await client.sync())?.snapshot).toBe(SNAPSHOT);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(new URL(fetchMock.mock.calls[1][0]).searchParams.get('since')).toBe(SNAPSHOT.syncToken);
    expect(client.getRetryAt()).toBeUndefined();
    expect(idb.set).not.toHaveBeenCalled();
  } finally {
    global.fetch = originalFetch;
    clock.mockRestore();
  }
});

it.each([
  ['invalid JSON', () => {
    jest.mocked(callBackendGet).mockResolvedValueOnce({
      status: 200, json: () => Promise.reject(new SyntaxError('Invalid JSON')),
    } as Response);
  }],
  ['invalid response', () => respond({ items: [{}] })],
  ['invalid metadata', () => respond({ metadata: { 'raw-nft': { token_info: 'invalid' } } })],
  ['400', () => { jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('invalid_address', 400)); }],
  ['401', () => { jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('Unauthorized', 401)); }],
  ['204', () => respond({}, 204)],
] as const)('uses fallback for %s for the session without changing durable state', async (outcome, setup) => {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  try {
    setup();
    const client = start();
    expect(await client.sync()).toBeUndefined();
    clock.mockReturnValue(1000 + 60 * MINUTE);
    expect(await client.sync()).toBeUndefined();
    expect(client.getRetryAt()).toBeUndefined();
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    expect(db[SNAPSHOT_KEY]).toEqual(SNAPSHOT);
    expect(idb.set).not.toHaveBeenCalled();
    expect(logDebugError).toHaveBeenCalled();
    if (outcome === '400') expect(logDebugError).toHaveBeenCalledWith('nftSync programming error', expect.any(Error));
    respond();
    expect(await start().sync()).toBeDefined();
    expect(callBackendGet).toHaveBeenCalledTimes(2);
  } finally {
    clock.mockRestore();
  }
});

it('keeps a 202 pause local to its account and clears it after an unchanged response', async () => {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  try {
    const otherAccountId = '1-mainnet';
    accounts[otherAccountId] = { byChain: { ton: { address: 'other-owner' } } };
    db[`${otherAccountId}:ton`] = SNAPSHOT;
    respond({ retryAfter: 30 }, 202);
    const client = start();
    expect(await client.sync()).toBeUndefined();
    expect(client.getRetryAt()).toBe(31000);

    respond({ items: [{ ...ITEM, on_sale: true }] });
    const otherClient = createNftSync(otherAccountId, 'ton', 'mainnet', 'other-owner');
    expect(await otherClient.sync()).toBeDefined();
    expect(otherClient.getRetryAt()).toBeUndefined();
    expect(db[SNAPSHOT_KEY]).toBe(SNAPSHOT);
    expect(callBackendGet).toHaveBeenCalledTimes(2);

    clock.mockReturnValue(30999);
    expect(await client.sync()).toBeUndefined();
    expect(callBackendGet).toHaveBeenCalledTimes(2);
    clock.mockReturnValue(31000);
    respond({ syncToken: SNAPSHOT.syncToken });
    expect((await client.sync())?.snapshot).toBe(SNAPSHOT);
    expect(client.getRetryAt()).toBeUndefined();
    expect(idb.set).toHaveBeenCalledTimes(1);
  } finally {
    clock.mockRestore();
  }
});

it('disables the endpoint for an hour after 404 across sessions', async () => {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  const client = start();
  jest.mocked(callBackendGet).mockRejectedValueOnce(new ApiServerError('unsupported_chain', 404));
  expect(await client.sync()).toBeUndefined();
  expect(client.getRetryAt()).toBe(1000 + 60 * MINUTE);
  expect(await client.sync()).toBeUndefined();
  accounts['1-mainnet'] = { byChain: { ton: { address: 'other-owner' } } };
  const otherClient = createNftSync('1-mainnet', 'ton', 'mainnet', 'other-owner');
  expect(otherClient.getRetryAt()).toBe(1000 + 60 * MINUTE);
  expect(await otherClient.sync()).toBeUndefined();
  expect(callBackendGet).toHaveBeenCalledTimes(1);
  clock.mockReturnValue(1000 + 60 * MINUTE);
  respond();
  expect(await client.sync()).toBeDefined();
  expect(client.getRetryAt()).toBeUndefined();
  clock.mockRestore();
});

it('keeps the new in-memory snapshot on a failed write and fetches a full snapshot next session', async () => {
  jest.mocked(idb.set).mockRejectedValueOnce(new Error('Quota exceeded'));
  respond({ items: [{ ...ITEM, on_sale: true }] });
  const client = start();
  const result = await client.sync();
  expect(result?.snapshot.items[ITEM.address].on_sale).toBe(true);
  expect(await client.load()).toEqual(result?.snapshot);
  expect(logDebugError).toHaveBeenCalledWith('nftSync persist', expect.any(Error));
  expect(db[SNAPSHOT_KEY]).toBeUndefined();
  respond({ reset: true, items: [ITEM] });
  await start().sync();
  expect(jest.mocked(callBackendGet).mock.calls[1][1]).toEqual({ since: undefined });
});

it.each([
  ['unavailable IndexedDB', new ReferenceError('indexedDB is not defined')],
  ['failed cache read', new Error('IndexedDB read failed')],
])('continues without a cache after %s', async (_reason, error) => {
  jest.mocked(idb.get).mockRejectedValueOnce(error);
  const client = start();
  expect(await client.load()).toBeUndefined();
  respond({ reset: true, items: [ITEM] });

  const result = await client.sync();

  expect(result?.snapshot.items[ITEM.address]).toEqual(ITEM);
  expect(await client.load()).toBe(result?.snapshot);
  expect(jest.mocked(callBackendGet).mock.calls[0][1]).toEqual({ since: undefined });
  expect(logDebugError).toHaveBeenCalledWith('nftSync load', error);
  expect(idb.set).not.toHaveBeenCalled();
  respond({ reset: true, items: [ITEM] });
  await start().sync();
  expect(jest.mocked(callBackendGet).mock.calls[1][1]).toEqual({ since: undefined });
});

it('validates snapshots with the chain adapter before writing them', async () => {
  const clock = jest.spyOn(Date, 'now').mockReturnValue(1000);
  try {
    const validate = jest.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error('Invalid address'));
    respond({ items: [{ ...ITEM, address: 'invalid' }] });
    const client = createNftSync(ACCOUNT_ID, 'ton', 'mainnet', OWNER, validate);
    expect(await client.sync()).toBeUndefined();
    expect(validate.mock.calls.at(-1)?.[1]).toEqual(['invalid']);
    expect(db[SNAPSHOT_KEY]).toEqual(SNAPSHOT);
    expect(idb.set).not.toHaveBeenCalled();
    clock.mockReturnValue(1000 + 60 * MINUTE);
    expect(await client.sync()).toBeUndefined();
    expect(client.getRetryAt()).toBeUndefined();
    expect(callBackendGet).toHaveBeenCalledTimes(1);
    respond();
    expect(await createNftSync(ACCOUNT_ID, 'ton', 'mainnet', OWNER, validate).sync()).toBeDefined();
    expect(callBackendGet).toHaveBeenCalledTimes(2);
  } finally {
    clock.mockRestore();
  }
});

it('removes account, network and all snapshot keys without reading unrelated snapshots', async () => {
  const keys = [SNAPSHOT_KEY, '0-mainnet:ethereum', '1-mainnet:ton', '0-testnet:ton'];
  for (const key of keys) db[key] = SNAPSHOT;

  await removeNftSyncSnapshots('0-mainnet');
  expect(Object.keys(db)).toEqual(['1-mainnet:ton', '0-testnet:ton']);
  await removeNftSyncSnapshots(undefined, 'mainnet');
  expect(Object.keys(db)).toEqual(['0-testnet:ton']);
  await removeNftSyncSnapshots();
  expect(Object.keys(db)).toEqual([]);
  expect(idb.keys).toHaveBeenCalledTimes(3);
  expect(idb.get).not.toHaveBeenCalled();
  expect(persistentStorage.setItem).not.toHaveBeenCalled();
});

it('persists parallel account snapshots without a separate index', async () => {
  db = {};
  accounts['1-mainnet'] = { byChain: { ton: { address: OWNER } } };
  const otherStorage = { ...persistentStorage };
  const first = start();
  jest.mocked(getCurrentStorage).mockReturnValue(otherStorage);
  const second = createNftSync('1-mainnet', 'ton', 'mainnet', OWNER);
  respond({ reset: true, items: [ITEM] });
  respond({ reset: true, items: [ITEM] });

  expect((await Promise.all([first.sync(), second.sync()])).every(Boolean)).toBe(true);
  expect(Object.keys(db).sort()).toEqual([SNAPSHOT_KEY, '1-mainnet:ton'].sort());
  expect(idb.set).toHaveBeenCalledTimes(2);
  expect(persistentStorage.setItem).not.toHaveBeenCalled();
  await removeNftSyncSnapshots();
  expect(Object.keys(db)).toEqual([]);
});

it('does not restore an account snapshot when its response arrives after account deletion', async () => {
  const response = new Deferred<Response>();
  jest.mocked(callBackendGet).mockReturnValueOnce(response.promise);
  const request = start().sync();
  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(callBackendGet).toHaveBeenCalledTimes(1);
  delete accounts[ACCOUNT_ID];
  await removeNftSyncSnapshots(ACCOUNT_ID);
  response.resolve({ status: 200, json: () => Promise.resolve({
    syncToken: 'next-token', reset: false, hasMore: false, items: [], removed: [], metadata: {},
  }) } as Response);
  expect(await request).toBeUndefined();
  expect(db[SNAPSHOT_KEY]).toBeUndefined();
});

it('removes a snapshot written after another runtime has completed account deletion', async () => {
  const readStarted = new Deferred();
  const releaseRead = new Deferred();
  persistentStorage.getItem.mockImplementationOnce(async () => {
    const capturedAccounts = { ...accounts };
    readStarted.resolve();
    await releaseRead.promise;
    return capturedAccounts;
  });
  const client = start();
  respond({ items: [{ ...ITEM, on_sale: true }] });
  const request = client.sync();
  await readStarted.promise;

  const otherStorage = {
    ...persistentStorage,
    getItem: jest.fn((key: string) => Promise.resolve(key === 'accounts' ? accounts : undefined)),
  };
  jest.mocked(getCurrentStorage).mockReturnValue(otherStorage);
  delete accounts[ACCOUNT_ID];
  await removeNftSyncSnapshots(ACCOUNT_ID);
  expect(db[SNAPSHOT_KEY]).toBeUndefined();

  releaseRead.resolve();
  expect(await request).toBeUndefined();
  expect(idb.set).toHaveBeenCalledTimes(1);
  expect(persistentStorage.getItem).toHaveBeenLastCalledWith('accounts', true);
  expect(idb.del).toHaveBeenCalledWith(SNAPSHOT_KEY, expect.any(Function));
  expect(db[SNAPSHOT_KEY]).toBeUndefined();
});

it('keeps wallet and Explorer snapshots in separate databases', () => {
  const previous = process.env.IS_EXPLORER;
  function getDatabaseName(isExplorer: boolean) {
    if (isExplorer) process.env.IS_EXPLORER = '1';
    else delete process.env.IS_EXPLORER;
    let name: string | undefined;
    jest.isolateModules(() => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      require('./nftSync');
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      name = jest.mocked((require('idb-keyval') as typeof idb).createStore).mock.lastCall?.[0];
    });
    return name;
  }

  try {
    expect(getDatabaseName(false)).toBe('keyval-store-nft-sync');
    expect(getDatabaseName(true)).toBe('explorer-keyval-store-nft-sync');
  } finally {
    if (previous === undefined) delete process.env.IS_EXPLORER;
    else process.env.IS_EXPLORER = previous;
  }
});
