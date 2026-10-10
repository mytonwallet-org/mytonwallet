import type { AgentWalletDataQueryResult } from './protocol/types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';

import { throwIfAborted } from '../../util/abortSignal';
import { buildAccounts, buildContacts } from './walletQueryAccounts';
import { invalid } from './walletQueryErrors';
import { buildValueSeries } from './walletQueryHistory';
import { buildPortfolio, buildPositionList } from './walletQueryPositions';
import { refreshPositions, resolveAccounts } from './walletQuerySources';
import { buildTransactionDetail, buildTransactionList } from './walletQueryTransactions';

export async function materializeWalletQuery(
  dependencies: WalletQueryMaterializationDependencies,
): Promise<Extract<AgentWalletDataQueryResult, { status: 'resolved' }>> {
  throwIfAborted(dependencies.signal);
  const { args } = dependencies;
  if (args.operation === 'assets.search') {
    throw invalid('Asset search belongs to the agent backend.');
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
    if (args.operation !== 'positions.list' || args.positionKinds.includes('fungible')) {
      accounts = await refreshPositions(dependencies, snapshot, accounts);
    }
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
