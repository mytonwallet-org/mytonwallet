import type { AgentThreadSummaryV2 } from './protocol/types';
import type { AgentV2ThreadHydration } from './types';

const mockStore = new Map<string, unknown>();
const mockLogDebugError = jest.fn();
const mockClear = jest.fn((store: import('idb-keyval').UseStore) => (
  jest.requireActual<typeof import('idb-keyval')>('idb-keyval').clear(store)
));
const mockCreateStore = jest.fn<import('idb-keyval').UseStore, [string, string]>(() => mockUseStore);
let mockTransactionQueue: Promise<unknown> = Promise.resolve();
let mockBeforeWriteTransaction: NoneToVoidFunction | undefined;
let mockHasStorageFailed = false;

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  INDEXED_DB_NAME: 'wallet',
}));
jest.mock('../../util/logs', () => ({
  logDebugError: (...args: unknown[]) => mockLogDebugError(...args),
}));
jest.mock('idb-keyval', () => ({
  ...jest.requireActual('idb-keyval'),
  createStore: (...args: [string, string]) => mockCreateStore(...args),
  clear: (store: import('idb-keyval').UseStore) => mockClear(store),
}));

const DEVICE_ID = 'device';
const TIMESTAMP = '2026-11-05T00:00:00.000Z';
const THREAD_BYTE_LIMIT = 256 * 1024;

beforeEach(() => {
  jest.resetModules();
  mockStore.clear();
  mockLogDebugError.mockClear();
  mockClear.mockClear();
  mockCreateStore.mockClear();
  mockHasStorageFailed = false;
  mockTransactionQueue = Promise.resolve();
  mockBeforeWriteTransaction = undefined;
});

test('independent cache contexts keep fifteen parallel writes within the shared LRU limit', async () => {
  let first!: typeof import('./threadCache');
  let second!: typeof import('./threadCache');
  jest.isolateModules(() => {
    first = jest.requireActual('./threadCache');
  });
  jest.isolateModules(() => {
    second = jest.requireActual('./threadCache');
  });
  await Promise.all(Array.from({ length: 15 }, (_, index) => (
    storeMessages(index % 2 ? first : second, `thread-${index}`)
  )));

  const messageIds = [...mockStore.keys()].filter((key) => key.startsWith('messages:'));
  const order = (mockStore.get('index') as { value: string[] }).value;
  expect(messageIds).toHaveLength(10);
  expect(messageIds.sort()).toEqual(order.map((id) => `messages:${id}`).sort());
});

test('a generation superseded as the eleventh write starts leaves all records and the index intact', async () => {
  const cache = await loadCache();
  for (let index = 0; index < 10; index++) {
    await storeMessages(cache, `thread-${index}`);
  }
  const snapshot = cloneValue([...mockStore]);
  let hasEnteredTransaction = false;
  const generation = cache.beginThreadMessagesCacheRequest('thread-10');
  mockBeforeWriteTransaction = () => {
    hasEnteredTransaction = true;
    cache.beginThreadMessagesCacheRequest('thread-10');
  };
  await cache.cacheMessages(DEVICE_ID, 'thread-10', {
    thread: createThread('thread-10'), messages: [createMessage('thread-10', 'message')],
  }, generation);

  expect(hasEnteredTransaction).toBe(true);
  expect([...mockStore]).toEqual(snapshot);
});

test('writing the thread list preserves an LRU index committed by another context', async () => {
  const cache = await loadCache();
  await storeMessages(cache, 'thread');
  const index = { ...cloneValue(mockStore.get('index') as object), value: ['newer-thread', 'thread'] };
  mockBeforeWriteTransaction = () => mockStore.set('index', index);
  await cache.cacheThreads(DEVICE_ID, [{ thread: createThread('listed') }], cache.beginThreadListCacheRequest());

  expect(mockStore.get('index')).toEqual(index);
});

test('evicts the least recently written thread at eleven and does not count the list', async () => {
  const cache = await loadCache();
  const items = [{ thread: createThread('listed'), preview: 'Preserved preview' }];
  await cache.cacheThreads(DEVICE_ID, items, cache.beginThreadListCacheRequest());
  for (let index = 0; index < 11; index++) {
    await storeMessages(cache, `thread-${index}`);
  }

  expect(await cache.getCachedMessages(DEVICE_ID, 'thread-0')).toBeUndefined();
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread-1')).toBeDefined();
  expect([...mockStore.keys()].filter((key) => key.startsWith('messages:'))).toHaveLength(10);
  expect(await cache.getCachedThreads(DEVICE_ID)).toEqual(items);
  expect(mockCreateStore).toHaveBeenCalledWith('wallet-agent-v2', 'threads');
});

test('reading and updating messages promote their threads before the next eviction', async () => {
  const cache = await loadCache();
  for (let index = 0; index < 10; index++) {
    await storeMessages(cache, `thread-${index}`);
  }
  await cache.getCachedMessages(DEVICE_ID, 'thread-0');
  await cache.updateCachedThread(DEVICE_ID, { ...createThread('thread-1'), title: 'Updated' });
  await storeMessages(cache, 'thread-10');

  expect(await cache.getCachedMessages(DEVICE_ID, 'thread-0')).toBeDefined();
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread-1'))?.thread.title).toBe('Updated');
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread-2')).toBeUndefined();
});

test('keeps the last fifty messages and records whether older messages exist', async () => {
  const cache = await loadCache();
  const messages = Array.from({ length: 55 }, (_, index) => createMessage('thread', String(index)));
  await storeMessages(cache, 'thread', messages);

  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toEqual({
    thread: createThread('thread'), messages: messages.slice(-50), hasOlder: true,
  });
  const page = { thread: createThread('thread'), messages: messages.slice(-1), nextCursor: 'older' };
  await cache.cacheMessages(DEVICE_ID, 'thread', page, cache.beginThreadMessagesCacheRequest('thread'));
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread'))?.hasOlder).toBe(true);
});

test('drops old messages until the whole record fits in 256 KiB of UTF-8 JSON', async () => {
  const cache = await loadCache();
  const messages = ['old', 'middle', 'new'].map((id) => createMessage('thread', id, 'я'.repeat(60000)));
  await storeMessages(cache, 'thread', messages);
  const record = mockStore.get('messages:thread');

  expect(new TextEncoder().encode(JSON.stringify(record)).byteLength).toBeLessThanOrEqual(THREAD_BYTE_LIMIT);
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread'))?.messages.map(({ id }) => id))
    .toEqual(['middle', 'new']);
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread'))?.hasOlder).toBe(true);
});

test('removes the record when even its newest message is too large', async () => {
  const cache = await loadCache();
  await storeMessages(cache, 'thread');
  await storeMessages(cache, 'thread', [createMessage('thread', 'large', 'x'.repeat(THREAD_BYTE_LIMIT))]);

  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();
  expect(mockStore.has('messages:thread')).toBe(false);
});

test.each(['deviceId', 'version'] as const)('clears every record on a foreign %s', async (field) => {
  const cache = await loadCache();
  await cache.cacheThreads(DEVICE_ID, [{ thread: createThread('thread') }], cache.beginThreadListCacheRequest());
  await storeMessages(cache, 'thread');
  const record = mockStore.get('index') as { deviceId: string; version: number };
  mockStore.set('index', { ...record, [field]: field === 'deviceId' ? 'foreign' : 2 });

  expect(await cache.getCachedThreads(DEVICE_ID)).toBeUndefined();
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();
  expect(mockStore.size).toBe(0);
  expect(mockClear).toHaveBeenCalledTimes(1);

  await storeMessages(cache, 'thread');
  const nextIndex = mockStore.get('index') as { deviceId: string; version: number };
  mockStore.set('index', { ...nextIndex, [field]: field === 'deviceId' ? 'foreign' : 2 });
  await storeMessages(cache, 'new-thread');
  expect(mockStore.size).toBe(0);
  expect(mockClear).toHaveBeenCalledTimes(2);
});

test('checks the ownership of list and message records independently of the index', async () => {
  const cache = await loadCache();
  await cache.cacheThreads(DEVICE_ID, [], cache.beginThreadListCacheRequest());
  const list = mockStore.get('threads') as { deviceId: string };
  mockStore.set('threads', { ...list, deviceId: 'foreign' });
  expect(await cache.getCachedThreads(DEVICE_ID)).toBeUndefined();
  expect(mockStore.size).toBe(0);

  await storeMessages(cache, 'thread');
  const messages = mockStore.get('messages:thread') as { version: number };
  mockStore.set('messages:thread', { ...messages, version: 2 });
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();
  expect(mockStore.size).toBe(0);

  await cache.cacheThreads(DEVICE_ID, [{ thread: createThread('thread') }], cache.beginThreadListCacheRequest());
  await storeMessages(cache, 'thread');
  const messagesBeforeUpdate = mockStore.get('messages:thread') as { version: number };
  mockStore.set('messages:thread', { ...messagesBeforeUpdate, version: 2 });
  await cache.updateCachedThread(DEVICE_ID, { ...createThread('thread'), title: 'Renamed' });
  expect(mockStore.size).toBe(0);

  await cache.cacheThreads(DEVICE_ID, [{ thread: createThread('thread') }], cache.beginThreadListCacheRequest());
  await storeMessages(cache, 'thread');
  const listBeforeDeletion = mockStore.get('threads') as { deviceId: string };
  mockStore.set('threads', { ...listBeforeDeletion, deviceId: 'foreign' });
  await cache.deleteCachedThread(DEVICE_ID, 'thread');
  expect(mockStore.size).toBe(0);
});

test('an older request cannot replace the latest list or message response', async () => {
  const cache = await loadCache();
  const firstListGeneration = cache.beginThreadListCacheRequest();
  const secondListGeneration = cache.beginThreadListCacheRequest();
  const firstMessagesGeneration = cache.beginThreadMessagesCacheRequest('thread');
  const secondMessagesGeneration = cache.beginThreadMessagesCacheRequest('thread');
  const freshThread = { ...createThread('thread'), title: 'Fresh' };
  await cache.cacheThreads(DEVICE_ID, [{ thread: freshThread }], secondListGeneration);
  await cache.cacheMessages(DEVICE_ID, 'thread', { thread: freshThread, messages: [] }, secondMessagesGeneration);
  await cache.cacheThreads(DEVICE_ID, [{ thread: createThread('thread') }], firstListGeneration);
  await cache.cacheMessages(
    DEVICE_ID, 'thread', { thread: createThread('thread'), messages: [] }, firstMessagesGeneration,
  );

  await cache.deleteCachedThread(DEVICE_ID, 'thread', firstMessagesGeneration);
  expect((await cache.getCachedThreads(DEVICE_ID))?.[0].thread.title).toBe('Fresh');
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread'))?.thread.title).toBe('Fresh');
});

test('updates summaries in both records and removes deleted or cleared messages', async () => {
  const cache = await loadCache();
  const thread = createThread('thread');
  await cache.cacheThreads(DEVICE_ID, [{ thread, preview: 'Preview' }], cache.beginThreadListCacheRequest());
  await storeMessages(cache, 'thread');
  const changed = { ...thread, title: 'Renamed', isPinned: true as const };
  await cache.updateCachedThread(DEVICE_ID, changed);

  expect((await cache.getCachedThreads(DEVICE_ID))?.[0]).toEqual({ thread: changed, preview: 'Preview' });
  expect((await cache.getCachedMessages(DEVICE_ID, 'thread'))?.thread).toEqual(changed);
  await cache.deleteCachedMessages(DEVICE_ID, 'thread');
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();
  expect(await cache.getCachedThreads(DEVICE_ID)).toHaveLength(1);
  await cache.updateCachedThread(DEVICE_ID, { ...changed, messageCount: 0 });
  expect(await cache.getCachedThreads(DEVICE_ID)).toEqual([]);

  await storeMessages(cache, 'thread');
  await cache.deleteCachedThread(DEVICE_ID, 'thread');
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();
  expect(await cache.getCachedThreads(DEVICE_ID)).toEqual([]);
});

test.each(['news', 'digest'] as const)('removes an untouched %s discussion on update', async (kind) => {
  const cache = await loadCache();
  const reference = kind === 'news'
    ? { news: { eventId: 307, headline: 'Headline', publishedAt: TIMESTAMP } }
    : { digest: {
      id: `ru:${TIMESTAMP}`, windowEnd: TIMESTAMP, total: 1, top: [{ eventId: 307, headline: 'Headline' }],
    } };
  const thread = { ...createThread('thread'), ...reference, messageCount: 3 };
  await cache.cacheThreads(DEVICE_ID, [{ thread, preview: 'Discussion' }], cache.beginThreadListCacheRequest());

  await cache.updateCachedThread(DEVICE_ID, { ...thread, messageCount: 1 });

  expect(await cache.getCachedThreads(DEVICE_ID)).toEqual([]);
});

test('invalidations prevent pending responses from restoring obsolete records', async () => {
  const cache = await loadCache();
  const thread = createThread('thread');
  const listGeneration = cache.beginThreadListCacheRequest();
  const messageGeneration = cache.beginThreadMessagesCacheRequest('thread');
  await cache.deleteCachedThread(DEVICE_ID, 'thread');
  await cache.cacheThreads(DEVICE_ID, [{ thread }], listGeneration);
  await cache.cacheMessages(DEVICE_ID, 'thread', { thread, messages: [] }, messageGeneration);
  expect(await cache.getCachedThreads(DEVICE_ID)).toBeUndefined();
  expect(await cache.getCachedMessages(DEVICE_ID, 'thread')).toBeUndefined();

  const pendingGeneration = cache.beginThreadMessagesCacheRequest('thread');
  await cache.clearThreadCache();
  await cache.cacheMessages(DEVICE_ID, 'thread', { thread, messages: [] }, pendingGeneration);
  expect(mockStore.size).toBe(0);
});

test('unavailable IndexedDB logs errors and getters return undefined', async () => {
  const cache = await loadCache();
  mockHasStorageFailed = true;
  await expect(storeMessages(cache, 'thread')).resolves.toBeUndefined();
  await expect(cache.getCachedThreads(DEVICE_ID)).resolves.toBeUndefined();
  await expect(cache.getCachedMessages(DEVICE_ID, 'thread')).resolves.toBeUndefined();
  expect(mockLogDebugError).toHaveBeenCalledTimes(3);
});

function loadCache() {
  return import('./threadCache');
}

function createThread(id: string): AgentThreadSummaryV2 {
  return { id, revision: 1, createdAt: TIMESTAMP, updatedAt: TIMESTAMP, lastActivityAt: TIMESTAMP, messageCount: 1 };
}

function createMessage(threadId: string, id: string, text = 'Message'): AgentV2ThreadHydration['messages'][number] {
  return { id, threadId, role: 'assistant', status: 'complete', createdAt: TIMESTAMP, text };
}

function storeMessages(
  cache: typeof import('./threadCache'), threadId: string, messages = [createMessage(threadId, 'message')],
) {
  return cache.cacheMessages(
    DEVICE_ID, threadId, { thread: createThread(threadId), messages },
    cache.beginThreadMessagesCacheRequest(`${threadId}`),
  );
}

function mockUseStore<T>(
  mode: IDBTransactionMode, callback: (store: IDBObjectStore) => T | PromiseLike<T>,
): Promise<T> {
  const pending = mockTransactionQueue.then(async () => {
    if (mockHasStorageFailed) throw new Error('IndexedDB unavailable');
    if (mode === 'readwrite') {
      const beforeWrite = mockBeforeWriteTransaction;
      mockBeforeWriteTransaction = undefined;
      beforeWrite?.();
    }
    const values = new Map([...mockStore].map(([key, value]) => [key, cloneValue(value)]));
    let hasAborted = false;
    const transaction = {
      oncomplete: undefined as NoneToVoidFunction | undefined,
      onabort: undefined as NoneToVoidFunction | undefined,
      error: new Error('Transaction aborted'),
      abort() { hasAborted = true; },
    };
    const store = {
      transaction,
      get(key: string) {
        const request = { result: undefined as unknown, onsuccess: undefined as NoneToVoidFunction | undefined };
        queueMicrotask(() => {
          request.result = cloneValue(values.get(key));
          request.onsuccess?.();
        });
        return request;
      },
      put(value: unknown, key: string) { values.set(key, cloneValue(value)); },
      delete(key: string) { values.delete(key); },
      clear() { values.clear(); },
    };
    const result = callback(store as unknown as IDBObjectStore);
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        if (hasAborted) {
          transaction.onabort?.();
        } else {
          mockStore.clear();
          values.forEach((value, key) => mockStore.set(key, value));
          transaction.oncomplete?.();
        }
        resolve();
      }, 0);
    });
    return result;
  });
  mockTransactionQueue = pending.catch(() => undefined);
  return pending;
}

function cloneValue<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}
