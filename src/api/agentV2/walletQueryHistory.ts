import type {
  AgentWalletDataQueryArgs,
  AgentWalletDataQueryResult,
  AgentWalletResolvedScopeV1,
} from './protocol/types';
import type { AgentV2HostAccount } from './types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';
import type { AgentV2WalletSessionSnapshot } from './walletSession';

import { resolveRequestedAsset } from './walletQueryAssets';
import {
  makeCoverage, projectAsset, requestedAccountCount, requireAccountRef, resolvedBase,
} from './walletQueryOutput';

export function buildValueSeries(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'value.series' }>,
): Extract<AgentWalletDataQueryResult, { operation: 'value.series' }> {
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'value_series',
      accountsRequested: requestedAccountCount(dependencies, accounts),
      accountsIncluded: accounts.length,
      rowsOmitted: 0,
      limitations: [],
      rowCount: accounts.length,
    })),
    operation: 'value.series',
    baseCurrency: snapshot.host!.baseCurrency,
    historyAccounts: accounts.map((account) => {
      const asset = args.metric === 'position_value'
        ? resolveRequestedAsset(account, args.assetSelectors, args.chains) : undefined;
      return {
        accountRef: requireAccountRef(snapshot, account),
        wallets: [...new Set(account.portfolioWalletKeys ?? [])],
        ...(asset ? { asset: projectAsset(asset) } : {}),
      };
    }),
    series: [],
  };
}
