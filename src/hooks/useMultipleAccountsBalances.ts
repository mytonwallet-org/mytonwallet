import { useMemo } from '../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../api/types';
import type { MultipleAccountsBalances } from '../global/selectors';
import type { Account, AccountSettings, GlobalState } from '../global/types';

import {
  selectMultipleAccountsAddressLineChainsSlow,
  selectMultipleAccountsBalances,
  selectMultipleAccountsStakingStatesSlow,
} from '../global/selectors';

interface OwnProps {
  filteredAccounts: Array<[string, Account]> | undefined;
  sourceAccounts: Record<string, Account> | undefined;
  byAccountId: GlobalState['byAccountId'] | undefined;
  tokenInfo: GlobalState['tokenInfo'] | undefined;
  settingsByAccountId: Record<string, AccountSettings> | undefined;
  areTokensWithNoCostHidden: boolean | undefined;
  baseCurrency: ApiBaseCurrency | undefined;
  currencyRates: ApiCurrencyRates | undefined;
  stakingDefault: ApiStakingState | undefined;
}

const EMPTY_RESULT: MultipleAccountsBalances = { balancesByAccountId: {}, totalBalance: undefined };

export function useMultipleAccountsBalances({
  filteredAccounts,
  sourceAccounts,
  byAccountId,
  tokenInfo,
  settingsByAccountId,
  areTokensWithNoCostHidden,
  baseCurrency,
  currencyRates,
  stakingDefault,
}: OwnProps) {
  // Every derivation below is restricted to the accounts that are actually rendered, not to every wallet of
  // the network - a user may own many more
  const accounts = useMemo(() => {
    if (!filteredAccounts || !sourceAccounts) return undefined;

    const result: Record<string, Account> = {};
    for (const [accountId] of filteredAccounts) {
      const account = sourceAccounts[accountId];
      if (account) result[accountId] = account;
    }

    return result;
  }, [filteredAccounts, sourceAccounts]);

  const stakingStatesByAccountId = useMemo(() => {
    if (!accounts || !byAccountId || !stakingDefault) return undefined;

    return selectMultipleAccountsStakingStatesSlow(accounts, byAccountId, stakingDefault);
  }, [accounts, byAccountId, stakingDefault]);

  const addressLineChainsByAccountId = useMemo(() => {
    if (!accounts || !byAccountId || !tokenInfo || !settingsByAccountId || !stakingStatesByAccountId) {
      return undefined;
    }

    return selectMultipleAccountsAddressLineChainsSlow(
      accounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      areTokensWithNoCostHidden,
      stakingStatesByAccountId,
    );
  }, [accounts, byAccountId, tokenInfo, settingsByAccountId, areTokensWithNoCostHidden, stakingStatesByAccountId]);

  const balances = useMemo(() => {
    if (!accounts || !byAccountId || !tokenInfo || !settingsByAccountId
      || !stakingStatesByAccountId || !baseCurrency || !currencyRates) {
      return EMPTY_RESULT;
    }

    return selectMultipleAccountsBalances(
      Object.keys(accounts),
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      stakingStatesByAccountId,
      baseCurrency,
      currencyRates,
    );
  }, [accounts, byAccountId, tokenInfo, settingsByAccountId, stakingStatesByAccountId, baseCurrency, currencyRates]);

  return { ...balances, addressLineChainsByAccountId };
}
