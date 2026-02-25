import React, { type ElementRef, memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../api/types';
import { type Account, AccountSelectorState, type GlobalState } from '../../global/types';

import {
  selectCurrentAccountId,
  selectMultipleAccountsStakingStatesSlow,
  selectMultipleAccountsTokensSlow,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useAccountsBalances } from '../main/modals/accountSelector/hooks/useAccountsBalances';

import AccountInfo from '../common/AccountInfo';
import AccountRowContent from '../common/AccountRowContent';
import Button from '../ui/Button';

import styles from './Settings.module.scss';

type StateProps = {
  orderedAccounts: Array<[string, Account]>;
  networkAccounts?: Record<string, Account>;
  byAccountId: GlobalState['byAccountId'];
  tokenInfo: GlobalState['tokenInfo'];
  stakingDefault: ApiStakingState;
  currencyRates: ApiCurrencyRates;
  currentAccountId?: string;
  baseCurrency: ApiBaseCurrency;
  areTokensWithNoCostHidden?: boolean;
  settingsByAccountId: GlobalState['settings']['byAccountId'];
  isSensitiveDataHidden?: true;
};

type OwnProps = {
  currentWalletRef?: ElementRef<HTMLDivElement>;
  onAddAccount: NoneToVoidFunction;
};

const MAX_VISIBLE_WALLETS = 5;

const SettingsWallets = ({
  orderedAccounts,
  networkAccounts,
  byAccountId,
  tokenInfo,
  stakingDefault,
  currencyRates,
  currentAccountId,
  baseCurrency,
  areTokensWithNoCostHidden,
  settingsByAccountId,
  isSensitiveDataHidden,
  currentWalletRef,
  onAddAccount,
}: OwnProps & StateProps) => {
  const {
    switchAccount,
    openAddAccountModal,
  } = getActions();
  const lang = useLang();

  const allAccountsTokens = useMemo(() => (
    selectMultipleAccountsTokensSlow(
      networkAccounts,
      byAccountId,
      tokenInfo,
      settingsByAccountId,
      areTokensWithNoCostHidden,
      baseCurrency,
      currencyRates,
    )
  ), [
    networkAccounts,
    byAccountId,
    tokenInfo,
    currencyRates,
    baseCurrency,
    areTokensWithNoCostHidden,
    settingsByAccountId,
  ]);

  const allAccountsStakingStates = useMemo(() => (
    selectMultipleAccountsStakingStatesSlow(networkAccounts, byAccountId, stakingDefault)
  ), [networkAccounts, byAccountId, stakingDefault]);

  const { balancesByAccountId } = useAccountsBalances(
    orderedAccounts,
    allAccountsTokens,
    allAccountsStakingStates,
    baseCurrency,
    currencyRates,
  );

  const allAccountsExceptCurrent = useMemo(() => {
    return orderedAccounts.filter(([accountId]) => accountId !== currentAccountId);
  }, [orderedAccounts, currentAccountId]);

  const filteredAccounts = useMemo(() => {
    return allAccountsExceptCurrent.slice(0, MAX_VISIBLE_WALLETS);
  }, [allAccountsExceptCurrent]);

  const shouldShowAllWalletsButton = allAccountsExceptCurrent.length > MAX_VISIBLE_WALLETS;

  const handleAddWalletClick = useLastCallback(() => {
    onAddAccount();
    openAddAccountModal({
      initialState: AccountSelectorState.AddAccountInitial,
      shouldHideBackButton: true,
    });
  });

  const handleSwitchAccount = useLastCallback((accountId: string) => {
    switchAccount({ accountId });
  });

  return (
    <>
      <div ref={currentWalletRef} className={styles.currentWalletSection}>
        <AccountInfo balanceData={currentAccountId ? balancesByAccountId[currentAccountId] : undefined} />
      </div>

      <div className={styles.block}>
        {filteredAccounts.map(([accountId, { title, byChain, type }]) => (
          <AccountRowContent
            key={accountId}
            accountId={accountId}
            byChain={byChain}
            accountType={type}
            title={title}
            isSelected={accountId === currentAccountId}
            balanceData={balancesByAccountId[accountId]}
            cardBackgroundNft={settingsByAccountId?.[accountId]?.cardBackgroundNft}
            isSensitiveDataHidden={isSensitiveDataHidden}
            className={buildClassName(styles.item, styles.item_withWallet)}
            avatarClassName={styles.itemAvatarWallet}
            onClick={handleSwitchAccount}
          />
        ))}

        {shouldShowAllWalletsButton && (
          <Button
            isText
            className={buildClassName(styles.item, styles.itemButton)}
            onClick={openAddAccountModal}
          >
            <i className={buildClassName(styles.itemIcon, 'icon-menu-dots')} aria-hidden />
            {lang('Show All Wallets')}
          </Button>
        )}

        <Button
          isText
          className={buildClassName(styles.item, styles.itemButton)}
          onClick={handleAddWalletClick}
        >
          <i className={buildClassName(styles.itemIcon, styles.itemIcon_big, 'icon-plus')} aria-hidden />
          {lang('Add Wallet')}
        </Button>
      </div>
    </>
  );
};

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const orderedAccounts = selectOrderedAccounts(global);
  const networkAccounts = selectNetworkAccounts(global);

  const {
    baseCurrency,
    areTokensWithNoCostHidden,
    byAccountId: settingsByAccountId,
    isSensitiveDataHidden,
  } = global.settings;

  return {
    orderedAccounts,
    networkAccounts,
    byAccountId: global.byAccountId,
    tokenInfo: global.tokenInfo,
    stakingDefault: global.stakingDefault,
    currencyRates: global.currencyRates,
    currentAccountId,
    baseCurrency,
    areTokensWithNoCostHidden,
    settingsByAccountId,
    isSensitiveDataHidden,
  };
})(SettingsWallets));
