import { createStore, del, get, set } from 'idb-keyval';

import type { GlobalState, PerpsHistoryState, PerpsState } from '../types';

import { INDEXED_DB_NAME } from '../../config';
import { logDebugError } from '../../util/logs';

/**
 * What Futures read from the network and show again at the next launch, as on iOS, so the screens do not start empty.
 * It lives apart from the global cache, which the app writes to `localStorage` on every change. The catalogue is not
 * here, because the SDK keeps its own copy and restores it when polling starts.
 */
export type PerpsReadCache = {
  chartsByAssetId?: PerpsState['chartsByAssetId'];
  historyByAccountId?: Record<string, PerpsCachedHistory>;
};

type PerpsCachedHistory = PerpsHistoryState & {
  /** Tells the wallet of the history from a later wallet that gets the `accountId` of a removed one */
  address: string;
};

const CACHE_KEY = 'read';
// As many trades as the iOS app keeps for an account
const FILLS_LIMIT = 200;

let store: ReturnType<typeof createStore> | undefined;

// The database opens on the first read or write, so a module import does not touch the storage
function getStore() {
  store ??= createStore(`${INDEXED_DB_NAME}-perps-read`, 'cache');

  return store;
}

export async function loadPerpsReadCache() {
  try {
    return await get<PerpsReadCache>(CACHE_KEY, getStore());
  } catch (err) {
    logDebugError('loadPerpsReadCache', err);
    return undefined;
  }
}

export async function savePerpsReadCache(cache: PerpsReadCache) {
  try {
    await set(CACHE_KEY, cache, getStore());
  } catch (err) {
    logDebugError('savePerpsReadCache', err);
  }
}

export async function clearPerpsReadCache() {
  try {
    await del(CACHE_KEY, getStore());
  } catch (err) {
    logDebugError('clearPerpsReadCache', err);
  }
}

/** The newest trades of each account. A cut history goes without its cursor, and its first refresh brings a new one. */
export function buildPerpsReadCache(global: GlobalState): PerpsReadCache {
  const historyByAccountId: Record<string, PerpsCachedHistory> = {};
  for (const [accountId, state] of Object.entries(global.byAccountId)) {
    const history = state.perps?.history;
    const address = global.accounts?.byId[accountId]?.byChain.arbitrum?.address;
    if (!history?.fills.length || !address) continue;

    historyByAccountId[accountId] = {
      address,
      fills: history.fills.slice(0, FILLS_LIMIT),
      fetchedAt: history.fetchedAt,
    };
  }

  return {
    chartsByAssetId: global.perps.chartsByAssetId,
    historyByAccountId,
  };
}
