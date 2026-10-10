import type { ApiActivity, ApiChain } from '../types';
import type {
  AgentApiChain,
  AgentWalletDataQueryArgs,
  AgentWalletDataQueryResult,
  AgentWalletDataTransactionRowV3,
  AgentWalletFilterSetV1,
  AgentWalletResolvedScopeV1,
  AgentWalletTransactionAmountV1,
} from './protocol/types';
import type { AgentV2HostAccount } from './types';
/* eslint-disable no-null/no-null -- The public detail result uses null when no exact transaction is available. */
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';
import type { AgentV2WalletSessionSnapshot } from './walletSession';

import { getActivityChains, STAKING_TRANSACTION_TYPES } from '../../util/activities';
import { toDecimal } from '../../util/decimals';
import { findNativeToken, getChainBySlug } from '../../util/tokens';
import { matchesSelector, resolveAsset } from './walletQueryAssets';
import { absoluteDecimal, canonicalDecimal, isCanonicalDecimal, isZeroDecimal } from './walletQueryDecimal';
import { unavailable } from './walletQueryErrors';
import { MAX_ACTIVITY_ACCOUNTS, MAX_ACTIVITY_CONCURRENCY, SOURCE_RETRY_ATTEMPTS } from './walletQueryLimits';
import {
  makeCoverage,
  maskIdentifier,
  nftSensitiveIdentifiers,
  projectAsset,
  requestedAccountCount,
  requireAccountRef,
  resolvedBase,
  safeHumanDisplay,
  safeWalletQueryAccountLabel,
  safeWalletQueryAssetSymbol,
  safeWalletQueryIdentifierDisplay,
  sanitizeText,
  uniqueLimitations,
} from './walletQueryOutput';
import { matchesRisk } from './walletQueryPositions';
import { canonicalTransactionSourceRowId } from './walletQueryRowId';
import {
  activityHasTransactionHash,
  getTransactionHashes,
  loadTransactionDetail,
  mapWithConcurrency,
  scanTransactionAccount,
} from './walletQuerySources';

export async function buildTransactionList(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'transactions.list' }>,
): Promise<Extract<AgentWalletDataQueryResult, { operation: 'transactions.list' }>> {
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

export async function buildTransactionDetail(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'transactions.detail' }>,
): Promise<Extract<AgentWalletDataQueryResult, { operation: 'transactions.detail' }>> {
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
      activity = await loadTransactionDetail(dependencies, match.account, match.activity, args.hash);
      detailFailed = !activity;
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

function getPrimaryChain(activity: ApiActivity): AgentApiChain {
  if (activity.kind === 'transaction') return getChainBySlug(activity.slug);
  return getActivityChains(activity)[0] ?? getChainBySlug(activity.from);
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
