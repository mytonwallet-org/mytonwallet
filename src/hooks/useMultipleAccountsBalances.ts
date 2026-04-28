import { useMemo } from '../lib/teact/teact';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingState,
} from '../api/types';
import type { Account, AccountSettings, GlobalState } from '../global/types';

import {
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
} from '../global/selectors';
import { useAccountsBalances } from './useAccountsBalances';

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
  const allAccountsTokens = useMemo(() => {
    if (!sourceAccounts || !byAccountId || !tokenInfo || !settingsByAccountId || !baseCurrency || !currencyRates) {
      return undefined;
    }

    return selectMultipleAccountsTokensSlow(
      sourceAccounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    );
  }, [
    sourceAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
  ]);

  const allAccountsStakingStates = useMemo(() => {
    if (!sourceAccounts || !byAccountId || !stakingDefault) return undefined;

    return selectMultipleAccountsStakingStatesSlow(sourceAccounts, byAccountId, stakingDefault);
  }, [sourceAccounts, byAccountId, stakingDefault]);

  return useAccountsBalances(
    filteredAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  );
}
