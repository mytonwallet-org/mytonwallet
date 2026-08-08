import type { ApiActivity, ApiChain, ApiSwapActivity, ApiSwapHistoryItem } from '../types';
import type { WalletOperationIntent } from './activities/reconciler/types';

import { SWAP_API_VERSION, TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import { buildBackendSwapId, getActivityTokenSlugs, parseTxId } from '../../util/activities';
import { mergeSortedActivities, sortActivities } from '../../util/activities/order';
import { getIsSupportedChain, getOrderedAccountChains, getSlugsSupportingCexSwap } from '../../util/chain';
import { HOUR, MINUTE } from '../../util/dateFormat';
import { unique } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { findNativeToken, getChainBySlug } from '../../util/tokens';
import { rememberActiveCexSwaps } from './activities/reconciler/activeCexSwapState';
import { getBackendDexSwapIdsRepresentedByTonAggregates } from './activities/reconciler/backendDexIdentity';
import {
  getCexSwapIdsRepresentedBySourceActivities,
  projectCexSwapActivities,
} from './activities/reconciler/cexSwapReconciler';
import { buildSwapOperationId, getWalletOperationIntents } from './activities/reconciler/operationIntentStore';
import { reconcileTonAggregatorActivitiesForAccount } from './activities/reconciler/tonTraceReconciler';
import { fetchStoredAccount } from './accounts';
import { callBackendGet, callBackendPost } from './backend';
import { getBackendConfigCache } from './cache';
import { buildTokenSlug, getTokenByAddress, getTokenBySlug } from './tokens';

type SwapHistoryAddressByChain = Partial<Record<ApiChain, string>>;

export async function swapGetHistory(address: string, params: {
  fromTimestamp?: number;
  toTimestamp?: number;
  status?: ApiSwapHistoryItem['status'];
  isCex?: boolean;
  asset?: string;
  hashes?: string[];
}): Promise<ApiSwapHistoryItem[]> {
  const { swapVersion } = await getBackendConfigCache();

  const items = await callBackendPost<ApiSwapHistoryItem[]>(`/swap/history/${address}`, {
    ...params,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  });

  return items.map(convertSwapItemToTrusted);
}

export async function swapGetHistoryByAddresses(addressByChain: SwapHistoryAddressByChain, params: {
  fromTimestamp?: number;
  toTimestamp?: number;
  isCex?: boolean;
  token?: string;
  hashes?: string[];
}): Promise<ApiSwapHistoryItem[]> {
  const { swapVersion } = await getBackendConfigCache();

  const items = await callBackendPost<ApiSwapHistoryItem[]>('/swap/history/by-addresses', {
    ...params,
    addressByChain,
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  });

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
  const from = getSwapItemSlug(swap.from, chain);
  const to = getSwapItemSlug(swap.to, chain);

  return {
    ...swap,
    id: buildBackendSwapId(swap.id),
    kind: 'swap',
    from,
    to,
    shouldLoadDetails: !swap.cex,
    ...(swap.cex && {
      extra: {
        reconciliation: {
          operationId: buildSwapOperationId(swap.id),
          sourceActionIds: [buildBackendSwapId(swap.id)],
          hiddenSourceActionIds: [],
          reason: 'cex-swap' as const,
        },
      },
    }),
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

  await callBackendPost(`/swap/history/${address}/${swapId}/update`, {
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    msgHash,
    msgHashNormalized,
    error,
  }, {
    method: 'PATCH',
    authToken,
  });
}

export async function swapReplaceActivities(
  accountId: string,
  activities: ApiActivity[],
  slug?: string,
  isToNow?: boolean,
  options: { incompleteTonTraceIds?: readonly string[] } = {},
): Promise<ApiActivity[]> {
  // Both projections ask the same question of the intent store, and on the native platforms every read of it crosses
  // the bridge, so one read serves the whole pass.
  const intents = activities.length && parseAccountId(accountId).network !== 'testnet'
    ? await getWalletOperationIntents(accountId)
    : [];
  const cexActivities = await swapReplaceCexActivities(accountId, activities, intents, slug, isToNow);
  // TON trace aggregation owns the canonical on-chain representation. Run it before backend DEX projection so an
  // explicitly-identical backend row is suppressed against the aggregate on every platform, not only web reducers.
  const tonActivities = await aggregateTonSwapActivities(accountId, cexActivities, options.incompleteTonTraceIds);
  return swapReplaceBackendDexActivities(accountId, tonActivities, intents, slug, isToNow);
}

const IN_FLIGHT_INTENT_LOOKBACK = HOUR;
const INTENT_TIMESTAMP_MARGIN = MINUTE;

/**
 * A swap row is created moments before its chain transactions, and until finalization it carries no chain hash the
 * request could find it by. A slice that starts at those transactions therefore misses the row of the very trade the
 * slice belongs to. The submit intents name the rows this wallet is waiting for, so the fetch reaches back to cover
 * them. Only the fetch window widens: row visibility keeps the original slice bounds, and a row pulled in this way
 * surfaces only through a transaction that explicitly represents it.
 */
export function getBackendDexHistoryFetchFromTime(
  fromTime: number,
  intents: readonly WalletOperationIntent[],
  now = Date.now(),
) {
  let fetchFromTime = fromTime;

  for (const intent of intents) {
    if (intent.swap?.type !== 'dex' || !intent.swap.submittedHashes?.length) continue;
    if (intent.createdAt < now - IN_FLIGHT_INTENT_LOOKBACK) continue;
    fetchFromTime = Math.min(fetchFromTime, intent.createdAt - INTENT_TIMESTAMP_MARGIN);
  }

  return fetchFromTime;
}

async function swapReplaceBackendDexActivities(
  accountId: string,
  /** Must be sorted */
  activities: ApiActivity[],
  intents: readonly WalletOperationIntent[],
  slug?: string,
  isToNow?: boolean,
): Promise<ApiActivity[]> {
  if (
    !activities.length
    || parseAccountId(accountId).network === 'testnet'
    || !canHaveBackendDexSwap(slug, activities)
  ) {
    return activities;
  }

  try {
    const { byChain: { ton: { address } = {} } } = await fetchStoredAccount(accountId);
    if (!address) return activities;

    const firstTimestamp = activities[0].timestamp;
    const lastTimestamp = activities[activities.length - 1].timestamp;
    const [fromTime, toTime] = firstTimestamp < lastTimestamp
      ? [firstTimestamp, isToNow ? Date.now() : lastTimestamp]
      : [lastTimestamp, isToNow ? Date.now() : firstTimestamp];

    const hashes = unique(activities.flatMap((activity) => [
      parseTxId(activity.id).hash,
      activity.externalMsgHashNorm,
    ].filter((hash): hash is string => Boolean(hash))));
    if (!hashes.length) return activities;

    const swaps = (await swapGetHistory(address, {
      fromTimestamp: getBackendDexHistoryFetchFromTime(fromTime, intents),
      toTimestamp: toTime,
      asset: slug ? getTokenBySlug(slug)?.tokenAddress ?? TONCOIN.symbol : undefined,
      hashes,
      isCex: false,
    })).filter((swap) => !swap.cex);

    if (!swaps.length) return activities;

    const swapsWithSubmittedHashes = swaps.map((swap) => {
      return {
        ...swap,
        hashes: unique([
          ...(swap.hashes ?? []),
          swap.msgHash,
        ].filter((hash): hash is string => Boolean(hash))),
      };
    });
    const backendSwapActivities = swapsWithSubmittedHashes.map((swap) => withBackendDexReconciliationMetadata(
      swapItemToActivity(swap),
      [],
    ));
    const visibleSwapIds = new Set<string>();

    for (const swap of swapsWithSubmittedHashes) {
      const isSwapHere = swap.timestamp > fromTime && swap.timestamp < toTime;
      if (isSwapHere) visibleSwapIds.add(swapItemToActivity(swap).id);
    }

    for (const swapId of getCexSwapIdsRepresentedBySourceActivities(
      activities,
      backendSwapActivities,
      intents,
      true,
    )) {
      visibleSwapIds.add(swapId);
    }

    const { projectedSourceActivities, projectedSwapActivities } = projectBackendDexSwapActivities(
      activities,
      backendSwapActivities,
      visibleSwapIds,
      intents,
    );

    return mergeSortedActivities(sortActivities(projectedSwapActivities), projectedSourceActivities);
  } catch (err) {
    logDebugError('swapReplaceBackendDexActivities', err);
    return activities;
  }
}

async function swapReplaceCexActivities(
  accountId: string,
  /** Must be sorted */
  activities: ApiActivity[],
  intents: readonly WalletOperationIntent[],
  slug?: string,
  isToNow?: boolean,
): Promise<ApiActivity[]> {
  if (!activities.length || parseAccountId(accountId).network === 'testnet' || !canHaveCexSwap(slug, activities)) {
    return activities;
  }

  try {
    const account = await fetchStoredAccount(accountId);
    const addressByChain = getOrderedAccountChains(account.byChain).reduce((result, chain) => {
      const address = account.byChain[chain]?.address;
      if (address) {
        result[chain] = address;
      }

      return result;
    }, {} as SwapHistoryAddressByChain);
    if (!Object.keys(addressByChain).length) {
      return activities;
    }

    const firstTimestamp = activities[0].timestamp;
    const lastTimestamp = activities[activities.length - 1].timestamp;

    const [fromTime, toTime] = firstTimestamp < lastTimestamp
      ? [firstTimestamp, isToNow ? Date.now() : lastTimestamp]
      : [lastTimestamp, isToNow ? Date.now() : firstTimestamp];

    const hashes = unique(activities.flatMap((activity) => [
      parseTxId(activity.id).hash,
      activity.externalMsgHashNorm,
    ].filter((hash): hash is string => Boolean(hash))));

    const swaps = await swapGetHistoryByAddresses(addressByChain, {
      fromTimestamp: fromTime,
      toTimestamp: toTime,
      token: slug ? getSwapHistoryTokenFilter(slug) : undefined,
      hashes,
      isCex: true,
    });

    if (!swaps.length) {
      return activities;
    }

    await rememberActiveCexSwaps(accountId, swaps);

    const allCexSwapActivities = swaps.map((swap) => swapItemToActivity(swap));
    const visibleCexSwapIds = new Set<string>();

    for (const swap of swaps) {
      const isSwapHere = swap.timestamp > fromTime && swap.timestamp < toTime;
      if (isSwapHere) {
        visibleCexSwapIds.add(swapItemToActivity(swap).id);
      }
    }

    // If the backend found a CEX swap through one of this page's raw transaction hashes, emit the canonical swap even
    // when the swap timestamp is just outside the activity page. Otherwise the raw payin/payout could be hidden or
    // filtered without a visible replacement after reload/pagination.
    for (const swapId of getCexSwapIdsRepresentedBySourceActivities(
      activities,
      allCexSwapActivities,
      intents,
    )) {
      visibleCexSwapIds.add(swapId);
    }

    const { projectedSourceActivities, projectedSwapActivities } = projectCexSwapActivities(
      activities,
      allCexSwapActivities,
      visibleCexSwapIds,
      intents,
    );

    // Even though the swap activities returned by the backend are sorted by timestamp, the client-side sorting may differ.
    // It's important to enforce our sorting, because otherwise `mergeSortedActivities` may leave duplicates.
    return mergeSortedActivities(sortActivities(projectedSwapActivities), projectedSourceActivities);
  } catch (err) {
    logDebugError('swapReplaceCexActivities', err);
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

export function projectBackendDexSwapActivities(
  sourceActivities: readonly ApiActivity[],
  backendSwapActivities: readonly ApiSwapActivity[],
  visibleSwapIds: ReadonlySet<string>,
  intents: readonly WalletOperationIntent[],
) {
  const duplicateBackendSwapIds = getBackendDexSwapIdsDuplicatedByTonAggregates(
    sourceActivities,
    backendSwapActivities,
    intents,
  );
  const effectiveVisibleSwapIds = new Set(
    [...visibleSwapIds].filter((id) => !duplicateBackendSwapIds.has(id)),
  );
  const { projectedSourceActivities, projectedSwapActivities } = projectCexSwapActivities(
    sourceActivities,
    backendSwapActivities,
    effectiveVisibleSwapIds,
    intents,
    true,
  );
  const hiddenSourceIdsByOperationId = new Map<string, string[]>();
  const swapIdByOperationId = new Map(projectedSwapActivities.map((swap) => [
    buildSwapOperationId(parseTxId(swap.id).hash),
    swap.id,
  ]));

  for (const activity of projectedSourceActivities) {
    const operationId = activity.extra?.reconciliation?.operationId;
    if (!activity.shouldHide || !operationId) continue;
    hiddenSourceIdsByOperationId.set(operationId, [
      ...(hiddenSourceIdsByOperationId.get(operationId) ?? []),
      activity.id,
    ]);
  }

  return {
    projectedSourceActivities: projectedSourceActivities.map((activity) => {
      if (!activity.shouldHide) return activity;
      const operationId = activity.extra?.reconciliation?.operationId;
      if (!operationId) return activity;
      return withBackendDexReconciliationMetadata(
        activity,
        hiddenSourceIdsByOperationId.get(operationId) ?? [activity.id],
        operationId,
        swapIdByOperationId.get(operationId) ?? activity.id,
      );
    }),
    projectedSwapActivities: projectedSwapActivities.map((swap) => {
      return withBackendDexReconciliationMetadata(
        swap,
        hiddenSourceIdsByOperationId.get(buildSwapOperationId(parseTxId(swap.id).hash)) ?? [],
      );
    }),
  };
}

export function getBackendDexSwapIdsDuplicatedByTonAggregates(
  sourceActivities: readonly ApiActivity[],
  backendSwapActivities: readonly ApiSwapActivity[],
  intents: readonly WalletOperationIntent[],
) {
  return getBackendDexSwapIdsRepresentedByTonAggregates(
    sourceActivities.filter(isVisibleTonAggregateSwap),
    backendSwapActivities,
    intents,
  );
}

function isVisibleTonAggregateSwap(activity: ApiActivity): activity is ApiSwapActivity {
  return activity.kind === 'swap'
    && activity.shouldHide !== true
    && Boolean(activity.extra?.mtwAggregator)
    && activity.extra?.reconciliation?.reason === 'ton-aggregated-swap';
}

function withBackendDexReconciliationMetadata<T extends ApiActivity>(
  activity: T,
  hiddenSourceActionIds: string[],
  operationId = buildSwapOperationId(parseTxId(activity.id).hash),
  sourceActivityId = activity.id,
): T {
  return {
    ...activity,
    extra: {
      ...activity.extra,
      reconciliation: {
        operationId,
        sourceActionIds: unique([sourceActivityId, ...hiddenSourceActionIds]),
        hiddenSourceActionIds,
        reason: 'ton-aggregated-swap',
      },
    },
  };
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

export async function aggregateTonSwapActivities(
  accountId: string,
  activities: readonly ApiActivity[],
  incompleteTraceIds: readonly string[] = [],
) {
  const result = await reconcileTonAggregatorActivitiesForAccount(
    accountId,
    activities,
    { incompleteTraceIds },
  );
  return result.activities;
}
