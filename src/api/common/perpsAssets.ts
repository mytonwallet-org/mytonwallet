import * as idb from 'idb-keyval';

import type { ApiPerpsGetAssetsResult, OnApiUpdate } from '../types';

import { INDEXED_DB_NAME } from '../../config';
import { logDebugError } from '../../util/logs';
import { callBackendGet } from './backend';

type StoredPerpsAssets = {
  langCode?: string;
  fetchedAt: number;
  result: ApiPerpsGetAssetsResult;
};

const CACHE_KEY = 'perpsAssets';

const cacheStore = idb.createStore(`${INDEXED_DB_NAME}-perps-assets`, 'catalogue');

let cached: StoredPerpsAssets | undefined;
let pending: { langCode?: string; promise: Promise<ApiPerpsGetAssetsResult> } | undefined;
let onUpdate: OnApiUpdate | undefined;
let requestGeneration = 0;

export function setPerpsAssetsUpdater(update: OnApiUpdate) {
  onUpdate = update;
}

/** Restores the last catalogue so the first read does not wait for the network. */
export async function loadPerpsAssetsCache(update?: OnApiUpdate) {
  if (update) onUpdate = update;
  if (cached) return;

  const stored = await readStoredCache();
  // A request that finished while the disk read was in flight is newer than this snapshot
  if (cached) return;
  if (!stored?.result?.assetsByChain) return;

  cached = stored;
  publish();
}

/**
 * Returns the cached `GET /perps/assets` response. A missing catalogue, or one stored for another
 * language, is fetched once and then reused until the periodic refresh replaces it.
 */
export function getPerpsAssets(langCode?: string, signal?: AbortSignal): Promise<ApiPerpsGetAssetsResult> {
  const hit = readCache(langCode);
  if (hit) return Promise.resolve(hit);

  if (!signal && pending && (langCode === undefined || pending.langCode === langCode)) {
    return pending.promise;
  }

  return refreshPerpsAssets(langCode, signal);
}

/** Timestamp of this exact cached catalogue, or zero when its freshness is unknown. */
export function getPerpsAssetsFetchedAt(result: ApiPerpsGetAssetsResult, langCode?: string): number {
  return readCache(langCode) === result && Number.isFinite(cached?.fetchedAt) ? cached!.fetchedAt : 0;
}

/** Always requests `GET /perps/assets` and replaces the cache. */
export function refreshPerpsAssets(langCode?: string, signal?: AbortSignal): Promise<ApiPerpsGetAssetsResult> {
  const requestId = ++requestGeneration;
  const promise = fetchPerpsAssets(langCode, signal, requestId).finally(() => {
    if (pending?.promise === promise) pending = undefined;
  });

  if (!signal) pending = { langCode, promise };

  return promise;
}

async function readStoredCache() {
  try {
    return await idb.get<StoredPerpsAssets>(CACHE_KEY, cacheStore);
  } catch (err) {
    logDebugError('perpsAssetsCache', err);
    return undefined;
  }
}

function readCache(langCode?: string) {
  if (!cached?.result.assetsByChain) return undefined;
  if (langCode !== undefined && cached.langCode !== langCode) return undefined;

  return cached.result;
}

async function fetchPerpsAssets(langCode: string | undefined, signal: AbortSignal | undefined, requestId: number) {
  const result = await callBackendGet<ApiPerpsGetAssetsResult>(
    '/perps/assets',
    langCode ? { langCode } : undefined,
    undefined,
    signal,
  );

  if (!result?.assetsByChain) {
    throw new Error('Invalid perps assets response');
  }

  // A newer refresh owns the cache. This caller still receives the response it asked for.
  if (requestId !== requestGeneration) return result;

  cached = { langCode, fetchedAt: Date.now(), result };
  publish();

  try {
    await idb.set(CACHE_KEY, cached, cacheStore);
  } catch (err) {
    logDebugError('perpsAssetsCache', err);
  }

  return result;
}

function publish() {
  if (!onUpdate || !cached) return;

  onUpdate({
    type: 'updatePerpsAssets',
    assets: cached.result,
    langCode: cached.langCode,
    fetchedAt: cached.fetchedAt,
  });
}
