import type { ApiBalanceBySlug, ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../api/types';
import type { AccountSettings, GlobalState } from '../types';

import { Big } from '../../lib/big.js';
import { calculateTotalBalanceValue } from '../../util/calculateFullBalance';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import memoize from '../../util/memoize';
import withCache from '../../util/withCache';
import { selectAccountTokenInfoMemoizedFor } from './tokens';

export interface AccountBalance {
  value: string;
  wholePart: string;
  fractionPart?: string;
  currencySymbol: string;
}

export interface MultipleAccountsBalances {
  balancesByAccountId: Record<string, AccountBalance>;
  totalBalance: string | undefined;
}

// Memoized per account: the total is recomputed only when this account's balances or staking, the token prices
// or the currency rate change. Other updates get the same object back, so a list row wrapped in `memo` skips its
// re-render. The total is summed straight from the raw balances, without building a sorted `UserToken` list.
const selectAccountBalanceMemoizedFor = withCache((_accountId: string) => memoize((
  balancesBySlug: ApiBalanceBySlug | undefined,
  tokenInfo: GlobalState['tokenInfo'],
  deletedSlugs: string[] | undefined,
  stakingStates: ApiStakingState[] | undefined,
  baseCurrencyRate: string,
  shortBaseSymbol: string,
): AccountBalance => {
  const {
    primaryValue: value,
    primaryWholePart: wholePart,
    primaryFractionPart: fractionPart,
  } = calculateTotalBalanceValue(balancesBySlug, tokenInfo, deletedSlugs, stakingStates, baseCurrencyRate);

  return { value, wholePart, fractionPart, currencySymbol: shortBaseSymbol };
}));

/**
 * The displayed balance of each given account, keyed by account id, plus their sum.
 *
 * `accountIds` must hold only the accounts the caller actually renders - a user may own many more wallets.
 */
export function selectMultipleAccountsBalances(
  accountIds: string[],
  byAccountId: GlobalState['byAccountId'],
  tokenInfo: GlobalState['tokenInfo'],
  settingsByAccountId: Record<string, AccountSettings>,
  stakingStatesByAccountId: Record<string, ApiStakingState[] | undefined>,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
): MultipleAccountsBalances {
  const baseCurrencyRate = currencyRates[baseCurrency];
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const balancesByAccountId: Record<string, AccountBalance> = {};
  let total = Big(0);

  for (const accountId of accountIds) {
    const balancesBySlug = byAccountId[accountId]?.balances?.bySlug;
    const balance = selectAccountBalanceMemoizedFor(accountId)(
      balancesBySlug,
      selectAccountTokenInfoMemoizedFor(accountId)(balancesBySlug, tokenInfo),
      settingsByAccountId[accountId]?.deletedSlugs,
      stakingStatesByAccountId[accountId],
      baseCurrencyRate,
      shortBaseSymbol,
    );
    balancesByAccountId[accountId] = balance;
    total = total.plus(balance.value);
  }

  return { balancesByAccountId, totalBalance: formatCurrency(total.toString(), shortBaseSymbol) };
}
