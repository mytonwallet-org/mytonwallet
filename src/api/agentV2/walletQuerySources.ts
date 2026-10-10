import type { ApiActivity } from '../types';
import type { AgentToolCall, AgentWalletAccountFilterV1 } from './protocol/types';
import type { AgentV2HostAccount } from './types';
import type {
  FetchPastActivities,
  RefreshWalletHoldings,
  TransactionScanOutcome,
  WalletQueryMaterializationDependencies,
  WalletQueryMaterializationScope,
} from './walletQueryTypes';
import type { AgentV2WalletSessionSnapshot } from './walletSession';

import { raceWithAbortSignal, throwIfAborted } from '../../util/abortSignal';
import { parseTxId } from '../../util/activities';
import { toDecimal } from '../../util/decimals';
import { matchesPortfolioAccountFilter } from './walletQueryAccountFilter';
import { Decimal } from './walletQueryDecimal';
import {
  invalid,
  isRetryableWalletSourceError,
  WalletQueryProjectionError,
} from './walletQueryErrors';
import {
  MAX_ACTIVITY_BATCH,
  MAX_ACTIVITY_SCAN_PER_ACCOUNT,
  SOURCE_RETRY_ATTEMPTS,
} from './walletQueryLimits';
import { transactionHashesEqual } from './walletQueryTransactionHash';

export async function refreshPositions(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
) {
  const stale = accounts.filter(({ domainStates }) => domainStates?.fungible?.state !== 'fresh');
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
      domainStates: { ...account.domainStates, fungible: { state, updatedAt: dependencies.completedAt } },
    };
  });
}

export async function scanTransactionAccount(
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

export async function loadTransactionDetail(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  activity: ApiActivity,
  hash: string,
): Promise<ApiActivity | undefined> {
  try {
    const enriched = await raceWithAbortSignal(
      () => dependencies.fetchActivityDetails!(account.accountId, activity, dependencies.signal),
      dependencies.signal,
    );
    await assertCurrentAuthority(dependencies);
    return activityHasTransactionHash(enriched, hash) ? enriched : undefined;
  } catch (error) {
    if (dependencies.signal.aborted) throw dependencies.signal.reason ?? error;
    if (error instanceof WalletQueryProjectionError) throw error;
    if (!isRetryableWalletSourceError(error)) throw error;
    await assertCurrentAuthority(dependencies);
    return undefined;
  }
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

export function resolveAccounts(
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

export function getTransactionHashes(activity: ApiActivity) {
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

export function activityHasTransactionHash(activity: ApiActivity, hash: string) {
  return getTransactionHashes(activity).some((candidate) => (
    candidate !== undefined && transactionHashesEqual(candidate, hash)
  ));
}

export async function mapWithConcurrency<Input, Output>(
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
