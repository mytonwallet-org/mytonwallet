import type {
  ApiPerpsAccountPosition,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsOperationKind,
  ApiPriceHistoryPeriod,
} from '../../api/types';
import type { Account, GlobalState, PerpsAccountSnapshot, PerpsChartState, PerpsHistoryState } from '../types';

import { IS_PERPS_SUPPORTED } from '../../config';
import { MINUTE, SECOND } from '../../util/dateFormat';
import { buildCollectionByKey } from '../../util/iteratees';
import memoize from '../../util/memoize';
import { getIsPerpsAccountDisabled, PERPS_ONBOARDING_BANNER_ID } from '../helpers/perps';
import {
  selectAccountState,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentNetwork,
  selectIsCurrentAccountViewMode,
  selectIsWalletTabActive,
  selectNetworkAccounts,
} from './accounts';

const PERPS_OPERATION_PENDING = 'PerpsOperationPending';
const PERPS_SNAPSHOT_PENDING = '';
const PERPS_MULTICHAIN_WALLET_REQUIRED = 'PerpsRequiresMultichainWallet';
const PERPS_OWN_WALLET_REQUIRED = 'PerpsRequiresOwnWallet';
// The ages after which the iOS app shows Perps data as stale
const SNAPSHOT_MAX_AGE = 60 * SECOND;
const MARKET_MAX_AGE = 2 * MINUTE;
const HISTORY_MAX_AGE = 5 * MINUTE;
const CHART_MAX_AGE = 5 * MINUTE;

export function selectCanReadPerps(global: GlobalState) {
  return IS_PERPS_SUPPORTED
    && selectCurrentNetwork(global) === 'mainnet'
    && Boolean(selectCurrentAccount(global)?.byChain.arbitrum);
}

/** The text key that explains why the current account has no Futures, or `undefined` when it has them */
export function selectPerpsUnavailableReason(global: GlobalState) {
  if (selectCanReadPerps(global)) return undefined;

  if (!IS_PERPS_SUPPORTED || selectCurrentNetwork(global) !== 'mainnet') return 'PerpsUnsupportedAccount';

  // On mainnet only the Arbitrum address is missing. A viewed wallet is someone else's, so the text asks for the user's
  // own wallet, while the user's own wallet needs to be swapped for a multichain one.
  return selectIsCurrentAccountViewMode(global) ? PERPS_OWN_WALLET_REQUIRED : PERPS_MULTICHAIN_WALLET_REQUIRED;
}

/** The reason is fixed by switching to another wallet, so the screen explains it even to a viewed wallet */
export function getIsPerpsWalletSwitchReason(reason?: string) {
  return reason === PERPS_MULTICHAIN_WALLET_REQUIRED || reason === PERPS_OWN_WALLET_REQUIRED;
}

const selectHasOtherPerpsAccountMemoized = memoize((accounts?: Record<string, Account>, currentAccountId?: string) => (
  Object.entries(accounts ?? {}).some(([accountId, account]) => (
    accountId !== currentAccountId && !getIsPerpsAccountDisabled(account)
  ))
));

export function selectHasOtherPerpsAccount(global: GlobalState) {
  return selectHasOtherPerpsAccountMemoized(selectNetworkAccounts(global), selectCurrentAccountId(global));
}

/** The Wallet screen is on top, so its Open Positions block is visible */
export function selectIsPerpsWalletBlockVisible(global: GlobalState) {
  return selectCanReadPerps(global) && selectIsWalletTabActive(global);
}

export function selectCurrentAccountPerps(global: GlobalState) {
  return selectCurrentAccountState(global)?.perps;
}

const selectPerpsMarketAssetsByIdMemoized = memoize((assets: ApiPerpsMarketAsset[]) => {
  return buildCollectionByKey(assets, 'id');
});

export function selectPerpsMarketAssetsById(global: GlobalState) {
  const assets = global.perps.market?.assets;

  return assets && selectPerpsMarketAssetsByIdMemoized(assets);
}

const selectPerpsMarketAssetsByNameMemoized = memoize((assets: ApiPerpsMarketAsset[]) => {
  return buildCollectionByKey(assets, 'name');
});

/** Catalogue markets by their Hyperliquid wire name, which trades use as `coin` */
export function selectPerpsMarketAssetsByName(global: GlobalState) {
  const assets = global.perps.market?.assets;

  return assets && selectPerpsMarketAssetsByNameMemoized(assets);
}

export function selectPerpsMarketAsset(global: GlobalState, assetId: string): ApiPerpsMarketAsset | undefined {
  return selectPerpsMarketAssetsById(global)?.[assetId];
}

/** The description of the market. The catalogue may leave it out, and the market detail brings it then. */
export function selectPerpsAssetDescription(global: GlobalState, assetId: string) {
  return selectPerpsMarketAsset(global, assetId)?.description
    || selectCurrentAccountPerps(global)?.marketDetailById?.[assetId]?.asset?.description;
}

const selectPerpsPositionsByAssetIdMemoized = memoize((positions: ApiPerpsAccountPosition[]) => {
  return buildCollectionByKey(positions, 'assetId');
});

export function selectCurrentAccountPerpsPosition(
  global: GlobalState,
  assetId: string,
): ApiPerpsAccountPosition | undefined {
  const positions = selectCurrentAccountPerps(global)?.snapshot?.positions;

  return positions && selectPerpsPositionsByAssetIdMemoized(positions)[assetId];
}

export function selectAccountPerpsOperation(global: GlobalState, accountId: string, operationId: string) {
  return selectAccountState(global, accountId)?.perpsOperations?.[operationId];
}

export function selectCurrentAccountPerpsOperation(global: GlobalState, operationId: string) {
  return selectCurrentAccountState(global)?.perpsOperations?.[operationId];
}

/** An operation that is still running or whose outcome is unknown, which forbids the next order */
export function isPerpsOperationBlocking(operation: ApiPerpsOperation) {
  return operation.state !== 'completed'
    && operation.state !== 'failed'
    && !(operation.state === 'unknown' && operation.acknowledgedAt !== undefined);
}

/** Blocking operations, newest first. Many containers read them on every global change, so the list is built once. */
const selectBlockingOperationsMemoized = memoize((operations: Record<string, ApiPerpsOperation>) => {
  return Object.values(operations)
    .filter(isPerpsOperationBlocking)
    .sort((a, b) => b.createdAt - a.createdAt);
});

// A partly filled trade is not listed here, since it blocks the onboarding as an unfinished operation
const selectHasPerpsTradeMemoized = memoize((operations: Record<string, ApiPerpsOperation>) => {
  return Object.values(operations).some(({ kind, state }) => kind !== 'withdraw' && state === 'completed');
});

/**
 * The newest operation that blocks an order of `kind` on `assetId`. A filled close or reduce that waits for its
 * withdrawal still lets the user reduce or close a different market, as the SDK allows.
 */
export function selectPerpsBlockingOperation(
  global: GlobalState,
  assetId?: string,
  kind?: ApiPerpsOperationKind,
): ApiPerpsOperation | undefined {
  return selectBlockingOperations(global)?.find((operation) => {
    const isReleasedElsewhere = operation.state === 'partial'
      && operation.orderStatus === 'filled'
      && operation.orderId !== undefined
      && (operation.kind === 'close' || operation.kind === 'reduce')
      && assetId !== undefined
      && operation.assetId !== assetId
      && (kind === 'close' || kind === 'reduce');

    return !isReleasedElsewhere;
  });
}

/** The newest blocking operation whose banner the user did not hide in its current state */
export function selectPerpsBannerOperation(global: GlobalState): ApiPerpsOperation | undefined {
  const { hiddenOperationStates } = global.perps;

  return selectBlockingOperations(global)?.find(({ id, state }) => hiddenOperationStates?.[id] !== state);
}

/** A pending operation leaves the trade buttons enabled, so that a tap opens the status of that operation */
export function isPerpsTradeDisabledBy(reason?: string) {
  return reason !== undefined && reason !== PERPS_OPERATION_PENDING;
}

/**
 * The text key that explains why the market cannot be traded now, or `undefined` when it can. Until the first snapshot
 * tells whether the account can trade, the key is empty, so the buttons are disabled without a text.
 */
export function selectPerpsTradeBlockReason(
  global: GlobalState,
  assetId: string,
  kind?: ApiPerpsOperationKind,
): string | undefined {
  if (!selectCanTradePerps(global)) {
    const unavailableReason = selectPerpsUnavailableReason(global);
    if (unavailableReason) return unavailableReason;

    const accountPerps = selectCurrentAccountPerps(global);
    if (!accountPerps?.snapshot && !accountPerps?.isSnapshotLoadFailed) return PERPS_SNAPSHOT_PENDING;

    return accountPerps?.snapshot?.tradingAvailability?.reason ?? 'PerpsUnavailable';
  }

  const availability = selectPerpsMarketAsset(global, assetId)?.tradingAvailability;
  if (!availability?.isAvailable) return availability?.reason ?? 'PerpsUnavailable';

  if (selectPerpsBlockingOperation(global, assetId, kind)) return PERPS_OPERATION_PENDING;

  return undefined;
}

export function selectShouldShowPerpsOnboarding(global: GlobalState) {
  const snapshot = selectCurrentAccountPerps(global)?.snapshot;
  if (!snapshot || snapshot.unavailableDexs.length || snapshot.positions.length) return false;

  return selectIsPerpsOnboardingExpected(global);
}

/**
 * The account has never traded and the user has not closed the onboarding, so it shows unless the snapshot finds
 * a position. A trade of this session counts before the history shows it. A withdrawal from the balance is not a trade
 * and leaves the onboarding in place.
 */
export function selectIsPerpsOnboardingExpected(global: GlobalState) {
  if (selectCurrentAccountPerps(global)?.hasActivityHistory !== false) return false;
  if (selectCurrentAccountSettings(global)?.dismissedHomeBannerIds?.includes(PERPS_ONBOARDING_BANNER_ID)) return false;

  const operations = selectCurrentAccountState(global)?.perpsOperations;
  if (operations && selectHasPerpsTradeMemoized(operations)) return false;

  return !selectPerpsBlockingOperation(global);
}

/** Positions are fresh for a minute after a read of every book, as on iOS */
export function isPerpsSnapshotStale(snapshot?: PerpsAccountSnapshot) {
  return !snapshot || snapshot.unavailableDexs.length > 0 || !isFresh(SNAPSHOT_MAX_AGE, snapshot.timestamp);
}

export function selectIsPerpsMarketStale(global: GlobalState) {
  return !isFresh(MARKET_MAX_AGE, global.perps.market?.assetsFetchedAt);
}

export function isPerpsHistoryStale(history?: PerpsHistoryState) {
  return !isFresh(HISTORY_MAX_AGE, history?.fetchedAt);
}

export function isPerpsChartStale(chart?: PerpsChartState) {
  return !isFresh(CHART_MAX_AGE, chart?.fetchedAt);
}

function selectCanTradePerps(global: GlobalState) {
  return selectCanReadPerps(global)
    && selectCurrentAccountPerps(global)?.snapshot?.tradingAvailability?.isAvailable === true;
}

function selectBlockingOperations(global: GlobalState) {
  const operations = selectCurrentAccountState(global)?.perpsOperations;

  return operations && selectBlockingOperationsMemoized(operations);
}

export function selectPerpsListedAsset(global: GlobalState, assetId: string) {
  return global.perpsAssets?.byId[assetId];
}

export function selectPerpsAssetDetail(
  global: GlobalState,
  accountId: string | undefined,
  assetId: string | undefined,
) {
  if (!accountId || !assetId) return undefined;

  return global.byAccountId[accountId]?.perpsAssetDetailById?.[assetId];
}

export function selectPerpsAssetChart(
  global: GlobalState,
  assetId: string | undefined,
  period: ApiPriceHistoryPeriod,
) {
  if (!assetId) return undefined;

  return global.perpsAssetChart?.byAssetId[assetId]?.[period];
}

function isFresh(maxAge: number, fetchedAt?: number) {
  if (!fetchedAt) return false;

  const age = Date.now() - fetchedAt;

  return age >= 0 && age < maxAge;
}
