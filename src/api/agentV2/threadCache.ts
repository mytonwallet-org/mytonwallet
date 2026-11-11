import * as idb from 'idb-keyval';

import type { AgentThreadListItemV2, AgentThreadSummaryV2 } from './protocol/types';
import type { AgentV2ThreadHydration } from './types';

import { INDEXED_DB_NAME } from '../../config';
import { logDebugError } from '../../util/logs';
import { getIsAgentV2ThreadStarted } from './threadStarted';

interface CacheRecord<T> {
  version: number;
  deviceId: string;
  value: T;
}

interface CachedMessages {
  thread: AgentThreadSummaryV2;
  messages: AgentV2ThreadHydration['messages'];
  hasOlder: boolean;
}

const SCHEMA_VERSION = 1;
const THREADS_KEY = 'threads';
const INDEX_KEY = 'index';
export const THREAD_CACHE_MESSAGE_LIMIT = 50;
const THREAD_LIMIT = 10;
const THREAD_BYTE_LIMIT = 256 * 1024;
const ENCODER = new TextEncoder();

let cacheStore: ReturnType<typeof idb.createStore> | undefined;
let cacheQueue: Promise<unknown> = Promise.resolve();
let requestGeneration = 0;
const requestGenerations = new Map<string, number>();

function beginThreadCacheRequest(key: string) {
  const generation = ++requestGeneration;
  requestGenerations.set(key, generation);
  return generation;
}

export function beginThreadListCacheRequest() {
  return beginThreadCacheRequest(THREADS_KEY);
}

export function beginThreadMessagesCacheRequest(threadId: string) {
  return beginThreadCacheRequest(getMessagesKey(threadId));
}

export function getCachedThreads(deviceId: string) {
  return runCacheOperation(async () => {
    await readIndex(deviceId);
    return (await readRecord<AgentThreadListItemV2[]>(deviceId, THREADS_KEY))?.value;
  });
}

export function getCachedMessages(deviceId: string, threadId: string) {
  return runCacheOperation(() => runMessageTransaction(deviceId, threadId, (store, order, _threads, messages) => {
    if (!messages) return undefined;

    store.put(createRecord(deviceId, promoteThread(order, threadId)), INDEX_KEY);
    return messages.value;
  }));
}

export function cacheThreads(deviceId: string, threads: AgentThreadListItemV2[], generation: number) {
  return runCacheOperation(async () => {
    await readIndex(deviceId);
    if (requestGenerations.get(THREADS_KEY) !== generation) return;

    await idb.set(THREADS_KEY, createRecord(deviceId, threads), getStore());
  });
}

export function cacheMessages(
  deviceId: string,
  threadId: string,
  page: Pick<AgentV2ThreadHydration, 'thread' | 'messages' | 'nextCursor'>,
  generation: number,
) {
  return runCacheOperation(() => {
    const key = getMessagesKey(threadId);
    if (requestGenerations.get(key) !== generation) return Promise.resolve(undefined);

    const record = trimMessages(createRecord(deviceId, {
      thread: page.thread,
      messages: page.messages.slice(-THREAD_CACHE_MESSAGE_LIMIT),
      hasOlder: Boolean(page.nextCursor) || page.messages.length > THREAD_CACHE_MESSAGE_LIMIT,
    }));
    return runMessageTransaction(deviceId, threadId, (store, order) => {
      if (requestGenerations.get(key) !== generation) return;
      if (!record) {
        removeMessages(store, deviceId, threadId, order);
        return;
      }

      const nextOrder = promoteThread(order, threadId);
      const evicted = nextOrder.splice(THREAD_LIMIT);
      evicted.forEach((id) => store.delete(getMessagesKey(id)));
      store.put(record, key);
      store.put(createRecord(deviceId, nextOrder), INDEX_KEY);
    });
  });
}

export function updateCachedThread(deviceId: string, thread: AgentThreadSummaryV2) {
  beginThreadCacheRequest(THREADS_KEY);
  beginThreadCacheRequest(getMessagesKey(thread.id));
  return runCacheOperation(() => runMessageTransaction(deviceId, thread.id, (store, order, threads, messages) => {
    if (threads) {
      const items = thread.messageCount && getIsAgentV2ThreadStarted(thread)
        ? threads.value.map((item) => (item.thread.id === thread.id ? { ...item, thread } : item))
        : threads.value.filter((item) => item.thread.id !== thread.id);
      store.put(createRecord(deviceId, items), THREADS_KEY);
    }
    if (messages) {
      const record = trimMessages({ ...messages, value: { ...messages.value, thread } });
      if (record) {
        store.put(record, getMessagesKey(thread.id));
        store.put(createRecord(deviceId, promoteThread(order, thread.id)), INDEX_KEY);
      } else {
        removeMessages(store, deviceId, thread.id, order);
      }
    }
  }));
}

export function deleteCachedThread(deviceId: string, threadId: string, generation?: number) {
  if (generation !== undefined && requestGenerations.get(getMessagesKey(threadId)) !== generation) {
    return Promise.resolve(undefined);
  }
  beginThreadCacheRequest(THREADS_KEY);
  beginThreadCacheRequest(getMessagesKey(threadId));
  return runCacheOperation(() => runMessageTransaction(deviceId, threadId, (store, order, threads) => {
    if (threads) {
      store.put(createRecord(deviceId, threads.value.filter(({ thread }) => thread.id !== threadId)), THREADS_KEY);
    }
    removeMessages(store, deviceId, threadId, order);
  }));
}

export function deleteCachedMessages(deviceId: string, threadId: string) {
  beginThreadCacheRequest(getMessagesKey(threadId));
  return runCacheOperation(() => runMessageTransaction(deviceId, threadId, (store, order) => {
    removeMessages(store, deviceId, threadId, order);
  }));
}

export function clearThreadCache() {
  requestGenerations.clear();
  return runCacheOperation(() => idb.clear(getStore()));
}

function runCacheOperation<T>(operation: () => Promise<T>): Promise<T | undefined> {
  const result = cacheQueue.then(operation).catch((err: unknown) => {
    logDebugError('agentV2ThreadCache', err);
    return undefined;
  });
  cacheQueue = result;
  return result;
}

async function runMessageTransaction<T>(
  deviceId: string,
  threadId: string,
  operation: (
    store: IDBObjectStore,
    order: string[],
    threads: CacheRecord<AgentThreadListItemV2[]> | undefined,
    messages: CacheRecord<CachedMessages> | undefined,
  ) => T,
) {
  let hasForeignRecord = false;
  const result = await getStore()('readwrite', (store) => {
    const completed = idb.promisifyRequest(store.transaction);
    const pending = Promise.all([
      idb.promisifyRequest<CacheRecord<string[]> | undefined>(store.get(INDEX_KEY)),
      idb.promisifyRequest<CacheRecord<AgentThreadListItemV2[]> | undefined>(store.get(THREADS_KEY)),
      idb.promisifyRequest<CacheRecord<CachedMessages> | undefined>(store.get(getMessagesKey(threadId))),
    ]).then(([index, threads, messages]) => {
      hasForeignRecord = [index, threads, messages].some((record) => record && (
        record.version !== SCHEMA_VERSION || record.deviceId !== deviceId
      ));
      if (hasForeignRecord) return undefined;

      try {
        return operation(store, index?.value ?? [], threads, messages);
      } catch (err) {
        store.transaction.abort();
        throw err;
      }
    });
    return Promise.all([completed, pending]).then(([, value]) => value);
  });
  if (hasForeignRecord) await idb.clear(getStore());
  return result;
}

async function readIndex(deviceId: string) {
  return (await readRecord<string[]>(deviceId, INDEX_KEY))?.value ?? [];
}

async function readRecord<T>(deviceId: string, key: string) {
  const record = await idb.get<CacheRecord<T>>(key, getStore());
  if (!record) return undefined;
  if (record.version !== SCHEMA_VERSION || record.deviceId !== deviceId) {
    await idb.clear(getStore());
    return undefined;
  }
  return record;
}

function createRecord<T>(deviceId: string, value: T): CacheRecord<T> {
  return { version: SCHEMA_VERSION, deviceId, value };
}

function getMessagesKey(threadId: string) {
  return `messages:${threadId}`;
}

function promoteThread(order: string[], threadId: string) {
  return [threadId, ...order.filter((id) => id !== threadId)];
}

function trimMessages(record: CacheRecord<CachedMessages>) {
  const hasMessages = Boolean(record.value.messages.length);
  while (ENCODER.encode(JSON.stringify(record)).byteLength > THREAD_BYTE_LIMIT) {
    if (!record.value.messages.length) return undefined;
    record.value.messages.shift();
    record.value.hasOlder = true;
  }
  return hasMessages && !record.value.messages.length ? undefined : record;
}

function removeMessages(store: IDBObjectStore, deviceId: string, threadId: string, order: string[]) {
  store.delete(getMessagesKey(threadId));
  store.put(createRecord(deviceId, order.filter((id) => id !== threadId)), INDEX_KEY);
}

function getStore() {
  cacheStore ??= idb.createStore(`${INDEXED_DB_NAME}-agent-v2`, 'threads');
  return cacheStore;
}
