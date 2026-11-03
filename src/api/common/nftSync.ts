import * as idb from 'idb-keyval';

import type { Storage } from '../storages/types';
import type { ApiChain, ApiNetwork } from '../types';

import { INDEXED_DB_NAME } from '../../config';
import { mergeAbortSignalsWithTimeout, raceWithAbortSignal, throwIfAborted } from '../../util/abortSignal';
import { parseAccountId } from '../../util/account';
import { classifyFetchFailure } from '../../util/fetch';
import { isLiteralObject } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { createTaskQueue } from '../../util/schedulers';
import { MINUTE, SEC } from '../constants';
import { ApiServerError } from '../errors';
import { getCurrentStorage } from '../storages';
import { callBackendGet } from './backend';

export type NftItemWire = {
  address: string;
  init: boolean;
  index: string;
  collection_address?: string | null;
  owner_address?: string | null;
  real_owner?: string | null;
  on_sale?: boolean;
  content?: { uri?: string };
  last_transaction_lt?: string;
};

export type NftSyncSnapshot = {
  schemaVersion: 1;
  syncToken: string;
  items: Record<string, NftItemWire>;
  metadata: Record<string, unknown>;
};

type NftSyncPage = {
  syncToken: string;
  reset: boolean;
  hasMore: boolean;
  items: NftItemWire[];
  removed: string[];
  metadata: Record<string, unknown>;
};

const snapshotStore = idb.createStore(`${INDEXED_DB_NAME}-nft-sync`, 'snapshots');

const states = new WeakMap<Storage, {
  queue: ReturnType<typeof createTaskQueue>;
  unavailableUntil: Map<string, number>;
  invalidSnapshots: Set<string>;
}>();

function getState(storage: Storage) {
  let state = states.get(storage);
  if (!state) {
    state = { queue: createTaskQueue(), unavailableUntil: new Map(), invalidSnapshots: new Set() };
    states.set(storage, state);
  }
  return state;
}

export function createNftSync(
  accountId: string,
  chain: ApiChain,
  network: ApiNetwork,
  owner: string,
  validateSnapshot?: (snapshot: NftSyncSnapshot, changedAddresses?: readonly string[]) => MaybePromise<void>,
) {
  const storage = getCurrentStorage();
  const state = getState(storage);
  const endpointKey = `${chain}/${network}`;
  const snapshotKey = `${accountId}:${chain}`;
  let snapshot: NftSyncSnapshot | undefined;
  let isLoaded = false;
  let isUnavailable = false;
  let retryAt: number | undefined;
  let isCacheUnavailable = false;
  const requests = createTaskQueue();

  async function load() {
    if (isLoaded) return snapshot;
    isLoaded = true;
    if (state.invalidSnapshots.has(snapshotKey)) return undefined;

    try {
      const stored = await idb.get(snapshotKey, snapshotStore);
      if (stored === undefined) return undefined;
      if (!isSnapshot(stored)) throw new Error('Invalid stored NFT snapshot');
      await validateSnapshot?.(stored);
      snapshot = stored;
    } catch (err) {
      await invalidateCache('nftSync load', err);
    }
    return snapshot;
  }

  async function sync(signal?: AbortSignal) {
    if (isUnavailable || Date.now() < Math.max(retryAt ?? 0, state.unavailableUntil.get(endpointKey) ?? 0)) {
      return undefined;
    }

    let isRequestError = false;
    let retryDelay: number | undefined;
    try {
      await load();
      throwIfAborted(signal);
      const previous = snapshot;
      let syncToken = previous?.syncToken;
      let items = previous?.items ?? {};
      let metadata = previous?.metadata ?? {};
      let hasCopied = !previous;
      let hasChanges = false;
      let reset = false;
      const changedAddresses = new Set<string>();
      const seenTokens = new Set<string>();

      while (true) {
        const deadline = mergeAbortSignalsWithTimeout(25000, signal);
        let page: unknown;
        isRequestError = true;
        try {
          page = await raceWithAbortSignal(async () => {
            const response = await callBackendGet(
              `/nfts/${chain}/${network}/${encodeURIComponent(owner)}`,
              { since: syncToken },
              undefined,
              deadline.signal,
              { shouldReturnResponse: true, shouldRetry: false, timeout: 25000 },
            );
            if (response.status === 202) {
              retryDelay = MINUTE;
              const body: unknown = await response.json().catch(() => undefined);
              const retryAfter = isLiteralObject(body) ? body.retryAfter : undefined;
              if (typeof retryAfter === 'number' && Number.isFinite(retryAfter)) {
                retryDelay = Math.min(5 * MINUTE, Math.max(5 * SEC, retryAfter * SEC));
              }
            }
            if (response.status !== 200) {
              throw new ApiServerError(`Unexpected NFT sync status ${response.status}`, response.status);
            }
            return response.json();
          }, deadline.signal);
        } finally {
          deadline.cleanup();
        }
        isRequestError = false;
        throwIfAborted(signal);
        if (!isPage(page) || (!syncToken && !page.reset)) throw new Error('Invalid NFT sync response');

        if (page.reset) {
          reset = true;
          items = {};
          metadata = {};
          hasCopied = true;
          changedAddresses.clear();
        }
        const metadataAddresses = Object.keys(page.metadata);
        if (page.items.length || page.removed.length || metadataAddresses.length) {
          hasChanges = true;
          if (!hasCopied) {
            items = { ...items };
            metadata = { ...metadata };
            hasCopied = true;
          }
          for (const address of page.removed) {
            changedAddresses.add(address);
            delete items[address];
          }
          for (const item of page.items) {
            changedAddresses.add(item.address);
            items[item.address] = item;
          }
          for (const address of metadataAddresses) metadata[address] = page.metadata[address];
        }
        syncToken = page.syncToken;
        if (!page.hasMore) break;
        if (seenTokens.has(syncToken)) throw new Error('NFT sync pagination did not advance');
        seenTokens.add(syncToken);
      }

      if (previous && !reset && !hasChanges && syncToken === previous.syncToken) {
        retryAt = undefined;
        state.unavailableUntil.delete(endpointKey);
        return { previous, snapshot: previous, reset, changedAddresses: [] };
      }

      let usedMetadata = metadata;
      if (reset || hasChanges) {
        usedMetadata = {};
        for (const item of Object.values(items)) {
          for (const address of [item.address, item.collection_address]) {
            if (address && Object.hasOwn(metadata, address)) usedMetadata[address] = metadata[address];
          }
        }
      }
      const addresses = [...changedAddresses];
      const next: NftSyncSnapshot = { schemaVersion: 1, syncToken, items, metadata: usedMetadata };
      await validateSnapshot?.(next, reset ? undefined : addresses);
      throwIfAborted(signal);

      const isAccountPresent = await state.queue.run(async () => {
        throwIfAborted(signal);
        const accounts = await storage.getItem('accounts');
        if (!accounts?.[accountId]?.byChain?.[chain]) return false;
        if (isCacheUnavailable) return true;
        try {
          await idb.set(snapshotKey, next, snapshotStore);
          state.invalidSnapshots.delete(snapshotKey);
        } catch (err) {
          await invalidateCache('nftSync persist', err);
        }
        const currentAccounts = await storage.getItem('accounts', true);
        if (!currentAccounts?.[accountId]?.byChain?.[chain]) {
          await idb.del(snapshotKey, snapshotStore);
          return false;
        }
        return true;
      });
      if (!isAccountPresent) return undefined;
      snapshot = next;
      throwIfAborted(signal);
      retryAt = undefined;
      state.unavailableUntil.delete(endpointKey);
      return { previous, snapshot: next, reset, changedAddresses: addresses };
    } catch (err) {
      if (signal?.aborted) return undefined;
      if (isRequestError && err instanceof ApiServerError && err.statusCode === 404) {
        state.unavailableUntil.set(endpointKey, Date.now() + 60 * MINUTE);
      } else if (isRequestError && !(err instanceof SyntaxError) && (retryDelay !== undefined
        || !(err instanceof ApiServerError)
        || err.statusCode === undefined
        || (err.statusCode >= 400 && classifyFetchFailure(err.statusCode) === 'retryable'))) {
        retryAt = Date.now() + (retryDelay ?? 5 * MINUTE);
      } else {
        isUnavailable = true;
      }
      logDebugError(
        err instanceof ApiServerError && err.statusCode === 400 ? 'nftSync programming error' : 'nftSync request',
        err,
      );
      return undefined;
    }
  }

  async function invalidateCache(message: string, err: unknown) {
    isCacheUnavailable = true;
    state.invalidSnapshots.add(snapshotKey);
    logDebugError(message, err);
    try {
      await idb.del(snapshotKey, snapshotStore);
    } catch (cleanupError) {
      logDebugError('nftSync invalidate', cleanupError);
    }
  }

  return {
    load,
    sync: (signal?: AbortSignal) => requests.run(() => sync(signal)),
    getRetryAt: () => {
      if (isUnavailable) return undefined;
      const times = [retryAt, state.unavailableUntil.get(endpointKey)]
        .filter((time): time is number => time !== undefined && time > Date.now());
      return times.length ? Math.max(...times) : undefined;
    },
  };
}

export function removeNftSyncSnapshots(accountId?: string, network?: ApiNetwork) {
  const storage = getCurrentStorage();
  return getState(storage).queue.run(async () => {
    try {
      const keys = await idb.keys<string>(snapshotStore);
      const removed = keys.filter((key) => {
        const id = key.slice(0, key.lastIndexOf(':'));
        return accountId !== undefined
          ? id === accountId
          : network === undefined || parseAccountId(id).network === network;
      });
      if (removed.length) await idb.delMany(removed, snapshotStore);
    } catch (err) {
      logDebugError('nftSync remove', err);
    }
  });
}

function isSnapshot(value: unknown): value is NftSyncSnapshot {
  return isLiteralObject(value) && value.schemaVersion === 1 && isToken(value.syncToken)
    && isLiteralObject(value.items) && Object.entries(value.items).every(([address, item]) => (
    isItem(item) && address === item.address
  )) && isMetadata(value.metadata);
}

function isPage(value: unknown): value is NftSyncPage {
  return isLiteralObject(value) && isToken(value.syncToken)
    && typeof value.reset === 'boolean' && typeof value.hasMore === 'boolean'
    && Array.isArray(value.items) && value.items.every(isItem)
    && Array.isArray(value.removed) && value.removed.every(isToken)
    && (!value.reset || value.removed.length === 0) && isMetadata(value.metadata);
}

function isToken(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

function isItem(value: unknown): value is NftItemWire {
  return isLiteralObject(value) && isToken(value.address) && typeof value.init === 'boolean'
    && typeof value.index === 'string'
    && ['collection_address', 'owner_address', 'real_owner'].every((key) => (
      value[key] === undefined || value[key] === null || isToken(value[key]) // eslint-disable-line no-null/no-null
    )) && (value.on_sale === undefined || typeof value.on_sale === 'boolean')
    && (value.last_transaction_lt === undefined || typeof value.last_transaction_lt === 'string')
    && (value.content === undefined || (isLiteralObject(value.content)
      && (value.content.uri === undefined || typeof value.content.uri === 'string')));
}

function isMetadata(value: unknown): value is Record<string, unknown> {
  return isLiteralObject(value) && Object.values(value).every((entry) => (
    isLiteralObject(entry) && typeof entry.is_indexed === 'boolean'
    && Array.isArray(entry.token_info) && entry.token_info.every(isLiteralObject)
  ));
}
