import type { ApiBaseCurrency, ApiPriceHistoryPeriod } from '../../api/types';
import type { Account, GlobalState } from '../types';

import { parseAccountId } from '../../util/account';
import { getOrderedAccountChains } from '../../util/chain';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import memoize from '../../util/memoize';
import withCache from '../../util/withCache';
import { selectCurrentAccount, selectCurrentAccountId } from './accounts';

export function selectPortfolioHistoryBundle(
  global: GlobalState,
  accountId: string,
  baseCurrency: ApiBaseCurrency,
  range: ApiPriceHistoryPeriod,
) {
  return global.portfolio?.historyByAccountId?.[accountId]?.[baseCurrency]?.[range];
}

// The `accountId` parameter is unused inside the body but acts as the `withCache` key - it gives
// each account its own `memoize` so switching `A → B → A` keeps `A`'s cached result intact
const selectPortfolioMainnetWalletKeysMemoizedFor = withCache((accountId: string) => memoize((
  byChain: Account['byChain'],
): string[] => {
  const result: string[] = [];

  for (const chain of getOrderedAccountChains(byChain)) {
    const wallet = byChain[chain];
    if (wallet?.address) {
      result.push(`${chain}:${wallet.address}`);
    }
  }

  return result;
}));

export function selectPortfolioMainnetWalletKeys(global: GlobalState): string[] {
  const accountId = selectCurrentAccountId(global);
  if (!accountId) return MEMO_EMPTY_ARRAY;

  const { network } = parseAccountId(accountId);
  if (network !== 'mainnet') return MEMO_EMPTY_ARRAY;

  const byChain = selectCurrentAccount(global)?.byChain;
  if (!byChain) return MEMO_EMPTY_ARRAY;

  return selectPortfolioMainnetWalletKeysMemoizedFor(accountId)(byChain);
}
