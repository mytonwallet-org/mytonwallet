/* eslint-disable no-null/no-null -- The public detail result uses null when no exact transaction is available. */
import type {
  ApiActivity, ApiBaseCurrency, ApiChain, ApiNft, ApiPortfolioHistoryParams,
  ApiPortfolioHistoryResponse, ApiPortfolioPnlChangeResponse, ApiPriceHistoryPeriod,
} from '../types';
import type {
  AgentApiChain,
  AgentAssetIdentityV2,
  AgentAssetSelector,
  AgentToolCall,
  AgentWalletAccountFilterV1,
  AgentWalletDataAggregateRowV2,
  AgentWalletDataCoverageV5,
  AgentWalletDataPolicySummaryV1,
  AgentWalletDataPositionRowV3,
  AgentWalletDataQueryArgsV5,
  AgentWalletDataQueryResultV5,
  AgentWalletDataSeriesPointV1,
  AgentWalletDataSeriesV1,
  AgentWalletDataTransactionRowV3,
  AgentWalletFilterSetV1,
  AgentWalletPortfolioAllocationV1,
  AgentWalletResolvedScopeV1,
  AgentWalletRiskModeV1,
  AgentWalletSourceOutcomeV1,
  AgentWalletTransactionAmountV1,
} from './protocol/types';
import type {
  AgentV2HostAccount,
  AgentV2HostAsset,
  AgentV2HostPosition,
  ApiUpdateAgentV2PortfolioHistory,
} from './types';
import type { AgentWalletScopeBinding } from './walletScopeStore';
import type { AgentV2WalletSession, AgentV2WalletSessionSnapshot } from './walletSession';

import { raceWithAbortSignal, throwIfAborted } from '../../util/abortSignal';
import { getActivityChains, parseTxId, STAKING_TRANSACTION_TYPES } from '../../util/activities';
import { toDecimal } from '../../util/decimals';
import { buildPortfolioHistoryParams, getPortfolioHistorySlot } from '../../util/portfolio/timeRange';
import { shortenAddress } from '../../util/shortenAddress';
import { findNativeToken, getChainBySlug } from '../../util/tokens';
import { matchesPortfolioAccountFilter } from './walletQueryAccountFilter';
import {
  isRetryableWalletSourceError,
  isWalletSourceError,
  WalletQueryProjectionError,
} from './walletQueryErrors';
import { canonicalTransactionSourceRowId, canonicalWalletQueryRowId } from './walletQueryRowId';
import { transactionHashesEqual } from './walletQueryTransactionHash';

const MAX_ACTIVITY_ACCOUNTS = 10;
const MAX_ACTIVITY_SCAN_PER_ACCOUNT = 500;
const MAX_ACTIVITY_BATCH = 50;
const MAX_ACTIVITY_CONCURRENCY = 4;
const MAX_HISTORY_ACCOUNTS = 5;
const MAX_SERIES = 5;
const MAX_SERIES_POINTS = 64;
const SOURCE_RETRY_ATTEMPTS = 2;
const RANGE_MAP = {
  '1d': '1D',
  '7d': '7D',
  '1m': '1M',
  '3m': '3M',
  '1y': '1Y',
  all: 'ALL',
} as const satisfies Record<string, ApiPriceHistoryPeriod>;

export type FetchPastActivities = (
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
  options?: { signal?: AbortSignal; shouldThrowOnError?: boolean },
) => Promise<{ activities: ApiActivity[]; hasMore: boolean } | undefined>;

export type FetchPortfolioHistory = (
  wallets: string[],
  baseCurrency: ApiBaseCurrency,
  params?: ApiPortfolioHistoryParams,
  options?: { signal?: AbortSignal; timeoutMs?: number },
) => Promise<ApiPortfolioHistoryResponse>;

export type FetchPortfolioPnlChange = (
  wallets: string[],
  baseCurrency: ApiBaseCurrency,
  params?: ApiPortfolioHistoryParams,
  options?: { signal?: AbortSignal; timeoutMs?: number },
) => Promise<ApiPortfolioPnlChangeResponse>;

export type RefreshWalletHoldings = (
  accounts: AgentV2HostAccount[],
  signal: AbortSignal,
) => Promise<Map<string, {
  byChain: Partial<Record<AgentApiChain, Record<string, bigint>>>;
  failedChains: AgentApiChain[];
}>>;

export interface WalletQueryMaterializationScope {
  accountIds: string[];
  accountScope: 'current' | 'selected' | 'explicitAll';
  accountsRequested: number;
}

export interface WalletQueryMaterializationDependencies {
  session: AgentV2WalletSession;
  authorityBinding: Omit<AgentWalletScopeBinding, 'queryDigest'>;
  args: AgentWalletDataQueryArgsV5;
  call: AgentToolCall;
  completedAt: string;
  signal: AbortSignal;
  scope?: WalletQueryMaterializationScope;
  resolvedScope?: AgentWalletResolvedScopeV1;
  filterDigest?: string;
  fetchPastActivities?: FetchPastActivities;
  fetchActivityDetails?: (accountId: string, activity: ApiActivity, signal?: AbortSignal) => Promise<ApiActivity>;
  fetchPortfolioHistory?: FetchPortfolioHistory;
  fetchPortfolioPnlChange?: FetchPortfolioPnlChange;
  getTokenBySlug?: (slug: string) => AgentV2HostAsset | undefined;
  refreshWalletHoldings?: RefreshWalletHoldings;
  onPortfolioHistory?: (update: Omit<ApiUpdateAgentV2PortfolioHistory, 'type'>) => void;
}

interface PositionCandidate {
  row: AgentWalletDataPositionRowV3;
  riskVerdict?: 'spam';
  visibility: 'visible' | 'hidden';
}

interface HistoryOutcome {
  account: AgentV2HostAccount;
  response?: ApiPortfolioHistoryResponse;
  source: 'cache' | 'network';
  failed: boolean;
}

interface HistorySeriesProjection {
  series: AgentWalletDataSeriesV1[];
  rowsOmitted: number;
}

interface TransactionScanOutcome {
  account: AgentV2HostAccount;
  activities: ApiActivity[];
  attempts: number;
  failed: boolean;
  hasMore: boolean;
}

export async function materializeWalletQuery(
  dependencies: WalletQueryMaterializationDependencies,
): Promise<Extract<AgentWalletDataQueryResultV5, { status: 'resolved' }>> {
  throwIfAborted(dependencies.signal);
  const { args } = dependencies;
  if (args.operation === 'assets.search') {
    return buildAssetSearch(dependencies, args);
  }

  const snapshot = dependencies.session.snapshot();
  const resolvedScope = dependencies.resolvedScope;
  const scope = dependencies.scope;
  if (!resolvedScope || !scope) throw invalid('The wallet query scope is missing.');
  const allowInactive = args.operation === 'account.inventory' && !args.includePortfolioTotals;
  let accounts = resolveAccounts(
    snapshot,
    scope,
    dependencies.call,
    allowInactive,
    args.operation === 'portfolio.aggregate' ? args.accountFilter : undefined,
  );
  if (args.operation === 'positions.list'
    || args.operation === 'portfolio.aggregate'
    || (args.operation === 'account.inventory' && args.includePortfolioTotals)) {
    accounts = await refreshPositions(dependencies, snapshot, accounts);
  }

  switch (args.operation) {
    case 'account.inventory':
      return buildAccounts(dependencies, snapshot, accounts, resolvedScope, args);
    case 'positions.list':
      return buildPositionList(dependencies, snapshot, accounts, resolvedScope, args);
    case 'portfolio.aggregate':
      return buildPortfolio(dependencies, snapshot, accounts, resolvedScope, args);
    case 'transactions.list':
      return buildTransactionList(dependencies, snapshot, accounts, resolvedScope, args);
    case 'transactions.detail':
      return buildTransactionDetail(dependencies, snapshot, accounts, resolvedScope, args);
    case 'contacts.list':
      return buildContacts(dependencies, snapshot, accounts, resolvedScope, args);
    case 'value.series':
      return buildValueSeries(dependencies, snapshot, accounts, resolvedScope, args);
  }
}

function buildAssetSearch(
  dependencies: WalletQueryMaterializationDependencies,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'assets.search' }>,
): Extract<AgentWalletDataQueryResultV5, { operation: 'assets.search' }> {
  const host = dependencies.session.snapshot().host;
  if (!host) throw unavailable('Wallet asset data is unavailable.');
  const query = normalizeAssetLookup(args.query);
  if (!query) throw invalid('The asset search query is invalid.');
  const chains = args.chains.length ? new Set(args.chains) : undefined;
  const heldAssets = host.accounts.filter(({ state }) => state === 'active').flatMap((account) => [
    ...account.holdings.map(({ asset }) => asset),
    ...(account.positions ?? []).flatMap(({ asset }) => asset ? [asset] : []),
  ]);
  const assets = uniqueAssets([...heldAssets, ...(host.assetCatalog ?? [])])
    .filter(({ chain }) => !chains || chains.has(chain));
  const matches = assets.flatMap((asset) => {
    const match = matchAssetSearch(asset, query);
    return match ? [{ asset: projectAsset(asset), ...match }] : [];
  }).sort((left, right) => (
    matchFieldRank(left.matchedOn) - matchFieldRank(right.matchedOn)
    || assetKey(left.asset).localeCompare(assetKey(right.asset))
  ));
  const selected = matches.slice(0, matches.length > 1 ? Math.max(2, args.pageSize) : args.pageSize);
  const resolution = selected.length === 0 ? 'no_match' : selected.length === 1 ? 'unique' : 'ambiguous';
  const omitted = Math.max(0, matches.length - selected.length);
  const coverage = makeCoverage({
    domain: 'assets',
    accountsRequested: 0,
    accountsIncluded: 0,
    rowsOmitted: omitted,
    limitations: omitted ? ['row_limit'] : [],
    rowCount: selected.length,
  });
  return {
    schemaVersion: 5,
    operation: 'assets.search',
    status: 'resolved',
    generatedAt: dependencies.completedAt,
    freshness: freshness(dependencies.completedAt, 'cache', false),
    coverage,
    assets: selected,
    resolution,
  };
}

function buildAccounts(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'account.inventory' }>,
): Extract<AgentWalletDataQueryResultV5, { operation: 'account.inventory' }> {
  const requestedChains = args.chains.length ? new Set(args.chains) : undefined;
  const rows = accounts.flatMap((account) => {
    const chains = [...new Set(account.chains.filter((chain) => !requestedChains || requestedChains.has(chain)))];
    if (!chains.length && requestedChains) return [];
    const publicAddresses = args.includePublicAddressReason && account.state === 'active'
      ? chains.flatMap((chain) => {
        const address = account.addresses[chain];
        return address && isBoundedText(address, 256) ? [{
          chain,
          address,
          disclosureReason: args.includePublicAddressReason!,
        }] : [];
      }).slice(0, 16)
      : undefined;
    const portfolio = args.includePortfolioTotals
      ? buildAccountPortfolioTotal(dependencies.session, snapshot, account, args.chains)
      : undefined;
    return [{
      rowId: canonicalWalletQueryRowId('account', requireAccountRef(snapshot, account)),
      kind: 'account' as const,
      accountRef: requireAccountRef(snapshot, account),
      accountLabel: safeWalletQueryAccountLabel(account),
      accountType: account.accountType,
      isCurrent: account.accountId === snapshot.host?.activeAccountId,
      state: account.state,
      isViewOnly: account.isViewOnly,
      chains,
      ...(portfolio ? {
        portfolioTotalStatus: portfolio.status,
        ...(portfolio.total ? { portfolioTotal: portfolio.total } : {}),
      } : {}),
      ...(publicAddresses?.length ? { publicAddresses } : {}),
    }];
  }).slice(0, 100);
  const omitted = 0;
  const unavailableCount = rows.filter(({ portfolioTotalStatus }) => (
    portfolioTotalStatus === 'unavailable'
  )).length;
  const staleCount = accounts.filter(({ domainStates }) => domainStates?.positions?.state === 'stale').length;
  const unpricedCount = rows.reduce((sum, row) => sum + (row.portfolioTotal?.unpricedCount ?? 0), 0);
  const limitations = args.includePortfolioTotals ? uniqueLimitations([
    ...(unavailableCount ? ['source_unavailable' as const] : []),
    ...(staleCount ? ['stale_data' as const] : []),
    ...(unpricedCount ? ['unpriced_positions' as const] : []),
  ]) : [];
  const coverage = makeCoverage({
    domain: 'accounts',
    accountsRequested: requestedAccountCount(dependencies, accounts),
    accountsIncluded: args.includePortfolioTotals ? accounts.length - unavailableCount : accounts.length,
    rowsOmitted: omitted,
    limitations,
    rowCount: rows.length,
  });
  if (args.includePortfolioTotals && rows.length && coverage.status === 'unavailable') {
    coverage.status = 'partial';
  }
  return {
    ...resolvedBase(dependencies, resolvedScope, coverage),
    operation: 'account.inventory',
    accounts: rows,
  };
}

function buildAccountPortfolioTotal(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  chains: AgentApiChain[],
) {
  const sourceState = account.domainStates?.positions?.state ?? 'notLoaded';
  if (sourceState === 'notLoaded' || sourceState === 'unavailable') {
    return { status: 'unavailable' as const };
  }
  const built = collectPositions(session, snapshot, [account], {
    assetSelectors: [],
    chains,
    includeZero: false,
    positionKinds: ['fungible', 'nft', 'staking', 'vesting', 'vault'],
    riskMode: 'exclude',
    visibilityMode: 'all',
  });
  const valued = built.rows.filter(({ valuationStatus }) => valuationStatus === 'valued');
  const unpricedCount = built.rows.length - valued.length + built.invalidRows;
  const value = valued.reduce((sum, row) => sum.plus(row.fiatValue!), Decimal.zero()).toString();
  return {
    status: sourceState === 'stale' || unpricedCount ? 'partial' as const : 'complete' as const,
    total: { value, baseCurrency: snapshot.host!.baseCurrency, unpricedCount },
  };
}

function buildPositionList(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'positions.list' }>,
): Extract<AgentWalletDataQueryResultV5, { operation: 'positions.list' }> {
  const built = collectPositions(dependencies.session, snapshot, accounts, args);
  const selected = sortPositions(built.rows, args.sort).slice(0, args.pageSize);
  const omitted = Math.max(0, built.rows.length - selected.length) + built.invalidRows;
  const limitations = uniqueLimitations([
    ...(omitted ? ['row_limit' as const] : []),
    ...(selected.some(({ valuationStatus }) => valuationStatus === 'unpriced')
      ? ['unpriced_positions' as const]
      : []),
    ...positionStateLimitations(accounts),
  ]);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'positions',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: availablePositionAccountCount(accounts),
      rowsOmitted: omitted,
      limitations,
      rowCount: selected.length,
    })),
    operation: 'positions.list',
    policySummary: built.policySummary,
    positions: selected,
  };
}

async function buildPortfolio(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'portfolio.aggregate' }>,
): Promise<Extract<AgentWalletDataQueryResultV5, { operation: 'portfolio.aggregate' }>> {
  const built = collectPositions(dependencies.session, snapshot, accounts, {
    ...args,
    assetSelectors: [],
    positionKinds: ['fungible', 'nft', 'staking', 'vesting', 'vault'],
    includeZero: false,
  });
  const sorted = sortPositions(built.rows, 'value_desc');
  const positions = sorted.slice(0, 100);
  const valued = sorted.filter((row) => row.valuationStatus === 'valued');
  const totalValue = valued.reduce((sum, row) => sum.plus(row.fiatValue!), Decimal.zero());
  const unpricedCount = sorted.filter(({ valuationStatus }) => valuationStatus === 'unpriced').length;
  const allocationRows = buildAllocations(valued, totalValue, snapshot.host!.baseCurrency);
  const allocations = allocationRows.slice(0, 100);
  const aggregateRows = args.groupBy.flatMap((groupBy) => (
    aggregatePositions(sorted, groupBy, snapshot.host!.baseCurrency)
  ));
  const aggregates = aggregateRows.slice(0, 100);
  const historyIsUnscoped = args.chains.length > 0;
  const [history, rangePnl] = historyIsUnscoped
    ? [[] as HistoryOutcome[], undefined]
    : await Promise.all([
      loadHistory(dependencies, snapshot, accounts, args.range),
      loadRangePnl(dependencies, snapshot, accounts, args.range),
    ]);
  const historyProjection = buildHistorySeries(
    snapshot, history, 'portfolio_value', [], [], MAX_SERIES_POINTS,
  );
  const series = historyProjection.series;
  const rowLimitOmitted = Math.max(0, sorted.length - positions.length)
    + Math.max(0, allocationRows.length - allocations.length)
    + Math.max(0, aggregateRows.length - aggregates.length)
    + historyProjection.rowsOmitted
    + built.invalidRows;
  const historyScopeOmitted = historyIsUnscoped ? accounts.length : 0;
  const historyLimitOmitted = historyIsUnscoped ? 0 : Math.max(0, accounts.length - MAX_HISTORY_ACCOUNTS);
  const omitted = rowLimitOmitted + historyScopeOmitted + historyLimitOmitted;
  const historyFailures = history.filter(({ failed }) => failed).length;
  const limitations = uniqueLimitations([
    ...(rowLimitOmitted ? ['row_limit' as const] : []),
    ...(unpricedCount ? ['unpriced_positions' as const] : []),
    ...(historyFailures || historyIsUnscoped ? ['source_partial' as const] : []),
    ...(accounts.length > MAX_HISTORY_ACCOUNTS ? ['history_limit' as const] : []),
    ...positionStateLimitations(accounts),
  ]);
  const source = history.some(({ source }) => source === 'network')
    ? history.some(({ source }) => source === 'cache') ? 'mixed' : 'network'
    : 'cache';
  const coverage = makeCoverage({
    domain: 'portfolio',
    accountsRequested: requestedAccountCount(dependencies, accounts),
    accountsIncluded: historyIsUnscoped
      ? availablePositionAccountCount(accounts)
      : Math.min(availablePositionAccountCount(accounts), history.length - historyFailures),
    rowsOmitted: omitted,
    limitations,
    rowCount: positions.length + allocations.length + aggregates.length + series.length,
  });
  return {
    ...resolvedBase(dependencies, resolvedScope, coverage, source),
    operation: 'portfolio.aggregate',
    policySummary: built.policySummary,
    total: {
      value: totalValue.toString(),
      baseCurrency: snapshot.host!.baseCurrency,
      unpricedCount,
    },
    ...(rangePnl ? { rangePnl } : {}),
    allocations,
    positions,
    aggregates,
    series,
  };
}

async function buildTransactionList(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'transactions.list' }>,
): Promise<Extract<AgentWalletDataQueryResultV5, { operation: 'transactions.list' }>> {
  if (!dependencies.fetchPastActivities || !dependencies.filterDigest) {
    throw unavailable('Wallet transactions are unavailable.');
  }
  const selectedAccounts = accounts.slice(0, MAX_ACTIVITY_ACCOUNTS);
  const scans = await mapWithConcurrency(selectedAccounts, MAX_ACTIVITY_CONCURRENCY, (account) => (
    scanTransactionAccount(dependencies, account, transactionTokenSlug(args.filters))
  ));
  const candidates = scans.flatMap(({ account, activities }) => activities.flatMap((activity) => {
    if (activity.shouldHide) return [];
    const row = projectTransaction(dependencies, snapshot, account, activity);
    return (!args.chains.length || args.chains.includes(row.chain))
      && matchesTransactionFilters(row, args.filters) && matchesRisk(row.riskVerdict, args.riskMode)
      ? [row]
      : [];
  })).sort(compareTransactions);
  const unique = dedupeRows(candidates);
  const transactions = unique.slice(0, args.pageSize);
  const sourceOmitted = scans.reduce((sum, scan) => sum + (scan.hasMore ? 1 : 0), 0);
  const omitted = Math.max(0, unique.length - transactions.length);
  const failed = scans.filter(({ failed }) => failed).length;
  const limitations = uniqueLimitations([
    ...(omitted ? ['row_limit' as const] : []),
    ...(sourceOmitted || accounts.length > MAX_ACTIVITY_ACCOUNTS ? ['history_limit' as const] : []),
    ...(failed ? ['source_partial' as const] : []),
  ]);
  const policyAccuracy = sourceOmitted || failed ? 'lower_bound' : 'exact';
  const spamCount = scans.reduce((sum, scan) => sum + scan.activities.filter(({ isScam }) => isScam).length, 0);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'transactions',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: scans.filter(({ failed: didFail }) => !didFail).length,
      rowsOmitted: omitted,
      limitations,
      rowCount: transactions.length,
      attempts: Math.min(SOURCE_RETRY_ATTEMPTS, Math.max(1, ...scans.map(({ attempts }) => attempts))),
    }), 'network'),
    operation: 'transactions.list',
    policySummary: {
      riskMode: args.riskMode,
      spamMatches: { count: spamCount, accuracy: policyAccuracy },
      hiddenMatches: { count: 0, accuracy: policyAccuracy },
    },
    appliedFilterDigest: dependencies.filterDigest,
    transactions,
  };
}

async function buildTransactionDetail(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'transactions.detail' }>,
): Promise<Extract<AgentWalletDataQueryResultV5, { operation: 'transactions.detail' }>> {
  if (!dependencies.fetchPastActivities) throw unavailable('Wallet transactions are unavailable.');
  const selectedAccounts = accounts.slice(0, MAX_ACTIVITY_ACCOUNTS);
  const scans = await mapWithConcurrency(selectedAccounts, MAX_ACTIVITY_CONCURRENCY, (account) => (
    scanTransactionAccount(dependencies, account, undefined, args.hash)
  ));
  const match = scans.flatMap(({ account, activities }) => activities.map((activity) => ({ account, activity })))
    .find(({ activity }) => activityHasTransactionHash(activity, args.hash));
  let transaction: AgentWalletDataTransactionRowV3 | null = null;
  let detailFailed = false;
  if (match) {
    let activity: ApiActivity | undefined = match.activity;
    if (dependencies.fetchActivityDetails) {
      try {
        const enriched = await raceWithAbortSignal(
          () => dependencies.fetchActivityDetails!(match.account.accountId, match.activity, dependencies.signal),
          dependencies.signal,
        );
        await assertCurrentAuthority(dependencies);
        if (activityHasTransactionHash(enriched, args.hash)) {
          activity = enriched;
        } else {
          activity = undefined;
          detailFailed = true;
        }
      } catch (error) {
        if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
        if (error instanceof WalletQueryProjectionError) throw error;
        if (!isRetryableWalletSourceError(error)) throw error;
        await assertCurrentAuthority(dependencies);
        activity = undefined;
        detailFailed = true;
      }
    }
    if (activity) transaction = projectTransaction(dependencies, snapshot, match.account, activity);
  }
  const failed = scans.filter(({ failed }) => failed).length;
  const incomplete = scans.some(({ hasMore }) => hasMore) && !match;
  const limitations = uniqueLimitations([
    ...(failed || detailFailed ? ['source_partial' as const] : []),
    ...(incomplete || accounts.length > MAX_ACTIVITY_ACCOUNTS ? ['history_limit' as const] : []),
  ]);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'transactions',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: scans.filter(({ failed: didFail }) => !didFail).length,
      rowsOmitted: 0,
      limitations,
      rowCount: transaction ? 1 : 0,
      attempts: Math.min(SOURCE_RETRY_ATTEMPTS, Math.max(1, ...scans.map(({ attempts }) => attempts))),
    }), 'network'),
    operation: 'transactions.detail',
    transaction,
  };
}

function buildContacts(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'contacts.list' }>,
): Extract<AgentWalletDataQueryResultV5, { operation: 'contacts.list' }> {
  const query = args.query ? normalizeSearch(args.query) : undefined;
  let missingBindings = 0;
  const savedAddressRows = accounts.flatMap((account) => (account.savedAddresses ?? []).flatMap((contact) => {
    if (args.chains.length && !args.chains.includes(contact.chain)) return [];
    if (query && !normalizeSearch(`${contact.name} ${contact.address}`).includes(query)) return [];
    const refs = dependencies.session.resolveSavedAddressRefs(account.accountId, contact.id);
    if (!refs) {
      missingBindings += 1;
      return [];
    }
    return [{
      rowId: canonicalWalletQueryRowId(
        'contact', `${requireAccountRef(snapshot, account)}\0${contact.id}`,
      ),
      kind: 'contact' as const,
      contactRef: refs.contactRef,
      addressRef: refs.addressRef,
      name: safeWalletQueryIdentifierDisplay(contact.name, contact.address, 160),
      chain: contact.chain,
      addressDisplay: maskIdentifier(contact.address),
    }];
  }));
  const scopedAccountIds = new Set(accounts.map(({ accountId }) => accountId));
  const ownWalletRows = (snapshot.host?.accounts ?? []).flatMap((account) => {
    if (scopedAccountIds.has(account.accountId) || account.state === 'deleted') return [];
    const name = safeWalletQueryAccountLabel(account);
    const chains = args.chains.length ? args.chains : account.chains;
    return [...new Set(chains)].flatMap((chain) => {
      const address = account.addresses[chain];
      if (!address || (query && !normalizeSearch(`${name} ${address}`).includes(query))) return [];
      const refs = dependencies.session.resolveWalletAddressRefs(account.accountId, chain);
      if (!refs) {
        missingBindings += 1;
        return [];
      }
      return [{
        rowId: canonicalWalletQueryRowId(
          'contact', `${requireAccountRef(snapshot, account)}\0own-wallet\0${chain}`,
        ),
        kind: 'contact' as const,
        contactRef: refs.contactRef,
        addressRef: refs.addressRef,
        name,
        chain,
        addressDisplay: maskIdentifier(address),
      }];
    });
  });
  const rows = [...savedAddressRows, ...ownWalletRows];
  const contacts = rows.slice(0, args.pageSize);
  const omitted = Math.max(0, rows.length - contacts.length) + missingBindings;
  const missingSources = accounts.filter(({ domainStates }) => (
    domainStates?.contacts?.state === 'notLoaded' || domainStates?.contacts?.state === 'unavailable'
  )).length;
  const limitations = uniqueLimitations([
    ...(rows.length > contacts.length ? ['row_limit' as const] : []),
    ...(missingBindings || missingSources ? ['source_partial' as const] : []),
  ]);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'contacts',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: Math.max(0, accounts.length - missingSources),
      rowsOmitted: omitted,
      limitations,
      rowCount: contacts.length,
    })),
    operation: 'contacts.list',
    contacts,
  };
}

async function buildValueSeries(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgsV5, { operation: 'value.series' }>,
): Promise<Extract<AgentWalletDataQueryResultV5, { operation: 'value.series' }>> {
  const historyIsUnscoped = args.metric === 'portfolio_value' && args.chains.length > 0;
  const history = historyIsUnscoped ? [] : await loadHistory(dependencies, snapshot, accounts, args.range);
  const historyProjection = buildHistorySeries(
    snapshot,
    history,
    args.metric,
    args.assetSelectors,
    args.chains,
    Math.min(args.maxPoints, MAX_SERIES_POINTS),
  );
  const series = historyProjection.series;
  const failed = history.filter(({ failed: didFail }) => didFail).length;
  const historyScopeOmitted = historyIsUnscoped ? accounts.length : 0;
  const historyLimitOmitted = historyIsUnscoped ? 0 : Math.max(0, accounts.length - MAX_HISTORY_ACCOUNTS);
  const omitted = historyProjection.rowsOmitted + historyScopeOmitted + historyLimitOmitted;
  const limitations = uniqueLimitations([
    ...(historyProjection.rowsOmitted ? ['row_limit' as const] : []),
    ...(failed || historyIsUnscoped ? ['source_partial' as const] : []),
    ...(accounts.length > MAX_HISTORY_ACCOUNTS ? ['history_limit' as const] : []),
  ]);
  const source = history.some(({ source: itemSource }) => itemSource === 'network')
    ? history.some(({ source: itemSource }) => itemSource === 'cache') ? 'mixed' : 'network'
    : 'cache';
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'value_series',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: historyIsUnscoped ? 0 : history.length - failed,
      rowsOmitted: omitted,
      limitations,
      rowCount: series.length,
    }), source),
    operation: 'value.series',
    series,
  };
}

function collectPositions(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  args: Pick<
    Extract<AgentWalletDataQueryArgsV5, { operation: 'positions.list' }>,
    'assetSelectors' | 'chains' | 'includeZero' | 'positionKinds' | 'riskMode' | 'visibilityMode'
  >,
) {
  const requestedKinds = new Set(args.positionKinds);
  const candidates: PositionCandidate[] = [];
  let invalidRows = 0;
  for (const account of accounts) {
    const accountRef = requireAccountRef(snapshot, account);
    if (requestedKinds.has('fungible')) {
      for (const holding of account.holdings) {
        if (!matchesAsset(holding.asset, args.chains, args.assetSelectors)) continue;
        if (!isCanonicalDecimal(holding.balance) || (!args.includeZero && isZeroDecimal(holding.balance))) continue;
        const valued = holding.valuationStatus === 'valued' && isCanonicalDecimal(holding.fiatValue);
        const quantity = canonicalDecimal(holding.balance);
        const availableQuantity = isCanonicalDecimal(holding.availableBalance)
          ? canonicalDecimal(holding.availableBalance)
          : undefined;
        candidates.push({
          riskVerdict: holding.riskVerdict,
          visibility: holding.visibility ?? 'visible',
          row: {
            rowId: canonicalWalletQueryRowId(
              'position', `${accountRef}\0fungible\0${assetKey(holding.asset)}`,
            ),
            kind: 'position',
            accountRef,
            accountLabel: safeWalletQueryAccountLabel(account),
            ...(holding.riskVerdict ? {
              assetRef: session.getAssetRef(account.accountId, holding.asset.slug, holding.asset.chain),
            } : {}),
            positionKind: 'fungible',
            chain: holding.asset.chain,
            label: safeWalletQueryAssetSymbol(holding.asset, 160),
            asset: projectAsset(holding.asset),
            quantity,
            decimals: holding.asset.decimals,
            ...(availableQuantity !== undefined ? { availableQuantity } : {}),
            valuationStatus: valued ? 'valued' : 'unpriced',
            ...(valued ? {
              fiatValue: canonicalDecimal(holding.fiatValue!),
              baseCurrency: snapshot.host!.baseCurrency,
            } : {}),
            ...(holding.riskVerdict ? { riskVerdict: holding.riskVerdict } : {}),
          },
        });
      }
    }
    for (const position of account.positions ?? []) {
      if (!requestedKinds.has(position.kind) || !matchesPosition(position, args.chains, args.assetSelectors)) continue;
      const row = projectExtraPosition(session, snapshot, account, accountRef, position);
      if (!row || (!args.includeZero && isZeroDecimal(row.quantity))) {
        const visibility = position.visibility ?? 'visible';
        invalidRows += row || !matchesRisk(position.riskVerdict, args.riskMode)
          || (args.visibilityMode !== 'all' && args.visibilityMode !== visibility) ? 0 : 1;
        continue;
      }
      candidates.push({
        row,
        riskVerdict: position.riskVerdict,
        visibility: position.visibility ?? 'visible',
      });
    }
  }
  const spamMatches = candidates.filter(({ riskVerdict }) => riskVerdict === 'spam').length;
  const hiddenMatches = candidates.filter(({ visibility }) => visibility === 'hidden').length;
  const rows = candidates.filter(({ riskVerdict, visibility }) => (
    matchesRisk(riskVerdict, args.riskMode)
    && (args.visibilityMode === 'all' || args.visibilityMode === visibility)
  )).map(({ row }) => row);
  const accuracy = positionStateLimitations(accounts).length ? 'lower_bound' : 'exact';
  const policySummary: AgentWalletDataPolicySummaryV1 = {
    riskMode: args.riskMode,
    visibilityMode: args.visibilityMode,
    spamMatches: { count: spamMatches, accuracy },
    hiddenMatches: { count: hiddenMatches, accuracy },
  };
  return { rows, invalidRows, policySummary };
}

function projectExtraPosition(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  accountRef: string,
  position: AgentV2HostPosition,
): AgentWalletDataPositionRowV3 | undefined {
  const asset = position.asset ?? fallbackPositionAsset(snapshot, account, position);
  const quantity = position.quantity && isCanonicalDecimal(position.quantity)
    ? canonicalDecimal(position.quantity)
    : position.kind === 'nft' ? '1' : undefined;
  if (!asset || quantity === undefined) return undefined;
  const valued = position.valuationStatus === 'valued' && isCanonicalDecimal(position.fiatValue);
  const status = canonicalPositionStatus(position.status);
  return {
    rowId: canonicalWalletQueryRowId('position', `${accountRef}\0${position.id}`),
    kind: 'position',
    accountRef,
    accountLabel: safeWalletQueryAccountLabel(account),
    ...(position.riskVerdict ? {
      assetRef: session.getAssetRef(account.accountId, asset.slug, asset.chain),
    } : {}),
    positionKind: position.kind,
    chain: position.chain,
    label: safeHumanDisplay(
      position.label,
      'Position',
      160,
      position.asset?.tokenAddress ? [position.asset.tokenAddress] : [],
    ),
    asset: projectAsset(asset),
    quantity,
    decimals: asset.decimals,
    valuationStatus: valued ? 'valued' : position.valuationStatus,
    ...(valued ? { fiatValue: canonicalDecimal(position.fiatValue!), baseCurrency: snapshot.host!.baseCurrency } : {}),
    ...(status ? { status } : {}),
    ...(position.apy && isSignedDecimal(position.apy) ? { apy: canonicalSignedDecimal(position.apy) } : {}),
    ...(position.rewards && isCanonicalDecimal(position.rewards)
      ? { rewards: canonicalDecimal(position.rewards) }
      : {}),
    ...(position.collection ? {
      collection: safeHumanDisplay(position.collection, 'Collection', 160),
    } : {}),
    ...(position.isOnSale !== undefined ? { isOnSale: position.isOnSale } : {}),
    ...(position.riskVerdict ? { riskVerdict: position.riskVerdict } : {}),
  };
}

function fallbackPositionAsset(
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  position: AgentV2HostPosition,
): AgentV2HostAsset | undefined {
  if (position.kind !== 'nft') {
    const native = findNativeToken(position.chain as ApiChain);
    const held = native && account.holdings.find(({ asset }) => asset.slug === native.slug)?.asset;
    const catalog = native && snapshot.host?.assetCatalog?.find(({ slug }) => slug === native.slug);
    if (held || catalog) return held ?? catalog;
  }
  if (position.kind !== 'nft') return undefined;
  return {
    slug: position.id.slice(0, 128),
    chain: position.chain,
    symbol: 'NFT',
    name: safeHumanDisplay(position.label, 'Asset', 160),
    decimals: 0,
  };
}

async function refreshPositions(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
) {
  const stale = accounts.filter(({ domainStates }) => domainStates?.positions?.state !== 'fresh');
  if (!stale.length || !dependencies.refreshWalletHoldings) return accounts;
  let refreshed: Awaited<ReturnType<RefreshWalletHoldings>>;
  try {
    refreshed = await raceWithAbortSignal(
      () => dependencies.refreshWalletHoldings!(stale, dependencies.signal),
      dependencies.signal,
    );
    await assertCurrentAuthority(dependencies);
  } catch (error) {
    if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
    if (error instanceof WalletQueryProjectionError) throw error;
    if (!isRetryableWalletSourceError(error)) throw error;
    await assertCurrentAuthority(dependencies);
    return accounts;
  }
  const catalog = new Map(snapshot.host?.assetCatalog?.map((asset) => [asset.slug, asset]) ?? []);
  return accounts.map((account) => {
    const update = refreshed.get(account.accountId);
    if (!update) return account;
    const successfulChains = Object.keys(update.byChain);
    const retained = account.holdings.filter(({ asset }) => !successfulChains.includes(asset.chain));
    const existing = new Map(account.holdings.map((holding) => [holding.asset.slug, holding]));
    const holdings = successfulChains.flatMap((chain) => Object.entries(update.byChain[chain] ?? {}).flatMap(
      ([slug, amount]) => {
        const previous = existing.get(slug);
        const asset = previous?.asset ?? catalog.get(slug);
        if (!asset || asset.chain !== chain) return [];
        const balance = toDecimal(amount, asset.decimals, true);
        const fiatValue = previous?.fiatPrice
          ? Decimal.parse(balance).times(previous.fiatPrice).toString()
          : undefined;
        return [{
          asset,
          balance,
          ...(fiatValue && fiatValue !== '0'
            ? { fiatValue, fiatPrice: previous!.fiatPrice, valuationStatus: 'valued' as const }
            : { valuationStatus: 'unpriced' as const }),
          ...(previous?.riskVerdict ? { riskVerdict: previous.riskVerdict } : {}),
          visibility: previous?.visibility ?? 'visible',
        }];
      },
    ));
    const state = update.failedChains.length
      ? successfulChains.length ? 'stale' as const : 'unavailable' as const
      : 'fresh' as const;
    return {
      ...account,
      holdings: [...retained, ...holdings],
      domainStates: { ...account.domainStates, positions: { state, updatedAt: dependencies.completedAt } },
    };
  });
}

async function scanTransactionAccount(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  tokenSlug?: string,
  targetHash?: string,
): Promise<TransactionScanOutcome> {
  const fetchPastActivities = dependencies.fetchPastActivities!;
  const activities: ApiActivity[] = [];
  const seen = new Set<string>();
  let hasMore = true;
  let failed = false;
  let attempts = 0;
  let requestLimit = MAX_ACTIVITY_BATCH;
  while (hasMore && activities.length < MAX_ACTIVITY_SCAN_PER_ACCOUNT) {
    throwIfAborted(dependencies.signal);
    let slice: Awaited<ReturnType<FetchPastActivities>>;
    let requestAttempts = 0;
    try {
      slice = await withSingleRetry(
        () => {
          requestAttempts += 1;
          return fetchPastActivities(account.accountId, requestLimit, tokenSlug, undefined, {
            signal: dependencies.signal,
            shouldThrowOnError: true,
          });
        },
        dependencies.signal,
        () => assertCurrentAuthority(dependencies),
      );
      attempts = Math.max(attempts, requestAttempts);
    } catch (error) {
      if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
      if (error instanceof WalletQueryProjectionError) throw error;
      if (!isRetryableWalletSourceError(error)) throw error;
      failed = true;
      break;
    }
    if (!slice) {
      failed = true;
      break;
    }
    for (const activity of slice.activities) {
      if (seen.has(activity.id)) continue;
      seen.add(activity.id);
      activities.push(activity);
    }
    if (targetHash && activities.some((activity) => activityHasTransactionHash(activity, targetHash))) {
      hasMore = false;
      break;
    }
    hasMore = slice.hasMore;
    if (!hasMore) break;
    if (slice.activities.length < requestLimit || requestLimit >= MAX_ACTIVITY_SCAN_PER_ACCOUNT) break;
    requestLimit = Math.min(MAX_ACTIVITY_SCAN_PER_ACCOUNT, requestLimit * 2);
  }
  return { account, activities, attempts, failed, hasMore };
}

function projectTransaction(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  activity: ApiActivity,
): AgentWalletDataTransactionRowV3 {
  const accountRef = requireAccountRef(snapshot, account);
  const transactionType = activity.kind === 'swap'
    ? 'swap'
    : activity.type === 'approval' ? 'callContract' : activity.type ?? 'transfer';
  const direction = activity.kind === 'transaction'
    ? activity.fromAddress === activity.toAddress ? 'self' : activity.isIncoming ? 'incoming' : 'outgoing'
    : 'self';
  const primaryHash = getTransactionHashes(activity)[0] ?? activity.id;
  const primaryAmount = transactionPrimaryAmount(dependencies, account, activity, direction);
  const fee = transactionFee(dependencies, account, activity);
  const counterparty = activity.kind === 'transaction'
    ? transactionCounterparty(dependencies, snapshot, account, activity, direction)
    : undefined;
  const swapDetails = activity.kind === 'swap' ? {
    from: transactionAmount(dependencies, account, activity.from, activity.fromAmount),
    to: transactionAmount(dependencies, account, activity.to, activity.toAmount),
  } : undefined;
  const stakingDetails = activity.kind === 'transaction' && STAKING_TRANSACTION_TYPES.has(activity.type)
    ? {
      action: activity.type === 'stake' ? 'stake' as const
        : activity.type === 'unstakeRequest' ? 'unstake_request' as const : 'unstake' as const,
      ...(primaryAmount ? { amount: { ...primaryAmount, quantity: absoluteDecimal(primaryAmount.quantity) } } : {}),
    }
    : undefined;
  const nftDetails = activity.kind === 'transaction' && activity.nft ? {
    action: nftAction(activity),
    displayName: safeHumanDisplay(
      activity.nft.name, 'NFT', 160, nftSensitiveIdentifiers(activity.nft),
    ),
    ...(activity.nft.collectionName ? {
      collectionName: safeHumanDisplay(
        activity.nft.collectionName, 'NFT collection', 160, nftSensitiveIdentifiers(activity.nft),
      ),
    } : {}),
  } : undefined;
  const contractDetails = activity.kind === 'transaction' && isContractTransaction(activity.type) ? {
    contractDisplay: safeWalletQueryIdentifierDisplay(
      activity.metadata?.name,
      direction === 'incoming' ? activity.fromAddress : activity.toAddress,
      160,
    ),
  } : undefined;
  return {
    rowId: canonicalTransactionSourceRowId(accountRef, activity.id),
    kind: 'transaction',
    accountRef,
    accountLabel: safeWalletQueryAccountLabel(account),
    chain: getPrimaryChain(activity),
    displayHash: maskIdentifier(primaryHash),
    transactionType,
    direction,
    status: activity.status,
    timestamp: new Date(activity.timestamp).toISOString(),
    ...(primaryAmount ? primaryAmount : {}),
    ...(fee ? { fee } : {}),
    ...(counterparty ? { counterparty } : {}),
    safeDescription: buildSafeDescription(dependencies, account, activity, direction),
    ...(swapDetails ? { swapDetails } : {}),
    ...(nftDetails ? { nftDetails } : {}),
    ...(contractDetails ? { contractDetails } : {}),
    ...(stakingDetails ? { stakingDetails } : {}),
    ...(activity.status === 'failed' ? { failureReason: 'Transaction failed' } : {}),
    ...(activity.isScam ? { riskVerdict: 'spam' as const } : {}),
  };
}

function transactionPrimaryAmount(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  activity: ApiActivity,
  direction: AgentWalletDataTransactionRowV3['direction'],
) {
  if (
    activity.kind !== 'transaction'
    || activity.type === 'approval'
    || activity.nft
    || activity.amount === 0n
  ) return undefined;
  const asset = resolveAsset(dependencies, account, activity.slug);
  if (!asset) return undefined;
  const absolute = activity.amount < 0n ? -activity.amount : activity.amount;
  const quantity = toDecimal(absolute, asset.decimals, true);
  return {
    asset: projectAsset(asset),
    quantity: direction === 'outgoing' ? `-${quantity}` : quantity,
    decimals: asset.decimals,
  };
}

function transactionAmount(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  slug: string,
  quantity: string,
): AgentWalletTransactionAmountV1 {
  const asset = resolveAsset(dependencies, account, slug) ?? {
    slug,
    chain: getChainBySlug(slug),
    symbol: slug.slice(0, 32) || 'TOKEN',
    decimals: 0,
  };
  return {
    asset: projectAsset(asset),
    quantity: isCanonicalDecimal(quantity) ? canonicalDecimal(quantity) : '0',
    decimals: asset.decimals,
  };
}

function transactionFee(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  activity: ApiActivity,
): AgentWalletTransactionAmountV1 | undefined {
  const chain = getPrimaryChain(activity);
  const native = findNativeToken(chain as ApiChain);
  if (!native) return undefined;
  const asset = resolveAsset(dependencies, account, native.slug);
  if (!asset) return undefined;
  if (activity.kind === 'transaction') {
    if (activity.fee === 0n) return undefined;
    return {
      asset: projectAsset(asset),
      quantity: toDecimal(activity.fee < 0n ? -activity.fee : activity.fee, asset.decimals, true),
      decimals: asset.decimals,
    };
  }
  if (!activity.networkFee || !isCanonicalDecimal(activity.networkFee) || isZeroDecimal(activity.networkFee)) {
    return undefined;
  }
  return { asset: projectAsset(asset), quantity: canonicalDecimal(activity.networkFee), decimals: asset.decimals };
}

function transactionCounterparty(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  activity: Extract<ApiActivity, { kind: 'transaction' }>,
  direction: AgentWalletDataTransactionRowV3['direction'],
) {
  if (direction === 'self') return { kind: 'wallet' as const, display: 'Own wallet' };
  const address = direction === 'incoming' ? activity.fromAddress : activity.toAddress;
  const wallet = snapshot.host?.accounts.find((candidate) => (
    candidate.state === 'active' && Object.values(candidate.addresses).includes(address)
  ));
  if (wallet) return { kind: 'wallet' as const, display: safeWalletQueryAccountLabel(wallet, 160) };
  const saved = (account.savedAddresses ?? []).find((candidate) => candidate.address === address);
  const savedRefs = saved && dependencies.session.resolveSavedAddressRefs(account.accountId, saved.id);
  if (saved && savedRefs) {
    return {
      kind: 'contact' as const,
      display: safeWalletQueryIdentifierDisplay(saved.name, saved.address, 160),
      addressRef: savedRefs.addressRef,
    };
  }
  if (activity.metadata?.name) {
    return {
      kind: 'contract' as const,
      display: safeWalletQueryIdentifierDisplay(activity.metadata.name, address, 160),
    };
  }
  return { kind: 'external' as const, display: maskIdentifier(address) };
}

function buildSafeDescription(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  activity: ApiActivity,
  direction: AgentWalletDataTransactionRowV3['direction'],
) {
  if (activity.kind === 'swap') {
    const fromAsset = resolveAsset(dependencies, account, activity.from);
    const toAsset = resolveAsset(dependencies, account, activity.to);
    const from = fromAsset
      ? safeWalletQueryAssetSymbol(fromAsset)
      : safeHumanDisplay(activity.from, 'Asset', 32);
    const to = toAsset
      ? safeWalletQueryAssetSymbol(toAsset)
      : safeHumanDisplay(activity.to, 'Asset', 32);
    return sanitizeText(`Swap ${activity.fromAmount} ${from} for ${activity.toAmount} ${to}`, 512);
  }
  if (activity.nft) {
    const name = safeHumanDisplay(
      activity.nft.name, 'transaction', 160, nftSensitiveIdentifiers(activity.nft),
    );
    return sanitizeText(`NFT ${name}`, 512);
  }
  if (activity.type === 'stake') return 'Stake transaction';
  if (activity.type === 'unstake') return 'Unstake transaction';
  if (activity.type === 'unstakeRequest') return 'Unstake request';
  if (activity.type === 'approval') return 'Token approval';
  if (isContractTransaction(activity.type)) return 'Contract interaction';
  const asset = resolveAsset(dependencies, account, activity.slug);
  const quantity = asset
    ? toDecimal(activity.amount < 0n ? -activity.amount : activity.amount, asset.decimals, true)
    : (activity.amount < 0n ? -activity.amount : activity.amount).toString();
  const verb = direction === 'incoming' ? 'Received' : direction === 'outgoing' ? 'Sent' : 'Transferred';
  const symbol = asset
    ? safeWalletQueryAssetSymbol(asset)
    : safeHumanDisplay(activity.slug, 'Asset', 32);
  return sanitizeText(`${verb} ${quantity} ${symbol}`, 512);
}

async function loadHistory(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  range: keyof typeof RANGE_MAP,
): Promise<HistoryOutcome[]> {
  const selected = accounts.slice(0, MAX_HISTORY_ACCOUNTS);
  return Promise.all(selected.map(async (account) => {
    const cached = account.accountId === snapshot.host?.activeAccountId
      ? snapshot.host?.portfolioHistory?.[range]
      : undefined;
    const period = RANGE_MAP[range];
    const now = Date.parse(dependencies.completedAt);
    const currentSlot = getPortfolioHistorySlot(period, now);
    if (cached?.response && cached.fetchedAtSlot === currentSlot) {
      return { account, response: cached.response, source: 'cache' as const, failed: false };
    }
    if (dependencies.fetchPortfolioHistory && account.portfolioWalletKeys?.length) {
      try {
        const response = await withSingleRetry(() => dependencies.fetchPortfolioHistory!(
          account.portfolioWalletKeys!,
          snapshot.host!.baseCurrency as ApiBaseCurrency,
          buildPortfolioHistoryParams(period, now),
          { signal: dependencies.signal, timeoutMs: 15_000 },
        ), dependencies.signal, () => assertCurrentAuthority(dependencies));
        dependencies.onPortfolioHistory?.({
          accountId: account.accountId,
          baseCurrency: snapshot.host!.baseCurrency as ApiBaseCurrency,
          range: period,
          fetchedAtSlot: currentSlot,
          netWorth: response,
        });
        return { account, response, source: 'network' as const, failed: false };
      } catch (error) {
        if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
        if (error instanceof WalletQueryProjectionError) throw error;
        if (!isRetryableWalletSourceError(error)) throw error;
      }
    }
    return cached?.response
      ? { account, response: cached.response, source: 'cache' as const, failed: true }
      : { account, source: 'cache' as const, failed: true };
  }));
}

async function loadRangePnl(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  range: keyof typeof RANGE_MAP,
) {
  const walletKeys = [...new Set(accounts.flatMap(({ portfolioWalletKeys }) => portfolioWalletKeys ?? []))];
  if (!dependencies.fetchPortfolioPnlChange || walletKeys.length === 0) return undefined;
  const period = RANGE_MAP[range];
  const now = Date.parse(dependencies.completedAt);
  try {
    const response = await withSingleRetry(() => dependencies.fetchPortfolioPnlChange!(
      walletKeys,
      snapshot.host!.baseCurrency as ApiBaseCurrency,
      buildPortfolioHistoryParams(period, now),
      { signal: dependencies.signal, timeoutMs: 15_000 },
    ), dependencies.signal, () => assertCurrentAuthority(dependencies));
    await assertCurrentAuthority(dependencies);
    const startAt = new Date(response.startTs);
    const endAt = new Date(response.endTs);
    if (
      typeof response.amount !== 'number'
      || !Number.isFinite(response.amount)
      || typeof response.base !== 'string'
      || response.base.toUpperCase() !== snapshot.host!.baseCurrency.toUpperCase()
      || !Number.isFinite(startAt.getTime())
      || !Number.isFinite(endAt.getTime())
      || startAt.getTime() > endAt.getTime()
      || endAt.getTime() > now + 30_000
    ) return undefined;
    const percent = typeof response.percent === 'number' && Number.isFinite(response.percent)
      ? numberToDecimal(response.percent)
      : undefined;
    return {
      semantics: 'portfolio_pnl' as const,
      range,
      amount: numberToDecimal(response.amount),
      ...(percent === undefined ? {} : { percent }),
      baseCurrency: snapshot.host!.baseCurrency,
      startAt: startAt.toISOString(),
      endAt: endAt.toISOString(),
    };
  } catch (error) {
    if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
    if (error instanceof WalletQueryProjectionError) throw error;
    if (!isWalletSourceError(error)) throw error;
    return undefined;
  }
}

function buildHistorySeries(
  snapshot: AgentV2WalletSessionSnapshot,
  history: HistoryOutcome[],
  metric: 'portfolio_value' | 'position_value',
  selectors: AgentAssetSelector[],
  chains: AgentApiChain[],
  maxPoints: number,
): HistorySeriesProjection {
  let pointRowsOmitted = 0;
  const candidates = history.flatMap(({ account, response }) => {
    if (!response) return [];
    const asset = metric === 'position_value' ? resolveRequestedAsset(account, selectors, chains) : undefined;
    if (metric === 'position_value' && !asset) return [];
    const projection = metric === 'portfolio_value'
      ? projectHistoryPoints(response.points, maxPoints)
      : projectPositionHistoryPoints(response, asset!, maxPoints);
    pointRowsOmitted += projection.rowsOmitted;
    const { points } = projection;
    if (!points.length) return [];
    return [{
      seriesId: canonicalWalletQueryRowId(
        'series', `${requireAccountRef(snapshot, account)}\0${metric}\0${assetKey(asset)}`,
      ),
      metric,
      label: metric === 'portfolio_value'
        ? safeWalletQueryAccountLabel(account, 160)
        : safeWalletQueryAssetSymbol(asset!, 160),
      baseCurrency: snapshot.host!.baseCurrency,
      ...(asset ? { asset: projectAsset(asset) } : {}),
      points,
    }];
  });
  const series = candidates.slice(0, MAX_SERIES);
  return {
    series,
    rowsOmitted: pointRowsOmitted + Math.max(0, candidates.length - series.length),
  };
}

function projectHistoryPoints(
  points: ApiPortfolioHistoryResponse['points'],
  maxPoints: number,
): { points: AgentWalletDataSeriesPointV1[]; rowsOmitted: number } {
  const validPoints = (points ?? []).flatMap(([timestamp, value]) => (
    typeof value === 'number' && Number.isFinite(value) && value >= 0
      ? [{ timestamp: new Date(timestamp * 1000).toISOString(), value: numberToDecimal(value) }]
      : []
  ));
  return {
    points: downsample(validPoints, maxPoints),
    rowsOmitted: Math.max(0, validPoints.length - maxPoints),
  };
}

function projectPositionHistoryPoints(
  response: ApiPortfolioHistoryResponse,
  asset: AgentV2HostAsset,
  maxPoints: number,
) {
  const tokenAddress = asset.tokenAddress?.toLocaleLowerCase('en-US');
  const symbol = asset.symbol.toLocaleLowerCase('en-US');
  const dataset = response.datasets?.find((candidate) => tokenAddress
    ? candidate.contractAddress.toLocaleLowerCase('en-US') === tokenAddress
    : candidate.symbol.toLocaleLowerCase('en-US') === symbol);
  return projectHistoryPoints(dataset?.points ?? [], maxPoints);
}

function resolveRequestedAsset(
  account: AgentV2HostAccount,
  selectors: AgentAssetSelector[],
  chains: AgentApiChain[],
) {
  return account.holdings.map(({ asset }) => asset)
    .find((asset) => (
      (!chains.length || chains.includes(asset.chain))
      && selectors.some((selector) => matchesSelector(asset, selector))
    ));
}

function aggregatePositions(
  positions: AgentWalletDataPositionRowV3[],
  groupBy: 'account' | 'asset' | 'network' | 'position_type',
  baseCurrency: string,
): AgentWalletDataAggregateRowV2[] {
  const groups = new Map<string, { label: string; value: Decimal; unpricedCount: number }>();
  for (const position of positions) {
    const [key, label] = groupBy === 'account' ? [position.accountRef, position.accountLabel]
      : groupBy === 'asset' ? [assetKey(position.asset), position.asset.symbol]
        : groupBy === 'network' ? [position.chain, position.chain]
          : [position.positionKind, position.positionKind];
    const current = groups.get(key) ?? { label, value: Decimal.zero(), unpricedCount: 0 };
    if (position.valuationStatus === 'valued') current.value = current.value.plus(position.fiatValue!);
    if (position.valuationStatus === 'unpriced') current.unpricedCount += 1;
    groups.set(key, current);
  }
  return [...groups.entries()].map(([key, group]) => ({
    rowId: canonicalWalletQueryRowId('aggregate', `${groupBy}\0${key}`),
    kind: 'aggregate' as const,
    groupKind: groupBy,
    label: groupBy === 'asset'
      ? safeHumanDisplay(group.label, 'Asset', 160)
      : sanitizeText(group.label, 160),
    value: group.value.toString(),
    baseCurrency,
    unpricedCount: group.unpricedCount,
  })).sort((left, right) => Decimal.parse(right.value).compare(Decimal.parse(left.value))
    || left.label.localeCompare(right.label));
}

function buildAllocations(
  positions: AgentWalletDataPositionRowV3[],
  total: Decimal,
  baseCurrency: string,
): AgentWalletPortfolioAllocationV1[] {
  const groups = new Map<string, { asset: AgentAssetIdentityV2; value: Decimal }>();
  for (const position of positions) {
    const key = assetKey(position.asset);
    const current = groups.get(key) ?? { asset: position.asset, value: Decimal.zero() };
    current.value = current.value.plus(position.fiatValue!);
    groups.set(key, current);
  }
  return [...groups.values()].sort((left, right) => right.value.compare(left.value)
    || assetKey(left.asset).localeCompare(assetKey(right.asset))).map(({ asset, value }) => ({
    asset,
    value: value.toString(),
    baseCurrency,
    percent: total.isZero() ? '0' : value.ratioPercent(total, 12),
  }));
}

function resolvedBase(
  dependencies: WalletQueryMaterializationDependencies,
  resolvedScope: AgentWalletResolvedScopeV1,
  coverage: AgentWalletDataCoverageV5,
  source: 'cache' | 'network' | 'mixed' = 'cache',
) {
  return {
    schemaVersion: 5 as const,
    status: 'resolved' as const,
    resolvedScope: cloneJson(resolvedScope),
    generatedAt: dependencies.completedAt,
    freshness: freshness(
      dependencies.completedAt,
      source,
      coverage.limitations.includes('stale_data'),
    ),
    coverage,
  };
}

function makeCoverage(input: {
  domain: AgentWalletSourceOutcomeV1['domain'];
  accountsRequested: number;
  accountsIncluded: number;
  rowsOmitted: number;
  limitations: AgentWalletDataCoverageV5['limitations'];
  rowCount: number;
  attempts?: number;
}): AgentWalletDataCoverageV5 {
  const limitations = uniqueLimitations([
    ...input.limitations,
    ...(input.accountsRequested > 0 && input.accountsIncluded === 0 ? ['source_unavailable' as const] : []),
    ...(input.accountsIncluded > 0 && input.accountsIncluded < input.accountsRequested
      ? ['source_partial' as const]
      : []),
  ]).slice(0, 8);
  const unavailableResult = input.accountsRequested > 0
    && input.accountsIncluded === 0
    && limitations.includes('source_unavailable');
  const complete = input.accountsIncluded === input.accountsRequested
    && input.rowsOmitted === 0
    && limitations.length === 0;
  const status = unavailableResult ? 'unavailable' : complete ? 'complete' : 'partial';
  const sourceStatus = unavailableResult ? 'failed_retryable'
    : limitations.includes('stale_data') ? 'stale'
      : input.rowCount === 0 ? 'complete_empty' : 'complete';
  return {
    status,
    ...(status === 'complete' && input.rowCount === 0 ? { emptyReason: 'no_matching_rows' as const } : {}),
    accountsRequested: input.accountsRequested,
    accountsIncluded: input.accountsIncluded,
    rowsOmitted: input.rowsOmitted,
    limitations,
    sourceOutcomes: [{
      domain: input.domain,
      status: sourceStatus,
      attempts: Math.min(SOURCE_RETRY_ATTEMPTS, input.attempts ?? 1),
      ...(input.accountsRequested ? {
        accountsRequested: input.accountsRequested,
        accountsIncluded: input.accountsIncluded,
      } : {}),
      ...(sourceStatus === 'failed_retryable' ? { reason: 'upstream_unavailable' as const }
        : sourceStatus === 'stale' ? { reason: 'stale_cache' as const } : {}),
    }],
  };
}

function requestedAccountCount(
  dependencies: WalletQueryMaterializationDependencies,
  accounts: AgentV2HostAccount[],
) {
  return dependencies.scope?.accountsRequested ?? accounts.length;
}

async function assertCurrentAuthority(dependencies: WalletQueryMaterializationDependencies) {
  const current = await dependencies.session.walletAuthorityBinding();
  const expected = dependencies.authorityBinding;
  if (
    current.accountDigest !== expected.accountDigest
    || current.profileDigest !== expected.profileDigest
    || current.revision !== expected.revision
    || current.sessionId !== expected.sessionId
  ) throw new WalletQueryProjectionError('wallet_context_changed', 'The active wallet changed.', false);
}

function freshness(asOf: string, source: 'cache' | 'network' | 'mixed', isStale: boolean) {
  return { asOf, source, isStale };
}

function resolveAccounts(
  snapshot: AgentV2WalletSessionSnapshot,
  scope: WalletQueryMaterializationScope,
  call: AgentToolCall,
  allowInactive: boolean,
  accountFilter: AgentWalletAccountFilterV1 | undefined,
) {
  const host = snapshot.host;
  if (!host || call.name !== 'wallet.data.query'
    || call.walletContextSession.accountScope !== scope.accountScope) {
    throw invalid('The wallet query account scope does not match.');
  }
  const available = host.accounts.filter(({ state }) => allowInactive || state === 'active').slice(0, 100);
  const expectedExplicitAll = available.filter((account) => (
    matchesPortfolioAccountFilter(account, accountFilter)
  ));
  if (scope.accountScope === 'explicitAll') {
    if (
      call.scopeIntent?.reason !== 'explicit_all_wallet_query'
      || call.scopeIntent.messageId !== call.intentSource?.messageId
      || scope.accountIds.length !== expectedExplicitAll.length
      || scope.accountIds.some((accountId, index) => (
        accountId !== expectedExplicitAll[index]?.accountId
      ))
    ) throw invalid('Cross-wallet data access is not allowed.');
  }
  if (scope.accountScope === 'selected' && (
    call.scopeIntent?.reason !== 'selected_wallet_query'
    || call.scopeIntent.messageId !== call.intentSource?.messageId
  )) throw invalid('Selected-wallet data access is not allowed.');
  const selected = scope.accountIds.map((accountId) => available.find((account) => account.accountId === accountId));
  if (selected.some((account) => !account)) throw invalid('The wallet scope is unavailable.');
  if (scope.accountScope === 'current' && (
    selected.length !== 1 || selected[0]?.accountId !== host.activeAccountId
  )) throw invalid('The active wallet scope is invalid.');
  if (scope.accountScope === 'selected' && selected.length !== 1) {
    throw invalid('The selected wallet scope is invalid.');
  }
  return selected as AgentV2HostAccount[];
}

function matchesTransactionFilters(row: AgentWalletDataTransactionRowV3, filters: AgentWalletFilterSetV1) {
  return filters.clauses.every((clause) => {
    if (clause.field === 'transaction.status') return clause.values.includes(row.status);
    if (clause.field === 'transaction.direction') return clause.values.includes(row.direction);
    if (clause.field === 'transaction.chain') return clause.values.includes(row.chain);
    if (clause.field === 'transaction.timestamp') {
      const value = Date.parse(row.timestamp);
      return value >= Date.parse(clause.range.fromInclusive) && value < Date.parse(clause.range.toExclusive);
    }
    return Boolean(row.asset && clause.values.some((selector) => matchesSelector(row.asset!, selector)));
  });
}

function transactionTokenSlug(filters: AgentWalletFilterSetV1) {
  const assets = filters.clauses.find((clause) => clause.field === 'transaction.asset');
  return assets?.field === 'transaction.asset' && assets.values.length === 1 ? assets.values[0].slug : undefined;
}

function matchesRisk(riskVerdict: 'spam' | undefined, riskMode: AgentWalletRiskModeV1) {
  return riskMode === 'all' || (riskMode === 'only' ? riskVerdict === 'spam' : riskVerdict !== 'spam');
}

function matchesAsset(asset: AgentV2HostAsset, chains: AgentApiChain[], selectors: AgentAssetSelector[]) {
  return (!chains.length || chains.includes(asset.chain))
    && (!selectors.length || selectors.some((selector) => matchesSelector(asset, selector)));
}

function matchesPosition(position: AgentV2HostPosition, chains: AgentApiChain[], selectors: AgentAssetSelector[]) {
  return (!chains.length || chains.includes(position.chain))
    && (!selectors.length || Boolean(position.asset
      && selectors.some((selector) => matchesSelector(position.asset!, selector))));
}

function matchesSelector(
  asset: Pick<AgentV2HostAsset, 'chain' | 'slug' | 'symbol' | 'tokenAddress'>,
  selector: AgentAssetSelector,
) {
  return (!selector.slug || selector.slug === asset.slug)
    && (!selector.chain || selector.chain === asset.chain)
    && (!selector.tokenAddress || normalizeSearch(selector.tokenAddress) === normalizeSearch(asset.tokenAddress ?? ''))
    && (!selector.symbol || normalizeSearch(selector.symbol) === normalizeSearch(asset.symbol));
}

function matchAssetSearch(asset: AgentV2HostAsset, query: string) {
  const fields = [
    ['address', asset.tokenAddress],
    ['symbol', asset.symbol],
    ['slug', asset.slug],
    ['name', asset.name],
  ] as const;
  for (const [matchedOn, raw] of fields) {
    const value = normalizeAssetLookup(raw ?? '');
    if (value && value === query) return { matchQuality: 'exact' as const, matchedOn };
  }
  return undefined;
}

function resolveAsset(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  slug: string,
) {
  return dependencies.getTokenBySlug?.(slug)
    ?? account.holdings.find(({ asset }) => asset.slug === slug)?.asset
    ?? dependencies.session.snapshot().host?.assetCatalog?.find((asset) => asset.slug === slug);
}

function getPrimaryChain(activity: ApiActivity): AgentApiChain {
  if (activity.kind === 'transaction') return getChainBySlug(activity.slug);
  return getActivityChains(activity)[0] ?? getChainBySlug(activity.from);
}

function getTransactionHashes(activity: ApiActivity) {
  if (activity.kind === 'transaction') {
    let parsed: string | undefined;
    try {
      parsed = parseTxId(activity.id).hash;
    } catch {
      parsed = undefined;
    }
    return [...new Set([activity.externalMsgHashNorm, parsed, activity.id].filter(Boolean))];
  }
  return [...new Set([
    activity.transactionIds.outgoing?.hash,
    activity.transactionIds.incoming?.hash,
    activity.msgHash,
    ...activity.hashes,
  ].filter(Boolean))];
}

function activityHasTransactionHash(activity: ApiActivity, hash: string) {
  return getTransactionHashes(activity).some((candidate) => (
    candidate !== undefined && transactionHashesEqual(candidate, hash)
  ));
}

function nftAction(activity: Extract<ApiActivity, { kind: 'transaction' }>) {
  if (activity.type === 'mint') return 'mint' as const;
  if (activity.type === 'burn') return 'burn' as const;
  if (activity.type === 'nftTrade') return activity.isIncoming ? 'purchase' as const : 'sale' as const;
  return 'transfer' as const;
}

function isContractTransaction(type: Extract<ApiActivity, { kind: 'transaction' }>['type']) {
  return type === 'callContract' || type === 'approval' || type === 'contractDeploy'
    || type?.startsWith('dns') || type?.startsWith('liquidity');
}

function compareTransactions(left: AgentWalletDataTransactionRowV3, right: AgentWalletDataTransactionRowV3) {
  return Date.parse(right.timestamp) - Date.parse(left.timestamp) || left.rowId.localeCompare(right.rowId);
}

function dedupeRows(rows: AgentWalletDataTransactionRowV3[]) {
  const unique = new Map<string, AgentWalletDataTransactionRowV3>();
  rows.forEach((row) => unique.set(row.rowId, row));
  return [...unique.values()];
}

function sortPositions(rows: AgentWalletDataPositionRowV3[], order: 'wallet_order' | 'value_desc' | 'quantity_desc') {
  if (order === 'wallet_order') return rows;
  const field = order === 'value_desc' ? 'fiatValue' : 'quantity';
  return [...rows].sort((left, right) => compareOptionalDecimals(right[field], left[field])
    || assetKey(left.asset).localeCompare(assetKey(right.asset))
    || left.rowId.localeCompare(right.rowId));
}

function positionStateLimitations(accounts: AgentV2HostAccount[]) {
  const states = accounts.map(({ domainStates }) => domainStates?.positions?.state ?? 'notLoaded');
  return uniqueLimitations([
    ...(states.includes('stale') ? ['stale_data' as const] : []),
    ...(states.some((state) => state === 'notLoaded' || state === 'unavailable')
      ? ['source_partial' as const]
      : []),
  ]);
}

function availablePositionAccountCount(accounts: AgentV2HostAccount[]) {
  return accounts.filter(({ domainStates }) => {
    const state = domainStates?.positions?.state;
    return state === undefined || state === 'fresh' || state === 'stale';
  }).length;
}

function projectAsset(asset: AgentV2HostAsset): AgentAssetIdentityV2 {
  return {
    slug: asset.slug,
    chain: asset.chain,
    symbol: safeWalletQueryAssetSymbol(asset),
    ...(asset.name ? {
      name: safeHumanDisplay(
        asset.name, 'Asset', 160, asset.tokenAddress ? [asset.tokenAddress] : [],
      ),
    } : {}),
    ...(asset.tokenAddress ? { tokenAddress: asset.tokenAddress } : {}),
    decimals: asset.decimals,
  };
}

export function safeWalletQueryAssetSymbol(
  asset: Pick<AgentV2HostAsset, 'symbol' | 'tokenAddress'>,
  maxLength = 32,
) {
  return safeHumanDisplay(
    asset.symbol, 'Asset', maxLength, asset.tokenAddress ? [asset.tokenAddress] : [],
  );
}

function uniqueAssets(assets: AgentV2HostAsset[]) {
  const unique = new Map<string, AgentV2HostAsset>();
  assets.forEach((asset) => unique.set(assetKey(asset), asset));
  return [...unique.values()];
}

function requireAccountRef(snapshot: AgentV2WalletSessionSnapshot, account: AgentV2HostAccount) {
  const accountRef = snapshot.accountRefs.get(account.accountId);
  if (!accountRef) throw invalid('A wallet account reference is unavailable.');
  return accountRef;
}

function canonicalPositionStatus(value?: string): AgentWalletDataPositionRowV3['status'] | undefined {
  return value === 'active' || value === 'unstaking' || value === 'ready'
    || value === 'frozen' || value === 'locked' ? value : undefined;
}

function assetKey(asset?: { chain: string; slug: string; tokenAddress?: string }) {
  return asset ? `${asset.chain}\0${asset.slug}\0${asset.tokenAddress ?? ''}` : '';
}

function normalizeSearch(value: string) {
  return value.normalize('NFKC').trim().toLocaleLowerCase('en-US').replace(/\s+/gu, ' ');
}

function normalizeAssetLookup(value: string) {
  return normalizeSearch(value).replaceAll('₮', 't');
}

function sanitizeText(value: string, maxLength: number) {
  return value.normalize('NFC').replace(/[\p{Cc}\p{Cf}]/gu, '').replace(/\s+/gu, ' ')
    .trim().slice(0, maxLength) || 'Unknown';
}

function maskIdentifier(value: string) {
  const sanitized = sanitizeText(value, 256);
  const masked = shortenAddress(sanitized, 8, 8);
  if (masked && masked !== sanitized) return masked.slice(0, 80);
  if (sanitized.length > 8) return `${sanitized.slice(0, 4)}…${sanitized.slice(-4)}`.slice(0, 80);
  return `${sanitized.slice(0, 2)}…${sanitized.slice(-2)}`.padEnd(5, '•').slice(0, 80);
}

export function safeWalletQueryIdentifierDisplay(
  value: string | undefined,
  fallbackIdentifier: string,
  maxLength: number,
) {
  return safeHumanDisplay(value, maskIdentifier(fallbackIdentifier), maxLength, [fallbackIdentifier]);
}

function safeHumanDisplay(
  value: string | undefined,
  fallback: string,
  maxLength: number,
  sensitiveIdentifiers: string[] = [],
) {
  const display = sanitizeText(value || fallback, maxLength);
  if (
    sensitiveIdentifiers.some((identifier) => (
      normalizeIdentifierDisplay(display).includes(normalizeIdentifierDisplay(identifier))
    ))
    || containsSensitiveIdentifier(display)
  ) return sanitizeText(fallback, maxLength);
  return display;
}

export function safeWalletQueryAccountLabel(account: AgentV2HostAccount, maxLength = 80) {
  const addresses = Object.values(account.addresses).filter((address): address is string => Boolean(address));
  return safeHumanDisplay(
    account.label,
    'Wallet',
    maxLength,
    addresses.length ? addresses : [account.accountId],
  );
}

function containsSensitiveIdentifier(value: string) {
  return /(?:0[xX][A-Fa-f0-9]{40}|[A-Fa-f0-9]{64}|[A-Za-z0-9+/_-]{43,126}={0,2}|[1-9A-HJ-NP-Za-km-z]{32,44})/u
    .test(value);
}

function normalizeIdentifierDisplay(value: string) {
  return value.normalize('NFKC').toLocaleLowerCase('en-US');
}

function nftSensitiveIdentifiers(nft: ApiNft) {
  return [nft.address, nft.collectionAddress].filter((value): value is string => Boolean(value));
}

function isBoundedText(value: string, maxLength: number) {
  const length = [...value].length;
  return length >= 1 && length <= maxLength;
}

function isCanonicalDecimal(value?: string): value is string {
  return Boolean(value && /^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(value));
}

function isSignedDecimal(value: string) {
  return /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(value);
}

function isZeroDecimal(value: string) {
  return /^0(?:\.0+)?$/u.test(value);
}

function canonicalDecimal(value: string) {
  const [whole, fraction] = value.split('.');
  const trimmed = fraction?.replace(/0+$/u, '');
  return trimmed ? `${whole}.${trimmed}` : whole;
}

function canonicalSignedDecimal(value: string) {
  const sign = value.startsWith('-') ? '-' : '';
  return `${sign}${canonicalDecimal(value.replace(/^-/, ''))}`;
}

function absoluteDecimal(value: string) {
  return value.startsWith('-') ? value.slice(1) : value;
}

function compareOptionalDecimals(left?: string, right?: string) {
  if (!left) return right ? -1 : 0;
  if (!right) return 1;
  return Decimal.parse(left).compare(Decimal.parse(right));
}

function numberToDecimal(value: number) {
  return value.toFixed(12).replace(/(?:\.0+|(?<fraction>\.\d*?)0+)$/u, '$<fraction>');
}

function downsample<T>(values: T[], limit: number) {
  if (values.length <= limit) return values;
  if (limit <= 1) return [values[values.length - 1]];
  return Array.from({ length: limit }, (_, index) => (
    values[Math.round(index * (values.length - 1) / (limit - 1))]
  ));
}

function uniqueLimitations<T extends AgentWalletDataCoverageV5['limitations'][number]>(values: T[]) {
  return [...new Set(values)];
}

async function mapWithConcurrency<Input, Output>(
  items: readonly Input[],
  concurrency: number,
  callback: (item: Input) => Promise<Output>,
) {
  const results = new Array<Output>(items.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (nextIndex < items.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await callback(items[index]);
    }
  });
  await Promise.all(workers);
  return results;
}

async function withSingleRetry<T>(
  operation: () => Promise<T>,
  signal: AbortSignal,
  afterAwait: () => Promise<void>,
) {
  let lastError: unknown;
  for (let attempt = 0; attempt < SOURCE_RETRY_ATTEMPTS; attempt += 1) {
    throwIfAborted(signal);
    try {
      const result = await raceWithAbortSignal(operation, signal);
      await afterAwait();
      return result;
    } catch (error) {
      if (signal.aborted) throw signal.reason ?? error;
      if (error instanceof WalletQueryProjectionError) throw error;
      if (!isRetryableWalletSourceError(error)) throw error;
      await afterAwait();
      lastError = error;
    }
  }
  throw lastError;
}

function matchFieldRank(value: 'symbol' | 'name' | 'slug' | 'address') {
  return ['address', 'symbol', 'slug', 'name'].indexOf(value);
}

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function invalid(message: string) {
  return new WalletQueryProjectionError('invalid_arguments', message, false);
}

function unavailable(message: string) {
  return new WalletQueryProjectionError('stale_data_unavailable', message, true);
}

class Decimal {
  private constructor(private readonly units: bigint, private readonly scale: number) {}

  static zero() { return new Decimal(0n, 0); }

  static parse(value: string) {
    if (!isCanonicalDecimal(value)) throw invalid('A wallet decimal is invalid.');
    const [whole, fraction = ''] = value.split('.');
    return new Decimal(BigInt(`${whole}${fraction}`), fraction.length).normalize();
  }

  plus(value: string | Decimal) {
    const other = typeof value === 'string' ? Decimal.parse(value) : value;
    const scale = Math.max(this.scale, other.scale);
    return new Decimal(
      this.units * 10n ** BigInt(scale - this.scale) + other.units * 10n ** BigInt(scale - other.scale),
      scale,
    ).normalize();
  }

  times(value: string | Decimal) {
    const other = typeof value === 'string' ? Decimal.parse(value) : value;
    return new Decimal(this.units * other.units, this.scale + other.scale).normalize();
  }

  compare(other: Decimal) {
    const scale = Math.max(this.scale, other.scale);
    const left = this.units * 10n ** BigInt(scale - this.scale);
    const right = other.units * 10n ** BigInt(scale - other.scale);
    return left === right ? 0 : left > right ? 1 : -1;
  }

  isZero() { return this.units === 0n; }

  ratioPercent(total: Decimal, precision: number) {
    if (total.units === 0n) return '0';
    const scale = Math.max(this.scale, total.scale);
    const numerator = this.units * 10n ** BigInt(scale - this.scale);
    const denominator = total.units * 10n ** BigInt(scale - total.scale);
    const factor = 10n ** BigInt(precision);
    const scaled = numerator * 100n * factor / denominator;
    const whole = scaled / factor;
    const fraction = (scaled % factor).toString().padStart(precision, '0').replace(/0+$/u, '');
    return fraction ? `${whole}.${fraction}` : whole.toString();
  }

  toString() {
    if (!this.scale) return this.units.toString();
    const digits = this.units.toString().padStart(this.scale + 1, '0');
    return `${digits.slice(0, -this.scale)}.${digits.slice(-this.scale)}`;
  }

  private normalize() {
    let { units, scale } = this;
    while (scale && units % 10n === 0n) {
      units /= 10n;
      scale -= 1;
    }
    return new Decimal(units, scale);
  }
}
