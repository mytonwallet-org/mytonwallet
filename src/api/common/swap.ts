import type { ApiAccountAny, ApiActivity, ApiChain, ApiSwapActivity, ApiSwapHistoryItem } from '../types';

import { SWAP_API_VERSION, TONCOIN } from '../../config';
import { throwIfAborted } from '../../util/abortSignal';
import { parseAccountId } from '../../util/account';
import { buildBackendSwapId, getActivityTokenSlugs, parseTxId } from '../../util/activities';
import { getIsSupportedChain, getOrderedAccountChains, getSlugsSupportingCexSwap } from '../../util/chain';
import { unique } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { findNativeToken, getChainBySlug } from '../../util/tokens';
import { projectSwapActivities } from './activities/swapReconciler';
import { fetchStoredAccount } from './accounts';
import { callBackendGet, callBackendPost } from './backend';
import { getBackendConfigCache } from './cache';
import { buildTokenSlug, getTokenByAddress, getTokenBySlug } from './tokens';

type SwapHistoryAddressByChain = Partial<Record<ApiChain, string>>;

export function getSwapHistoryAddressByChain(account: Pick<ApiAccountAny, 'byChain'>) {
  return getOrderedAccountChains(account.byChain).reduce((result, chain) => {
    const address = account.byChain[chain]?.address;
    if (address) result[chain] = address;
    return result;
  }, {} as SwapHistoryAddressByChain);
}

export async function swapGetHistory(address: string, params: {
  fromTimestamp?: number;
  toTimestamp?: number;
  status?: ApiSwapHistoryItem['status'];
  isCex?: boolean;
  asset?: string;
  hashes?: string[];
}, signal?: AbortSignal): Promise<ApiSwapHistoryItem[]> {
  const { swapVersion } = await getBackendConfigCache();

  const items = await callBackendPost<ApiSwapHistoryItem[]>(`/swap/history/${address}`, {
    ...params,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  }, { signal });

  return items.map(convertSwapItemToTrusted);
}

export async function swapGetHistoryByAddresses(addressByChain: SwapHistoryAddressByChain, params: {
  fromTimestamp?: number;
  toTimestamp?: number;
  isCex?: boolean;
  token?: string;
  hashes?: string[];
}, signal?: AbortSignal): Promise<ApiSwapHistoryItem[]> {
  const { swapVersion } = await getBackendConfigCache();

  const items = await callBackendPost<ApiSwapHistoryItem[]>('/swap/history/by-addresses', {
    ...params,
    addressByChain,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  }, { signal });

  return items.map(convertSwapItemToTrusted);
}

export async function swapGetHistoryItem(
  address: string,
  id: string,
  options: { authToken?: string; forceProviderRefresh?: boolean } = {},
): Promise<ApiSwapHistoryItem> {
  const { swapVersion } = await getBackendConfigCache();

  const item = await callBackendGet<ApiSwapHistoryItem>(`/swap/history/${address}/${id}`, {
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    forceProviderRefresh: options.forceProviderRefresh || undefined,
  }, options.authToken ? { 'X-Auth-Token': options.authToken } : undefined);

  return convertSwapItemToTrusted(item);
}

export function swapItemToActivity(swap: ApiSwapHistoryItem, chain?: ApiChain): ApiSwapActivity {
  return {
    ...swap,
    id: buildBackendSwapId(swap.id),
    kind: 'swap',
    from: getSwapItemSlug(swap.from, chain),
    to: getSwapItemSlug(swap.to, chain),
    shouldLoadDetails: !swap.cex,
  };
}

// FIXME: TON renaming
export function getSwapItemSlug(asset: string, legacyChain?: ApiChain) {
  if (asset === 'TON' || asset === TONCOIN.symbol) {
    return TONCOIN.slug;
  }

  const newBackendIdSlug = getNewBackendIdSlug(asset);
  if (newBackendIdSlug) {
    return newBackendIdSlug;
  }

  return getTokenBySlug(asset)?.slug
    ?? (legacyChain ? getTokenByAddress(asset, legacyChain)?.slug : undefined)
    ?? getTokenByAddress(asset)?.slug
    ?? asset;
}

function getNewBackendIdSlug(asset: string) {
  const [chain, tokenAddressOrNative, extra] = asset.split(':');
  if (extra !== undefined || !tokenAddressOrNative || !getIsSupportedChain(chain)) {
    return undefined;
  }

  if (tokenAddressOrNative === 'native') {
    return findNativeToken(chain)?.slug;
  }

  return getTokenByAddress(tokenAddressOrNative, chain)?.slug ?? buildTokenSlug(chain, tokenAddressOrNative);
}

export function getSwapHistoryTokenFilter(slug: string) {
  const token = getTokenBySlug(slug);
  if (token?.tokenAddress) {
    return token.tokenAddress;
  }

  return slug === TONCOIN.slug ? 'TON' : slug;
}

export async function patchSwapItem(options: {
  address: string;
  swapId: string;
  authToken: string;
  msgHash?: string;
  msgHashNormalized?: string;
  error?: string;
}) {
  const {
    address, swapId, authToken, msgHash, msgHashNormalized, error,
  } = options;

  const { swapVersion } = await getBackendConfigCache();

  return callBackendPost<ApiSwapHistoryItem | undefined>(`/swap/history/${address}/${swapId}/update`, {
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    msgHash,
    msgHashNormalized,
    error,
  }, {
    method: 'PATCH',
    authToken,
  });
}

/**
 * Merges the backend swap history into a sorted slice of chain activities: the backend rows of the slice's time
 * window and of the hashes it contains are fetched (cross-chain rows by every account address, TON DEX rows by the
 * TON address), then the slice is projected so that each swap is one row. The backend answers with rows matching
 * either the window or the hashes, so a row created moments before its first chain action is still reached.
 */
export async function swapReplaceActivities(
  accountId: string,
  /** Must be sorted */
  activities: ApiActivity[],
  slug?: string,
  isToNow?: boolean,
  signal?: AbortSignal,
): Promise<ApiActivity[]> {
  if (!activities.length || parseAccountId(accountId).network === 'testnet') {
    return activities;
  }

  try {
    const addressByChain = getSwapHistoryAddressByChain(await fetchStoredAccount(accountId));
    const tonAddress = addressByChain.ton;

    const timestamps = activities.map(({ timestamp }) => timestamp);
    const fromTime = Math.min(...timestamps);
    const toTime = isToNow ? Date.now() : Math.max(...timestamps);
    const hashes = unique(activities.flatMap((activity) => [
      parseTxId(activity.id).hash,
      activity.externalMsgHashNorm,
    ].filter((hash): hash is string => Boolean(hash))));

    const [cexRows, dexRows] = await Promise.all([
      Object.keys(addressByChain).length && canHaveCexSwap(slug, activities)
        ? swapGetHistoryByAddresses(addressByChain, {
          fromTimestamp: fromTime,
          toTimestamp: toTime,
          token: slug ? getSwapHistoryTokenFilter(slug) : undefined,
          hashes,
          isCex: true,
        }, signal)
        : [],
      tonAddress && canHaveBackendDexSwap(slug, activities)
        ? swapGetHistory(tonAddress, {
          fromTimestamp: fromTime,
          toTimestamp: toTime,
          asset: slug ? getTokenBySlug(slug)?.tokenAddress ?? TONCOIN.symbol : undefined,
          hashes,
          isCex: false,
        }, signal)
        : [],
    ]);

    const rowsById = new Map([...cexRows, ...dexRows.filter((swap) => !swap.cex)].map((swap) => [swap.id, swap]));
    if (!rowsById.size) return activities;
    const swapRows = [...rowsById.values()].map((swap) => swapItemToActivity(swap));

    return projectSwapActivities(activities, swapRows, { fromTime, toTime });
  } catch (err) {
    throwIfAborted(signal);
    logDebugError('swapReplaceActivities', err);
    return activities;
  }
}

function canHaveBackendDexSwap(slug: string | undefined, activities: ApiActivity[]) {
  if (slug) return isTonSlug(slug);

  return activities.some((activity) => {
    return getActivityTokenSlugs(activity).some(isTonSlug);
  });
}

function isTonSlug(slug: string) {
  try {
    return getChainBySlug(slug) === 'ton';
  } catch {
    return false;
  }
}

function canHaveCexSwap(slug: string | undefined, activities: ApiActivity[]): boolean {
  // In cross-chain swaps, only a few tokens are available.
  // It’s not optimal to request swap history for all the others.
  const slugsSupportingCexSwap = getSlugsSupportingCexSwap();

  if (slug) {
    return slugsSupportingCexSwap.has(slug);
  }

  return activities.some((activity) => {
    return getActivityTokenSlugs(activity).some((slug) => {
      return slugsSupportingCexSwap.has(slug);
    });
  });
}

export function convertSwapItemToTrusted(swap: ApiSwapHistoryItem): ApiSwapHistoryItem {
  return {
    ...swap,
    status: swap.status === 'pending' ? 'pendingTrusted' : swap.status,
  };
}
