import type { ApiChain } from '../types';
import type {
  AgentApiChain,
  AgentAssetIdentityV2,
  AgentWalletDataAggregateRowV2,
  AgentWalletDataPolicySummaryV1,
  AgentWalletDataPositionRowV3,
  AgentWalletDataQueryArgs,
  AgentWalletDataQueryResult,
  AgentWalletPortfolioAllocationV1,
  AgentWalletResolvedScopeV1,
  AgentWalletRiskModeV1,
  AgentWalletSourceOutcomeV1,
} from './protocol/types';
import type { AgentV2HostAccount, AgentV2HostAsset, AgentV2HostPosition, AgentV2PositionKind } from './types';
import type { PositionCandidate, WalletQueryMaterializationDependencies } from './walletQueryTypes';
import type { AgentV2WalletSession, AgentV2WalletSessionSnapshot } from './walletSession';

import { getChainsSupportingNft } from '../../util/chain';
import { getBackendConfigCacheSync } from '../common/cache';
import { assetKey, matchesAsset, matchesPosition } from './walletQueryAssets';
import {
  canonicalDecimal,
  canonicalSignedDecimal,
  compareOptionalDecimals,
  Decimal,
  isCanonicalDecimal,
  isSignedDecimal,
  isZeroDecimal,
} from './walletQueryDecimal';
import { invalid } from './walletQueryErrors';
import {
  makeCoverage,
  projectAsset,
  requestedAccountCount,
  requireAccountRef,
  resolvedBase,
  safeHumanDisplay,
  safeWalletQueryAccountLabel,
  safeWalletQueryAssetSymbol,
  sanitizeText,
  uniqueLimitations,
} from './walletQueryOutput';
import { canonicalWalletQueryRowId } from './walletQueryRowId';

export function buildAccountPortfolioTotal(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  chains: AgentApiChain[],
) {
  const sourceStates = getPositionStates(account, chains);
  if (!sourceStates.some((state) => state === 'fresh' || state === 'stale')) {
    return { status: 'unavailable' as const };
  }
  const built = collectPositions(session, snapshot, [account], {
    assetSelectors: [],
    chains,
    includeZero: false,
    positionKinds: POSITION_KINDS,
    riskMode: 'exclude',
    visibilityMode: 'all',
  });
  const valued = built.rows.filter(({ valuationStatus }) => valuationStatus === 'valued');
  const unpricedCount = built.rows.length - valued.length + built.invalidRows;
  const value = valued.reduce((sum, row) => sum.plus(row.fiatValue!), Decimal.zero()).toString();
  return {
    status: sourceStates.some((state) => state !== 'fresh') || unpricedCount
      ? 'partial' as const : 'complete' as const,
    total: { value, baseCurrency: snapshot.host!.baseCurrency, unpricedCount },
  };
}

export function buildPositionList(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'positions.list' }>,
): Extract<AgentWalletDataQueryResult, { operation: 'positions.list' }> {
  const built = collectPositions(dependencies.session, snapshot, accounts, args);
  const selected = sortPositions(built.rows, args.sort).slice(0, args.pageSize);
  const omitted = Math.max(0, built.rows.length - selected.length) + built.invalidRows;
  const limitations = uniqueLimitations([
    ...(omitted ? ['row_limit' as const] : []),
    ...(selected.some(({ valuationStatus }) => valuationStatus === 'unpriced')
      ? ['unpriced_positions' as const]
      : []),
    ...positionStateLimitations(accounts, args.chains, args.positionKinds),
  ]);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'positions',
      sourceStatus: getPositionSourceStatus(accounts, args.chains, args.positionKinds),
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: availablePositionAccountCount(accounts, args.chains, args.positionKinds),
      rowsOmitted: omitted,
      limitations,
      rowCount: selected.length,
    })),
    operation: 'positions.list',
    policySummary: built.policySummary,
    positions: selected,
  };
}

export function buildPortfolio(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'portfolio.aggregate' }>,
): Extract<AgentWalletDataQueryResult, { operation: 'portfolio.aggregate' }> {
  const built = collectPositions(dependencies.session, snapshot, accounts, {
    ...args,
    assetSelectors: [],
    positionKinds: POSITION_KINDS,
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
  const shouldProvideHistoryAccounts = args.historySource === 'backend';
  if (shouldProvideHistoryAccounts && args.chains.length) {
    throw invalid('Backend portfolio history requires whole accounts.');
  }
  const rowLimitOmitted = Math.max(0, sorted.length - positions.length)
    + Math.max(0, allocationRows.length - allocations.length)
    + Math.max(0, aggregateRows.length - aggregates.length)
    + built.invalidRows;
  const limitations = uniqueLimitations([
    ...(rowLimitOmitted ? ['row_limit' as const] : []),
    ...(unpricedCount ? ['unpriced_positions' as const] : []),
    ...positionStateLimitations(accounts, args.chains),
  ]);
  const coverage = makeCoverage({
    domain: 'portfolio',
    sourceStatus: getPositionSourceStatus(accounts, args.chains),
    accountsRequested: requestedAccountCount(dependencies, accounts),
    accountsIncluded: availablePositionAccountCount(accounts, args.chains),
    rowsOmitted: rowLimitOmitted,
    limitations,
    rowCount: positions.length + allocations.length + aggregates.length,
  });
  return {
    ...resolvedBase(dependencies, resolvedScope, coverage),
    operation: 'portfolio.aggregate',
    ...(shouldProvideHistoryAccounts ? {
      historyAccounts: accounts.map((account) => ({
        accountRef: requireAccountRef(snapshot, account),
        wallets: [...new Set(account.portfolioWalletKeys ?? [])],
      })),
    } : {}),
    policySummary: built.policySummary,
    total: {
      value: totalValue.toString(),
      baseCurrency: snapshot.host!.baseCurrency,
      unpricedCount,
    },
    allocations,
    positions,
    aggregates,
    series: [],
  };
}

export function collectWalletSnapshotPositions(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
) {
  return collectPositions(session, snapshot, [account], {
    assetSelectors: [], chains: [], includeZero: true,
    positionKinds: ['fungible'], riskMode: 'all', visibilityMode: 'all',
  });
}

function collectPositions(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  args: Pick<
    Extract<AgentWalletDataQueryArgs, { operation: 'positions.list' }>,
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
  const accuracy = positionStateLimitations(accounts, args.chains).length ? 'lower_bound' : 'exact';
  const policySummary: AgentWalletDataPolicySummaryV1 = {
    riskMode: args.riskMode,
    visibilityMode: args.visibilityMode,
    spamMatches: { count: spamMatches, accuracy },
    hiddenMatches: { count: hiddenMatches, accuracy },
  };
  return { rows, candidates, invalidRows, policySummary };
}

function projectExtraPosition(
  session: AgentV2WalletSession,
  snapshot: AgentV2WalletSessionSnapshot,
  account: AgentV2HostAccount,
  accountRef: string,
  position: AgentV2HostPosition,
): AgentWalletDataPositionRowV3 | undefined {
  const asset = position.asset ?? (position.kind === 'nft' ? nftPositionAsset(position) : undefined);
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

function nftPositionAsset(position: AgentV2HostPosition): AgentV2HostAsset {
  return {
    slug: position.id.slice(0, 128),
    chain: position.chain,
    symbol: 'NFT',
    name: safeHumanDisplay(position.label, 'Asset', 160),
    decimals: 0,
  };
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

export function matchesRisk(riskVerdict: 'spam' | undefined, riskMode: AgentWalletRiskModeV1) {
  return riskMode === 'all' || (riskMode === 'only' ? riskVerdict === 'spam' : riskVerdict !== 'spam');
}

function sortPositions(rows: AgentWalletDataPositionRowV3[], order: 'wallet_order' | 'value_desc' | 'quantity_desc') {
  if (order === 'wallet_order') return rows;
  const field = order === 'value_desc' ? 'fiatValue' : 'quantity';
  return [...rows].sort((left, right) => compareOptionalDecimals(right[field], left[field])
    || assetKey(left.asset).localeCompare(assetKey(right.asset))
    || left.rowId.localeCompare(right.rowId));
}

function getPositionStates(account: AgentV2HostAccount, chains: readonly AgentApiChain[], kinds = POSITION_KINDS) {
  // While the backend keeps vesting off, no account has a vesting, so there is none for the host to load
  const config = getBackendConfigCacheSync();
  const isVestingOff = Boolean(config && !config.isVestingEnabled);
  return kinds.map((kind) => {
    if (kind === 'nft') {
      return getNftState(account, chains);
    }
    return kind === 'vesting' && isVestingOff
      ? 'fresh' as const
      : account.domainStates?.[kind]?.state ?? 'notLoaded';
  });
}

/**
 * NFTs load network by network, so the networks a read covers decide: each NFT network of the account among them
 * must have been read in full. The rows of the networks already read are listed either way.
 */
function getNftState(account: AgentV2HostAccount, chains: readonly AgentApiChain[]) {
  const nftChains = getChainsSupportingNft();
  const loadedChains = new Set(account.nftLoadedChains);
  const isLoaded = account.chains
    .filter((chain) => nftChains.has(chain as ApiChain) && (!chains.length || chains.includes(chain)))
    .every((chain) => loadedChains.has(chain));
  return isLoaded ? 'fresh' : 'notLoaded';
}

export function getPositionSourceStatus(
  accounts: AgentV2HostAccount[],
  chains: readonly AgentApiChain[],
  kinds = POSITION_KINDS,
): AgentWalletSourceOutcomeV1['status'] | undefined {
  const states = accounts.flatMap((account) => getPositionStates(account, chains, kinds));
  if (states.includes('notLoaded')) return 'not_loaded';
  if (states.includes('unavailable')) return 'failed_retryable';
  if (states.includes('stale')) return 'stale';
  return undefined;
}

export function positionStateLimitations(
  accounts: AgentV2HostAccount[],
  chains: readonly AgentApiChain[],
  kinds = POSITION_KINDS,
) {
  const states = accounts.flatMap((account) => getPositionStates(account, chains, kinds));
  return uniqueLimitations([
    ...(states.includes('stale') ? ['stale_data' as const] : []),
    ...(states.some((state) => state === 'notLoaded' || state === 'unavailable')
      ? ['source_partial' as const]
      : []),
  ]);
}

function availablePositionAccountCount(
  accounts: AgentV2HostAccount[],
  chains: readonly AgentApiChain[],
  kinds = POSITION_KINDS,
) {
  return accounts.filter((account) => getPositionStates(account, chains, kinds)
    .some((state) => state === 'fresh' || state === 'stale')).length;
}

function canonicalPositionStatus(value?: string): AgentWalletDataPositionRowV3['status'] | undefined {
  return value === 'active' || value === 'unstaking' || value === 'ready'
    || value === 'frozen' || value === 'locked' ? value : undefined;
}

const POSITION_KINDS: AgentV2PositionKind[] = ['fungible', 'nft', 'staking', 'vesting', 'vault'];
