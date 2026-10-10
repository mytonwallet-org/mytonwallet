import type {
  AgentToolCall,
  AgentWalletDataQueryArgs,
  AgentWalletResolvedScopeV1,
} from './protocol/types';
import type { AgentV2HostAccount } from './types';
import type { WalletQueryAuthorityBinding, WalletQueryMaterializationScope } from './walletQueryTypes';
import type { AgentV2WalletSession } from './walletSession';

import { matchesPortfolioAccountFilter } from './walletQueryAccountFilter';
import { WalletQueryProjectionError } from './walletQueryErrors';
import { safeWalletQueryAccountLabel } from './walletQueryOutput';

export interface WalletQueryScopeDependencies {
  args: Exclude<AgentWalletDataQueryArgs, { operation: 'assets.search' }>;
  authorityBinding: WalletQueryAuthorityBinding;
  call: AgentToolCall;
  session: AgentV2WalletSession;
}

export type WalletQueryScopeResolution =
  | {
    kind: 'resolved';
    materializationScope: WalletQueryMaterializationScope;
    resolvedScope: AgentWalletResolvedScopeV1;
  }
  | {
    kind: 'required';
    reason: 'ambiguous' | 'not_found';
  };

export function resolveWalletQueryScope(
  dependencies: WalletQueryScopeDependencies,
): WalletQueryScopeResolution {
  assertScopeAuthority(dependencies);
  const snapshot = dependencies.session.snapshot();
  const host = snapshot.host;
  if (!host) throw unavailable();
  const selector = dependencies.args.accountSelector;
  const rawInventoryAccounts = host.accounts.slice(0, 100);
  const inventoryAccounts = filterPortfolioAccounts(rawInventoryAccounts, dependencies.args);
  const dataAccounts = inventoryAccounts.filter(({ state }) => state === 'active');
  const metadataOnlyInventory = dependencies.args.operation === 'account.inventory'
    && !dependencies.args.includePortfolioTotals;
  const accounts = metadataOnlyInventory ? inventoryAccounts : dataAccounts;
  const totalsInventory = dependencies.args.operation === 'account.inventory'
    && dependencies.args.includePortfolioTotals;
  if (!rawInventoryAccounts.length
    || (!inventoryAccounts.length && dependencies.args.operation === 'portfolio.aggregate')
    || (!accounts.length && (
      selector.kind !== 'explicitAll' || totalsInventory
    ))) {
    throw unavailable();
  }
  if (selector.kind === 'current') {
    const account = accounts.find(({ accountId }) => accountId === host.activeAccountId);
    if (!account) throw unavailable();
    return resolved('current', [account], snapshot.accountRefs);
  }
  if (selector.kind === 'explicitAll') {
    if (metadataOnlyInventory) return resolved('explicitAll', inventoryAccounts, snapshot.accountRefs);
    if (dependencies.args.operation === 'account.inventory') {
      return resolved('explicitAll', dataAccounts, snapshot.accountRefs);
    }
    return resolved('explicitAll', inventoryAccounts, snapshot.accountRefs, dataAccounts);
  }
  if (selector.kind === 'ordinal') {
    const account = accounts[selector.index - 1];
    if (!account) return required('not_found');
    return resolved('ordinal', [account], snapshot.accountRefs);
  }

  const exact = accounts.filter(({ label }) => normalizeLabel(label) === normalizeLabel(selector.label));
  if (exact.length === 1) {
    return resolved('named', exact, snapshot.accountRefs);
  }
  if (exact.length > 1) return required('ambiguous');
  return required('not_found');
}

function filterPortfolioAccounts(
  accounts: AgentV2HostAccount[],
  args: Exclude<AgentWalletDataQueryArgs, { operation: 'assets.search' }>,
): AgentV2HostAccount[] {
  const viewOnlyMode = args.operation === 'portfolio.aggregate'
    ? args.accountFilter?.viewOnly
    : undefined;
  if (args.operation !== 'portfolio.aggregate'
    || args.accountSelector.kind !== 'explicitAll'
    || !viewOnlyMode
    || viewOnlyMode === 'include') return accounts;
  return accounts.filter((account) => matchesPortfolioAccountFilter(account, args.accountFilter));
}

function assertScopeAuthority(dependencies: WalletQueryScopeDependencies) {
  const selector = dependencies.args.accountSelector;
  const expectedScope = selector.kind === 'current'
    ? 'current'
    : selector.kind === 'explicitAll' ? 'explicitAll' : 'selected';
  const { call } = dependencies;
  if (call.name !== 'wallet.data.query') throw invalidArguments();
  const context = call.walletContextSession;
  const authority = dependencies.authorityBinding;
  if (
    context.accountScope !== expectedScope
    || authority.accountScope !== expectedScope
    || context.activeAccountRef !== authority.activeAccountRef
    || context.revision !== authority.revision
    || context.sessionId !== authority.sessionId
  ) throw invalidArguments();
  if (
    expectedScope === 'explicitAll'
    && (
      call.scopeIntent?.reason !== 'explicit_all_wallet_query'
      || call.scopeIntent.messageId !== call.intentSource?.messageId
    )
  ) throw invalidArguments();
  if (
    expectedScope === 'selected'
    && (
      call.scopeIntent?.reason !== 'selected_wallet_query'
      || call.scopeIntent.messageId !== call.intentSource?.messageId
    )
  ) throw invalidArguments();
  if (expectedScope === 'current' && call.scopeIntent !== undefined) throw invalidArguments();
}

function resolved(
  kind: AgentWalletResolvedScopeV1['kind'],
  accounts: AgentV2HostAccount[],
  accountRefs: ReadonlyMap<string, string>,
  materializedAccounts: AgentV2HostAccount[] = accounts,
): Extract<WalletQueryScopeResolution, { kind: 'resolved' }> {
  const accountScope = kind === 'current' ? 'current'
    : kind === 'explicitAll' ? 'explicitAll' : 'selected';
  return {
    kind: 'resolved',
    materializationScope: {
      accountIds: materializedAccounts.map(({ accountId }) => accountId),
      accountScope,
      accountsRequested: accounts.length,
    },
    resolvedScope: {
      kind,
      accounts: accounts.map((account) => ({
        accountRef: requireAccountRef(accountRefs, account.accountId),
        accountLabel: safeWalletQueryAccountLabel(account),
      })),
    },
  };
}

function required(
  reason: 'ambiguous' | 'not_found',
): Extract<WalletQueryScopeResolution, { kind: 'required' }> {
  return { kind: 'required', reason };
}

function normalizeLabel(value?: string) {
  return sanitizeLabel(value).normalize('NFKC').toLocaleLowerCase('en-US');
}

function sanitizeLabel(value?: string) {
  return (value || 'Wallet').normalize('NFC').replace(/[\p{Cc}\p{Cf}]/gu, '')
    .replace(/\s+/gu, ' ').trim().slice(0, 80) || 'Wallet';
}

function requireAccountRef(refs: ReadonlyMap<string, string>, accountId: string) {
  const ref = refs.get(accountId);
  if (!ref) throw invalidArguments();
  return ref;
}

function invalidArguments() {
  return new WalletQueryProjectionError('invalid_arguments', 'The grounded wallet request is invalid.', false);
}

function unavailable() {
  return new WalletQueryProjectionError('stale_data_unavailable', 'Wallet data is unavailable.', true);
}
