import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import { type Account, AccountSelectorState, type GlobalState } from '../../../../global/types';

import {
  selectCurrentAccountId,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMultipleAccountsBalances } from '../../../../hooks/useMultipleAccountsBalances';

import AccountRowContent from '../../../common/AccountRowContent';
import Button from '../../../ui/Button';

import styles from './LandscapeWalletList.module.scss';

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

const MAX_VISIBLE_WALLETS = 16;

function LandscapeWalletList({
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
}: StateProps) {
  const { switchAccount, openAddAccountModal, openAccountSelector } = getActions();

  const lang = useLang();

  const filteredAccounts = useMemo(() => {
    return orderedAccounts.slice(0, MAX_VISIBLE_WALLETS);
  }, [orderedAccounts]);

  const { balancesByAccountId } = useMultipleAccountsBalances({
    filteredAccounts,
    sourceAccounts: networkAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });

  const handleSwitchAccount = useLastCallback((accountId: string) => {
    switchAccount({ accountId });
  });

  const hasExcessWallets = orderedAccounts.length > MAX_VISIBLE_WALLETS;

  const handleAddWalletClick = useLastCallback(() => {
    openAddAccountModal({
      initialState: AccountSelectorState.AddAccountInitial,
      shouldHideBackButton: true,
    });
  });

  return (
    <div className={styles.root}>
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
          className={styles.item}
          avatarClassName={styles.itemAvatar}
          onClick={handleSwitchAccount}
        />
      ))}

      {hasExcessWallets && (
        <Button
          isText
          className={buildClassName(styles.item, styles.itemButton)}
          onClick={openAccountSelector}
        >
          <i className={buildClassName(styles.itemIcon, 'icon-more-alt')} aria-hidden />
          {lang('Show All Wallets')}
        </Button>
      )}
      <Button
        isText
        className={buildClassName(styles.item, styles.itemButton)}
        onClick={handleAddWalletClick}
      >
        <i className={buildClassName(styles.itemIcon, 'icon-plus')} aria-hidden />
        {lang('Add Wallet')}
      </Button>
    </div>
  );
}

export default memo(withGlobal(
  (global): StateProps => {
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
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(LandscapeWalletList));
