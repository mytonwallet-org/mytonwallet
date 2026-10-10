import type { ApiNft } from '../types';
import type {
  AgentAssetIdentityV2,
  AgentWalletDataCoverage,
  AgentWalletResolvedScopeV1,
  AgentWalletSourceOutcomeV1,
} from './protocol/types';
import type { AgentV2HostAccount, AgentV2HostAsset } from './types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';
import type { AgentV2WalletSessionSnapshot } from './walletSession';

import { shortenAddress } from '../../util/shortenAddress';
import { invalid } from './walletQueryErrors';
import { SOURCE_RETRY_ATTEMPTS } from './walletQueryLimits';

export function resolvedBase(
  dependencies: WalletQueryMaterializationDependencies,
  resolvedScope: AgentWalletResolvedScopeV1,
  coverage: AgentWalletDataCoverage,
  source: 'cache' | 'network' | 'mixed' = 'cache',
) {
  return {
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

export function makeCoverage(input: {
  domain: AgentWalletSourceOutcomeV1['domain'];
  sourceStatus?: AgentWalletSourceOutcomeV1['status'];
  accountsRequested: number;
  accountsIncluded: number;
  rowsOmitted: number;
  limitations: AgentWalletDataCoverage['limitations'];
  rowCount: number;
  attempts?: number;
}): AgentWalletDataCoverage {
  const limitations = uniqueLimitations([
    ...input.limitations,
    ...(input.accountsRequested > 0 && input.accountsIncluded === 0 ? ['source_unavailable' as const] : []),
    ...(input.accountsIncluded > 0 && input.accountsIncluded < input.accountsRequested
      ? ['source_partial' as const]
      : []),
  ]).slice(0, 8);
  const unavailableResult = input.accountsRequested > 0
    && input.accountsIncluded === 0
    && limitations.includes('source_unavailable')
    && input.rowCount === 0;
  const complete = input.accountsIncluded === input.accountsRequested
    && input.rowsOmitted === 0
    && limitations.length === 0;
  const status = unavailableResult ? 'unavailable' : complete ? 'complete' : 'partial';
  const sourceStatus = input.sourceStatus ?? (
    unavailableResult || limitations.includes('source_partial') ? 'failed_retryable'
      : limitations.includes('stale_data') ? 'stale'
        : input.rowCount === 0 && complete ? 'complete_empty'
          : input.rowCount === 0 ? 'not_loaded' : 'complete'
  );
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
        : sourceStatus === 'stale' ? { reason: 'stale_cache' as const }
          : sourceStatus === 'not_loaded' || sourceStatus === 'failed_terminal'
            ? { reason: 'unknown' as const } : {}),
    }],
  };
}

export function requestedAccountCount(
  dependencies: WalletQueryMaterializationDependencies,
  accounts: AgentV2HostAccount[],
) {
  return dependencies.scope?.accountsRequested ?? accounts.length;
}

function freshness(asOf: string, source: 'cache' | 'network' | 'mixed', isStale: boolean) {
  return { asOf, source, isStale };
}

export function projectAsset(asset: AgentV2HostAsset): AgentAssetIdentityV2 {
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

export function requireAccountRef(snapshot: AgentV2WalletSessionSnapshot, account: AgentV2HostAccount) {
  const accountRef = snapshot.accountRefs.get(account.accountId);
  if (!accountRef) throw invalid('A wallet account reference is unavailable.');
  return accountRef;
}

export function normalizeSearch(value: string) {
  return value.normalize('NFKC').trim().toLocaleLowerCase('en-US').replace(/\s+/gu, ' ');
}

export function sanitizeText(value: string, maxLength: number) {
  return value.normalize('NFC').replace(/[\p{Cc}\p{Cf}]/gu, '').replace(/\s+/gu, ' ')
    .trim().slice(0, maxLength) || 'Unknown';
}

export function maskIdentifier(value: string) {
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

export function safeHumanDisplay(
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

export function nftSensitiveIdentifiers(nft: ApiNft) {
  return [nft.address, nft.collectionAddress].filter((value): value is string => Boolean(value));
}

export function isBoundedText(value: string, maxLength: number) {
  const length = [...value].length;
  return length >= 1 && length <= maxLength;
}

export function uniqueLimitations<T extends AgentWalletDataCoverage['limitations'][number]>(values: T[]) {
  return [...new Set(values)];
}

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}
