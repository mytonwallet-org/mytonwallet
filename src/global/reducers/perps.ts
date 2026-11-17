import type {
  ApiPerpsActivityHistory,
  ApiPerpsFill,
  ApiPerpsGetAssetsResult,
  ApiPerpsListedAsset,
  ApiPerpsMarketAsset,
  ApiPerpsMarketSnapshot,
  ApiPerpsOperation,
  ApiPerpsQuote,
  ApiPerpsSnapshot,
  ApiPriceHistoryPeriod,
} from '../../api/types';
import type { PerpsReadCache } from '../helpers/perpsReadCache';
import type {
  AccountPerpsState,
  GlobalState,
  LangCode,
  PerpsAssetDetailState,
  PerpsBalanceDepositProgress,
  PerpsChartState,
  PerpsHistoryState,
  PerpsMarketDetailState,
  PerpsNavigation,
  PerpsOpenedActivity,
  PerpsOperationReceipt,
  PerpsTradeState,
  PriceHistoryPeriods,
} from '../types';

import { areDeepEqual } from '../../util/areDeepEqual';
import { omit, pick } from '../../util/iteratees';
import { getPerpsFillKey } from '../helpers/perps';
import { selectAccountState, selectIsWalletTabActive } from '../selectors/accounts';
import { updateAccountState } from './misc';

const CHARTS_LIMIT = 24;
export const MARKET_SNAPSHOT_KEYS: (keyof ApiPerpsMarketSnapshot)[] = [
  'assets', 'marketSections', 'limits', 'assetsFetchedAt',
];

export function updatePerpsMarket(
  global: GlobalState,
  market: ApiPerpsMarketSnapshot,
  langCode?: LangCode,
): GlobalState {
  return updatePerps(global, { market: { ...market, langCode }, isMarketLoadFailed: undefined });
}

/** Puts the fresher market of its detail into the catalogue. The detail has no sparkline, so the old one stays. */
export function updatePerpsMarketAsset(global: GlobalState, asset: ApiPerpsMarketAsset): GlobalState {
  const { market } = global.perps;
  const index = market?.assets.findIndex(({ id }) => id === asset.id) ?? -1;
  if (!market || index === -1) return global;

  const assets = [...market.assets];
  assets[index] = { ...asset, sparkline: asset.sparkline ?? assets[index].sparkline };

  return updatePerps(global, { market: { ...market, assets } });
}

export function markPerpsMarketLoadFailed(global: GlobalState): GlobalState {
  return global.perps.isMarketLoadFailed ? global : updatePerps(global, { isMarketLoadFailed: true });
}

export function updateAccountPerps(
  global: GlobalState,
  accountId: string,
  partial: Partial<AccountPerpsState>,
): GlobalState {
  if (!global.accounts?.byId[accountId]) return global;

  return updateAccountState(global, accountId, {
    perps: {
      ...selectAccountState(global, accountId)?.perps,
      ...partial,
    },
  });
}

/**
 * A snapshot that misses some books would drop the positions in them and understate the totals, so it replaces only
 * an absent snapshot. The last positions and totals stay with the new `unavailableDexs`, which mark them as
 * incomplete, and with the new `tradingAvailability`, which does not depend on the books.
 */
export function updatePerpsSnapshot(global: GlobalState, accountId: string, snapshot: ApiPerpsSnapshot) {
  const current = selectAccountState(global, accountId)?.perps?.snapshot;
  const isIncomplete = snapshot.unavailableDexs.length > 0;

  return updateAccountPerps(global, accountId, {
    snapshot: isIncomplete && current
      ? { ...current, unavailableDexs: snapshot.unavailableDexs, tradingAvailability: snapshot.tradingAvailability }
      : omit(snapshot, MARKET_SNAPSHOT_KEYS),
    isSnapshotLoadFailed: undefined,
  });
}

export function markPerpsSnapshotLoadFailed(global: GlobalState, accountId: string): GlobalState {
  if (selectAccountState(global, accountId)?.perps?.isSnapshotLoadFailed) return global;

  return updateAccountPerps(global, accountId, { isSnapshotLoadFailed: true });
}

export function updatePerpsChart(
  global: GlobalState,
  assetId: string,
  period: ApiPriceHistoryPeriod,
  chart: PerpsChartState,
): GlobalState {
  const chartsByAssetId = {
    ...global.perps.chartsByAssetId,
    [assetId]: { ...global.perps.chartsByAssetId[assetId], [period]: chart },
  };

  const charts = Object.entries(chartsByAssetId).flatMap(([chartAssetId, byPeriod]) => (
    Object.entries(byPeriod).map(([chartPeriod, state]) => ({
      assetId: chartAssetId,
      period: chartPeriod as ApiPriceHistoryPeriod,
      fetchedAt: state?.fetchedAt ?? 0,
    }))
  ));

  if (charts.length > CHARTS_LIMIT) {
    charts.sort((a, b) => a.fetchedAt - b.fetchedAt);

    for (const stale of charts.slice(0, charts.length - CHARTS_LIMIT)) {
      if (stale.assetId === assetId && stale.period === period) continue;

      const byPeriod = { ...chartsByAssetId[stale.assetId] };
      delete byPeriod[stale.period];
      chartsByAssetId[stale.assetId] = byPeriod;
    }
  }

  return updatePerps(global, { chartsByAssetId });
}

/**
 * Merges a history page into the loaded history. A refresh of the first page keeps the older pages already loaded,
 * so the list does not shrink while it polls. Their cursor stays only while the refreshed page reaches them: after
 * more new fills than a page holds, the next page of the refresh loads the fills between them.
 */
export function mergePerpsHistory(
  page: ApiPerpsActivityHistory,
  current?: PerpsHistoryState,
  isNextPage?: boolean,
): PerpsHistoryState {
  const currentFills = current?.fills ?? [];
  const reachesLoadedPages = !current?.isRestored && hasCommonFill(currentFills, page.fills);

  return {
    fills: mergeFills(currentFills, page.fills),
    nextCursor: isNextPage || !reachesLoadedPages ? page.nextCursor : current!.nextCursor,
    fetchedAt: isNextPage ? current?.fetchedAt : Date.now(),
  };
}

function hasCommonFill(current: ApiPerpsFill[], next: ApiPerpsFill[]) {
  const keys = new Set(current.map(getPerpsFillKey));

  return next.some((fill) => keys.has(getPerpsFillKey(fill)));
}

function mergeFills(current: ApiPerpsFill[], next: ApiPerpsFill[]) {
  const byKey = new Map(current.map((fill) => [getPerpsFillKey(fill), fill]));
  for (const fill of next) {
    byKey.set(getPerpsFillKey(fill), fill);
  }

  return [...byKey.values()].sort((a, b) => b.time - a.time);
}

/** Puts the data of the last launch where the network has not brought fresher data yet */
export function restorePerpsReadCache(global: GlobalState, cache: PerpsReadCache): GlobalState {
  const chartsByAssetId = { ...global.perps.chartsByAssetId };
  for (const [assetId, byPeriod] of Object.entries(cache.chartsByAssetId ?? {})) {
    for (const [period, chart] of Object.entries(byPeriod)) {
      if (!chart?.points || chartsByAssetId[assetId]?.[period as ApiPriceHistoryPeriod]) continue;

      chartsByAssetId[assetId] = { ...chartsByAssetId[assetId], [period]: chart };
    }
  }

  global = updatePerps(global, { chartsByAssetId });

  for (const [accountId, { address, ...history }] of Object.entries(cache.historyByAccountId ?? {})) {
    if (global.accounts?.byId[accountId]?.byChain.arbitrum?.address !== address) continue;
    if (selectAccountState(global, accountId)?.perps?.history) continue;

    global = updateAccountPerps(global, accountId, { history: { ...history, isRestored: true } });
  }

  return global;
}

export function updatePerpsMarketDetail(
  global: GlobalState,
  accountId: string,
  assetId: string,
  partial: PerpsMarketDetailState,
): GlobalState {
  const marketDetailById = selectAccountState(global, accountId)?.perps?.marketDetailById;

  return updateAccountPerps(global, accountId, {
    marketDetailById: {
      ...marketDetailById,
      [assetId]: { ...marketDetailById?.[assetId], ...partial },
    },
  });
}

export function updatePerpsNavigation(global: GlobalState, navigation: PerpsNavigation): GlobalState {
  return updatePerps(global, { navigation });
}

/**
 * Opens the market or the position of `assetId`. Back from it returns to the section or the Wallet screen it was opened
 * from. The market and the position of one asset are two states of one screen, so a switch between them keeps the way
 * back.
 */
export function updatePerpsAssetNavigation(
  global: GlobalState,
  screen: 'market' | 'position',
  assetId: string,
): GlobalState {
  const { navigation } = global.perps;
  const isOtherStateOfScreen = (navigation.screen === 'market' || navigation.screen === 'position')
    && navigation.screen !== screen
    && navigation.assetId === assetId;

  if (isOtherStateOfScreen) {
    return updatePerpsNavigation(global, { ...navigation, screen });
  }

  if (selectIsWalletTabActive(global)) {
    return updatePerpsNavigation(global, { screen, assetId, isOpenedFromWallet: true });
  }

  return updatePerpsNavigation(global, {
    screen,
    assetId,
    ...(navigation.screen === 'section' && { sectionId: navigation.sectionId }),
  });
}

export function addPerpsReceipt(
  global: GlobalState,
  accountId: string,
  operationId: string,
  quote: ApiPerpsQuote,
): GlobalState {
  const perpsReceipts = selectAccountState(global, accountId)?.perpsReceipts;

  return updateAccountState(global, accountId, { perpsReceipts: { ...perpsReceipts, [operationId]: { quote } } });
}

export function updatePerpsReceipt(
  global: GlobalState,
  accountId: string,
  operationId: string,
  update: Partial<PerpsOperationReceipt>,
): GlobalState {
  const perpsReceipts = selectAccountState(global, accountId)?.perpsReceipts;
  const receipt = perpsReceipts?.[operationId];
  if (!receipt) return global;

  return updateAccountState(global, accountId, {
    perpsReceipts: { ...perpsReceipts, [operationId]: { ...receipt, ...update } },
  });
}

/** Drops the receipts of operations the account no longer keeps, since the journal forgets old resolved operations */
export function prunePerpsReceipts(global: GlobalState, accountId: string): GlobalState {
  const accountState = selectAccountState(global, accountId);
  const perpsReceipts = accountState?.perpsReceipts;
  if (!perpsReceipts) return global;

  const operationIds = Object.keys(perpsReceipts);
  const keptIds = operationIds.filter((id) => accountState.perpsOperations?.[id]);
  if (keptIds.length === operationIds.length) return global;

  return updateAccountState(global, accountId, { perpsReceipts: pick(perpsReceipts, keptIds) });
}

export function hidePerpsOperationBanner(global: GlobalState, operation: ApiPerpsOperation): GlobalState {
  const { hiddenOperationStates } = global.perps;
  if (hiddenOperationStates?.[operation.id] === operation.state) return global;

  return updatePerps(global, {
    hiddenOperationStates: { ...hiddenOperationStates, [operation.id]: operation.state },
  });
}

export function setPerpsOpenedActivity(global: GlobalState, openedActivity: PerpsOpenedActivity): GlobalState {
  return updatePerps(global, { openedActivity });
}

export function clearPerpsOpenedActivity(global: GlobalState): GlobalState {
  return global.perps.openedActivity ? updatePerps(global, { openedActivity: undefined }) : global;
}

export function setPerpsTrade(global: GlobalState, trade: PerpsTradeState): GlobalState {
  return updatePerps(global, { trade });
}

export function clearPerpsTrade(global: GlobalState): GlobalState {
  return global.perps.trade ? updatePerps(global, { trade: undefined }) : global;
}

/** Futures screens show the data of one account, so another account starts on the Futures home screen */
export function resetPerpsAccountScreens(global: GlobalState): GlobalState {
  const { navigation, trade, openedActivity } = global.perps;
  if (navigation.screen === 'home' && !trade && !openedActivity) return global;
  // The form that switches the wallet moves to it first, and the market under the form stays on screen
  if (trade && trade.accountId === global.currentAccountId) return global;

  return updatePerps(global, { navigation: { screen: 'home' }, trade: undefined, openedActivity: undefined });
}

export function updatePerpsTrade(global: GlobalState, update: Partial<PerpsTradeState>): GlobalState {
  const { trade } = global.perps;
  if (!trade) return global;

  const isErrorDetailsOutdated = 'error' in update && !('errorDetails' in update);

  return setPerpsTrade(global, { ...trade, ...update, ...(isErrorDetailsOutdated && { errorDetails: undefined }) });
}

export function updatePerpsAssets(
  global: GlobalState,
  assets: ApiPerpsGetAssetsResult,
  langCode: string | undefined,
  fetchedAt: number,
): GlobalState {
  const perpsAssets = {
    ...assets,
    byId: indexPerpsAssets(assets),
    langCode,
    fetchedAt,
  };

  if (areDeepEqual(global.perpsAssets, perpsAssets)) return global;

  return { ...global, perpsAssets };
}

export function updatePerpsAssetDetail(
  global: GlobalState,
  accountId: string,
  assetId: string,
  partial: PerpsAssetDetailState,
): GlobalState {
  const current = selectAccountState(global, accountId)?.perpsAssetDetailById;

  return updateAccountState(global, accountId, {
    perpsAssetDetailById: {
      ...current,
      [assetId]: {
        ...current?.[assetId],
        ...partial,
      },
    },
  });
}

export function updatePerpsAssetChart(
  global: GlobalState,
  assetId: string,
  partial: PriceHistoryPeriods,
): GlobalState {
  const byAssetId = global.perpsAssetChart?.byAssetId ?? {};

  return {
    ...global,
    perpsAssetChart: {
      byAssetId: {
        ...byAssetId,
        [assetId]: {
          ...byAssetId[assetId],
          ...partial,
        },
      },
    },
  };
}

function indexPerpsAssets(assets: ApiPerpsGetAssetsResult): Record<string, ApiPerpsListedAsset> {
  const byId: Record<string, ApiPerpsListedAsset> = {};

  for (const listed of Object.values(assets.assetsByChain)) {
    for (const asset of listed ?? []) {
      byId[asset.id] = asset;
    }
  }

  for (const section of assets.sections ?? []) {
    for (const asset of section.assets) {
      byId[asset.id] = asset;
    }
  }

  return byId;
}

export function updatePerpsBalanceDeposit(
  global: GlobalState,
  accountId: string,
  progress: PerpsBalanceDepositProgress,
): GlobalState {
  if (!global.accounts?.byId[accountId]) return global;
  return updateAccountState(global, accountId, { perpsBalanceDeposit: progress });
}

export function updatePerpsOperation(global: GlobalState, operation: ApiPerpsOperation): GlobalState {
  const { accountId } = operation;
  if (!global.accounts?.byId[accountId]) return global;

  const operations = {
    ...global.byAccountId[accountId]?.perpsOperations,
    [operation.id]: operation,
  };
  const resolved = Object.values(operations)
    .filter((value) => value.state === 'completed' || value.state === 'failed' || value.acknowledgedAt !== undefined)
    .sort((a, b) => b.createdAt - a.createdAt);
  for (const value of resolved.slice(20)) delete operations[value.id];

  return updateAccountState(global, accountId, { perpsOperations: operations });
}

function updatePerps(global: GlobalState, update: Partial<GlobalState['perps']>): GlobalState {
  return { ...global, perps: { ...global.perps, ...update } };
}
