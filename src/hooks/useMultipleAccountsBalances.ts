import { useMemo } from '../lib/teact/teact';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingState,
} from '../api/types';
import type { Account, AccountSettings, GlobalState } from '../global/types';

import { IS_GRAM_WALLET } from '../config';
import {
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
} from '../global/selectors';
import { getAddressDisplayByChain } from '../util/formatAccountAddress';
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

  // The same accounts with `byChain` narrowed for address display (see `getAddressDisplayByChain`).
  // While no account is narrowed, the `filteredAccounts` identity survives so memoized consumers keep their cache.
  const displayedAccounts = useMemo(() => {
    if (!IS_GRAM_WALLET || !filteredAccounts) return filteredAccounts;

    let isNarrowed = false;
    const narrowed = filteredAccounts.map(([accountId, account]): [string, Account] => {
      const byChain = getAddressDisplayByChain(
        account.byChain,
        allAccountsTokens?.[accountId],
        allAccountsStakingStates?.[accountId],
      );
      if (byChain === account.byChain) return [accountId, account];

      isNarrowed = true;
      return [accountId, { ...account, byChain }];
    });

    return isNarrowed ? narrowed : filteredAccounts;
  }, [filteredAccounts, allAccountsTokens, allAccountsStakingStates]);

  const balances = useAccountsBalances(
    filteredAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  );

  return { ...balances, displayedAccounts };
}
