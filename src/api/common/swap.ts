import type { ApiActivity, ApiSwapActivity, ApiSwapHistoryItem } from '../types';

import { MTW_AGGREGATOR_QUERY_ID, SWAP_API_VERSION, TONCOIN } from '../../config';
import { Big } from '../../lib/big.js';
import { parseAccountId } from '../../util/account';
import { buildBackendSwapId, getActivityTokenSlugs, getIsBackendSwapId, parseTxId } from '../../util/activities';
import { mergeSortedActivities, sortActivities } from '../../util/activities/order';
import { getSlugsSupportingCexSwap } from '../../util/chain';
import { unique } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { getChainBySlug } from '../../util/tokens';
import { fetchStoredAccount } from './accounts';
import { callBackendGet, callBackendPost } from './backend';
import { getBackendConfigCache } from './cache';
import { buildTokenSlug, getTokenByAddress, getTokenBySlug } from './tokens';

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

export async function swapGetHistoryItem(address: string, id: string): Promise<ApiSwapHistoryItem> {
  const { swapVersion } = await getBackendConfigCache();

  const item = await callBackendGet<ApiSwapHistoryItem>(`/swap/history/${address}/${id}`, {
    swapVersion: swapVersion ?? SWAP_API_VERSION,
  });

  return convertSwapItemToTrusted(item);
}

export function swapItemToActivity(swap: ApiSwapHistoryItem): ApiSwapActivity {
  return {
    ...swap,
    id: buildBackendSwapId(swap.id),
    kind: 'swap',
    from: getSwapItemSlug(swap, swap.from),
    to: getSwapItemSlug(swap, swap.to),
    shouldLoadDetails: !swap.cex,
  };
}

export function getSwapItemSlug(item: ApiSwapHistoryItem, asset: string) {
  if (asset === TONCOIN.symbol) {
    return TONCOIN.slug;
  }
  if (item.cex) {
    return getTokenByAddress(asset)?.slug ?? asset;
  }
  return buildTokenSlug('ton', asset);
}

export async function patchSwapItem(options: {
  address: string;
  swapId: string;
  authToken: string;
  msgHash?: string;
  error?: string;
}) {
  const {
    address, swapId, authToken, msgHash, error,
  } = options;

  const { swapVersion } = await getBackendConfigCache();

  await callBackendPost(`/swap/history/${address}/${swapId}/update`, {
    swapVersion: swapVersion ?? SWAP_API_VERSION,
    msgHash,
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
): Promise<ApiActivity[]> {
  const cexActivities = await swapReplaceCexActivities(accountId, activities, slug, isToNow);
  return aggregateTonSwapActivities(cexActivities);
}

async function swapReplaceCexActivities(
  accountId: string,
  /** Must be sorted */
  activities: ApiActivity[],
  slug?: string,
  isToNow?: boolean,
): Promise<ApiActivity[]> {
  if (!activities.length || parseAccountId(accountId).network === 'testnet' || !canHaveCexSwap(slug, activities)) {
    return activities;
  }

  try {
    const { byChain: { ton: { address } = {} } } = await fetchStoredAccount(accountId);
    if (!address) {
      return activities;
    }

    const firstTimestamp = activities[0].timestamp;
    const lastTimestamp = activities[activities.length - 1].timestamp;

    const [fromTime, toTime] = firstTimestamp < lastTimestamp
      ? [firstTimestamp, isToNow ? Date.now() : lastTimestamp]
      : [lastTimestamp, isToNow ? Date.now() : firstTimestamp];

    const hashes = activities.map(({ id }) => parseTxId(id).hash);

    const swaps = await swapGetHistory(address, {
      fromTimestamp: fromTime,
      toTimestamp: toTime,
      asset: slug ? getTokenBySlug(slug)?.tokenAddress ?? TONCOIN.symbol : undefined,
      hashes,
      isCex: true,
    });

    if (!swaps.length) {
      return activities;
    }

    const swapActivities: ApiActivity[] = [];
    const allSwapHashes = new Set<string>();

    for (const swap of swaps) {
      swap.hashes.forEach((hash) => allSwapHashes.add(hash));

      const isSwapHere = swap.timestamp > fromTime && swap.timestamp < toTime;
      if (isSwapHere) {
        swapActivities.push(swapItemToActivity(swap));
      }
    }

    const otherActivities = activities.map((activity) => {
      if (activity.kind === 'transaction' && allSwapHashes.has(parseTxId(activity.id).hash)) {
        return { ...activity, shouldHide: true };
      } else {
        return activity;
      }
    });

    // Even though the swap activities returned by the backend are sorted by timestamp, the client-side sorting may differ.
    // It's important to enforce our sorting, because otherwise `mergeSortedActivities` may leave duplicates.
    return mergeSortedActivities(sortActivities(swapActivities), otherActivities);
  } catch (err) {
    logDebugError('swapReplaceCexActivities', err);
    return activities;
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

function aggregateTonSwapActivities(activities: ApiActivity[]) {
  if (!activities.length) {
    return activities;
  }

  const aggregatorTraceIds = getAggregatorTraceIdsStorage();

  const traceMap = new Map<string, {
    swaps: { activity: ApiSwapActivity; index: number }[];
    hasAggregatorMarker: boolean;
  }>();

  activities.forEach((activity, index) => {
    const traceId = parseTxId(activity.id).hash;
    const group = traceMap.get(traceId) ?? { swaps: [], hasAggregatorMarker: false };

    if (
      !getIsBackendSwapId(activity.id)
      && activity.kind === 'swap'
      && getChainBySlug(activity.from) === 'ton'
      && getChainBySlug(activity.to) === 'ton'
    ) {
      group.swaps.push({ activity, index });
    }

    if (
      activity.extra?.queryId === MTW_AGGREGATOR_QUERY_ID
      || activity.extra?.isOurSwapFee
    ) {
      group.hasAggregatorMarker = true;
    }

    traceMap.set(traceId, group);
  });

  const replacements = new Map<number, ApiActivity>();
  const skipIndices = new Set<number>();

  traceMap.forEach((group, traceId) => {
    const aggregated = buildAggregatedSwap(traceId, group, aggregatorTraceIds.has(traceId));
    if (!aggregated) {
      return;
    }

    aggregatorTraceIds.add(traceId);
    const { aggregatedActivity, primaryIndex, swapIndices } = aggregated;

    replacements.set(primaryIndex, aggregatedActivity);
    swapIndices.forEach((swapIndex) => {
      if (swapIndex !== primaryIndex) {
        skipIndices.add(swapIndex);
      }
    });
  });

  if (!replacements.size && !skipIndices.size) {
    return activities;
  }

  const result: ApiActivity[] = [];

  activities.forEach((activity, index) => {
    if (skipIndices.has(index) && !replacements.has(index)) {
      return;
    }

    const replacement = replacements.get(index);
    result.push(replacement ?? activity);
  });

  return sortActivities(result);
}

function buildAggregatedSwap(
  traceId: string,
  group: {
    swaps: { activity: ApiSwapActivity; index: number }[];
    hasAggregatorMarker: boolean;
  },
  isKnownAggregatorTrace: boolean,
) {
  const { swaps, hasAggregatorMarker } = group;

  if (!isKnownAggregatorTrace && (!hasAggregatorMarker || swaps.length < 2)) {
    return undefined;
  }

  if (swaps.some(({ activity }) => activity.status !== 'completed')) {
    return undefined;
  }

  const swapIds = swaps.map(({ activity }) => activity.id);
  const primaryIndex = Math.min(...swaps.map(({ index }) => index));
  const primarySwap = swaps.find(({ index }) => index === primaryIndex)?.activity ?? swaps[0].activity;

  const totals = new Map<string, Big>();
  let timestamp = 0;
  let networkFee = Big(0);
  let swapFee = Big(0);
  let ourFee = Big(0);

  swaps.forEach(({ activity }) => {
    timestamp = Math.max(timestamp, activity.timestamp);

    totals.set(activity.from, (totals.get(activity.from) || Big(0)).minus(activity.fromAmount));
    totals.set(activity.to, (totals.get(activity.to) || Big(0)).add(activity.toAmount));

    networkFee = networkFee.add(activity.networkFee);
    swapFee = swapFee.add(activity.swapFee);
    ourFee = ourFee.add(activity.ourFee || '0');
  });

  const aggregatedAmounts = resolveAggregatedAmounts(totals, swaps.map(({ activity }) => activity));
  if (!aggregatedAmounts) {
    return undefined;
  }

  const aggregatedActivity: ApiSwapActivity = {
    ...primarySwap,
    ...aggregatedAmounts,
    timestamp,
    networkFee: networkFee.toString(),
    swapFee: swapFee.toString(),
    ourFee: ourFee.toString(),
    hashes: unique(swaps.flatMap(({ activity }) => activity.hashes)),
    extra: {
      ...primarySwap.extra,
      mtwAggregator: {
        traceId,
        swapIds,
        from: aggregatedAmounts.from,
        to: aggregatedAmounts.to,
      },
    },
  };

  return {
    aggregatedActivity,
    primaryIndex,
    swapIndices: swaps.map(({ index }) => index),
  };
}

function resolveAggregatedAmounts(
  totals: Map<string, Big>,
  swaps: ApiSwapActivity[],
) {
  let fromSlug = swaps[0]?.from;
  let toSlug = swaps[swaps.length - 1]?.to;
  let minEntry: [string, Big] | undefined;
  let maxEntry: [string, Big] | undefined;

  totals.forEach((value, slug) => {
    if (!minEntry || value.lt(minEntry[1])) {
      minEntry = [slug, value];
    }
    if (!maxEntry || value.gt(maxEntry[1])) {
      maxEntry = [slug, value];
    }
  });

  const fromAmount = minEntry && minEntry[1].lt(0) ? minEntry[1].times(-1) : Big(swaps[0].fromAmount);
  const toAmount = maxEntry && maxEntry[1].gt(0) ? maxEntry[1] : Big(swaps[swaps.length - 1].toAmount);

  if (minEntry && minEntry[1].lt(0)) {
    fromSlug = minEntry[0];
  }
  if (maxEntry && maxEntry[1].gt(0)) {
    toSlug = maxEntry[0];
  }

  if (!fromSlug || !toSlug) {
    return undefined;
  }

  return {
    from: fromSlug,
    to: toSlug,
    fromAmount: fromAmount.toString(),
    toAmount: toAmount.toString(),
  };
}

function getAggregatorTraceIdsStorage() {
  // Module-level storage to reuse knowledge about aggregator traces between different slices
  // (e.g., token-specific pagination that may miss TON-fee markers).
  aggregatorTraceIdsStorage ??= new Set<string>();
  return aggregatorTraceIdsStorage;
}

let aggregatorTraceIdsStorage: Set<string> | undefined;
