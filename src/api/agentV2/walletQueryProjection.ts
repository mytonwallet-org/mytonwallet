import type {
  AgentAssetSelector,
  AgentToolResultRequestV2,
  AgentWalletDataCoverage,
  AgentWalletDataQueryArgs,
  AgentWalletDataQueryResult,
  AgentWalletDataSeriesV1,
  AgentWalletFilterClauseV1,
  AgentWalletFilterSetV1,
} from './protocol/types';
import type { WalletQueryAuthorityBinding, WalletQueryMaterializationDependencies } from './walletQueryTypes';

import { sha256 } from '../common/utils';
import contractManifest from './generated/manifest.json';
import { WalletQueryProjectionError } from './walletQueryErrors';
import { materializeWalletQuery } from './walletQueryMaterializer';
import { resolveWalletQueryScope } from './walletQueryScope';

export interface WalletQueryProjectionV5Dependencies extends Omit<
  WalletQueryMaterializationDependencies,
  'args' | 'filterDigest' | 'resolvedScope' | 'scope'
> {
  args: AgentWalletDataQueryArgs;
  authorityBinding: WalletQueryAuthorityBinding;
}

export async function buildWalletQueryProjection(
  dependencies: WalletQueryProjectionV5Dependencies,
): Promise<AgentWalletDataQueryResult> {
  const args = canonicalArgs(dependencies.args);
  const filters = args.operation === 'transactions.list' ? args.filters : undefined;
  const filterDigest = filters ? await appliedFilterDigest(filters) : undefined;
  if (args.operation === 'assets.search') {
    return materializeWalletQuery({ ...dependencies, args });
  }
  const scope = resolveWalletQueryScope({
    args,
    authorityBinding: dependencies.authorityBinding,
    call: dependencies.call,
    session: dependencies.session,
  });
  if (scope.kind === 'required') {
    return {
      operation: args.operation,
      status: 'scope_resolution_required',
      reason: scope.reason,
    };
  }
  const result = await materializeWalletQuery({
    ...dependencies,
    args,
    filterDigest,
    resolvedScope: scope.resolvedScope,
    scope: scope.materializationScope,
  });
  validateMaterializedResult(args, result);
  return result;
}

function validateMaterializedResult(
  args: AgentWalletDataQueryArgs,
  result: Extract<AgentWalletDataQueryResult, { status: 'resolved' }>,
) {
  if (result.operation !== args.operation) throw invalidArguments();
  if (args.operation !== 'account.inventory' || result.operation !== 'account.inventory') return;
  let baseCurrency: string | undefined;
  let hasIncompleteTotal = false;
  for (const row of result.accounts) {
    if (args.includePortfolioTotals) {
      if (row.state !== 'active' || !row.portfolioTotalStatus) throw invalidArguments();
      if (row.portfolioTotalStatus === 'unavailable') {
        if (row.portfolioTotal) throw invalidArguments();
        hasIncompleteTotal = true;
      } else {
        if (!row.portfolioTotal || !/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(row.portfolioTotal.value)) {
          throw invalidArguments();
        }
        if (baseCurrency && row.portfolioTotal.baseCurrency !== baseCurrency) throw invalidArguments();
        baseCurrency = row.portfolioTotal.baseCurrency;
        hasIncompleteTotal ||= row.portfolioTotalStatus === 'partial'
          || row.portfolioTotal.unpricedCount > 0;
      }
    } else if (row.portfolioTotalStatus || row.portfolioTotal) {
      throw invalidArguments();
    }
  }
  if (args.includePortfolioTotals && hasIncompleteTotal && result.coverage.status === 'complete') {
    throw invalidArguments();
  }
}

export function fitWalletQueryV5Request(
  request: AgentToolResultRequestV2,
  maxResultBytes: number,
) {
  if (request.status !== 'success' || request.toolName !== 'wallet.data.query') return request;
  const result = request.result.result;
  while (serializedByteLength(request) > maxResultBytes && removeLowestPriorityItem(result)) {
    if ('coverage' in result) markCoverageTrimmed(result.coverage);
  }
  return request;
}

function canonicalArgs(args: AgentWalletDataQueryArgs): AgentWalletDataQueryArgs {
  const canonical = cloneJson(args);
  if (canonical.operation === 'transactions.list') {
    canonical.filters = canonicalFilterSet(canonical.filters);
  }
  return canonical;
}

function canonicalFilterSet(filters: AgentWalletFilterSetV1): AgentWalletFilterSetV1 {
  if (filters.catalogDigest !== contractManifest.walletFilterCatalogSha256) throw invalidArguments();
  const order: AgentWalletFilterClauseV1['field'][] = [
    'transaction.status',
    'transaction.direction',
    'transaction.timestamp',
    'transaction.chain',
    'transaction.asset',
  ];
  const seen = new Set<string>();
  const clauses = filters.clauses.map((clause) => {
    if (seen.has(clause.field)) throw invalidArguments();
    seen.add(clause.field);
    if (clause.field === 'transaction.timestamp') {
      if (Date.parse(clause.range.fromInclusive) >= Date.parse(clause.range.toExclusive)) {
        throw invalidArguments();
      }
      return cloneJson(clause);
    }
    if (clause.field === 'transaction.asset') {
      return {
        ...cloneJson(clause),
        values: clause.values.map(canonicalAssetSelector)
          .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right))),
      };
    }
    return {
      ...cloneJson(clause),
      values: [...clause.values].sort(),
    } as AgentWalletFilterClauseV1;
  }).sort((left, right) => order.indexOf(left.field) - order.indexOf(right.field));
  return { schemaVersion: 1, catalogDigest: filters.catalogDigest, clauses };
}

function canonicalAssetSelector(selector: AgentAssetSelector): AgentAssetSelector {
  return {
    ...(selector.slug ? { slug: selector.slug } : {}),
    ...(selector.chain ? { chain: selector.chain } : {}),
    ...(selector.tokenAddress ? { tokenAddress: selector.tokenAddress } : {}),
    ...(selector.symbol ? { symbol: selector.symbol.toLocaleUpperCase('en-US') } : {}),
  };
}

async function appliedFilterDigest(filters: AgentWalletFilterSetV1) {
  return sha256Hex(canonicalJson(filters));
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(sortJsonValue(value));
}

function sortJsonValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortJsonValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, child]) => child !== undefined)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, sortJsonValue(child)]),
    );
  }
  return value;
}

async function sha256Hex(value: string) {
  const digest = await sha256(new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function removeLowestPriorityItem(result: AgentWalletDataQueryResult) {
  if (result.status === 'scope_resolution_required') return false;
  switch (result.operation) {
    case 'account.inventory':
      return Boolean(result.accounts.pop());
    case 'assets.search':
      if (result.assets.length <= (result.resolution === 'ambiguous' ? 2 : result.resolution === 'unique' ? 1 : 0)) {
        return false;
      }
      result.assets.pop();
      return true;
    case 'positions.list':
      return Boolean(result.positions.pop());
    case 'portfolio.aggregate':
      return removeSeriesPoint(result.series)
        || Boolean(result.series.pop())
        || Boolean(result.aggregates.pop())
        || Boolean(result.allocations.pop())
        || Boolean(result.positions.pop());
    case 'transactions.list':
      return Boolean(result.transactions.pop());
    case 'transactions.detail':
      return false;
    case 'contacts.list':
      return Boolean(result.contacts.pop());
    case 'value.series':
      return removeSeriesPoint(result.series) || Boolean(result.series.pop());
  }
}

function removeSeriesPoint(series: AgentWalletDataSeriesV1[]) {
  const candidate = [...series].reverse().find(({ points }) => points.length > 1);
  if (!candidate) return false;
  candidate.points.splice(Math.max(1, candidate.points.length - 2), 1);
  return true;
}

function markCoverageTrimmed(coverage: AgentWalletDataCoverage) {
  coverage.status = 'partial';
  delete coverage.emptyReason;
  coverage.rowsOmitted += 1;
  if (!coverage.limitations.includes('row_limit') && coverage.limitations.length < 8) {
    coverage.limitations.push('row_limit');
  }
}

function serializedByteLength(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function invalidArguments() {
  return new WalletQueryProjectionError('invalid_arguments', 'The wallet filters are invalid.', false);
}
