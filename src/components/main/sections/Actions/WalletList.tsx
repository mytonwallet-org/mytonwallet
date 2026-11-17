import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo, useMemo, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import { type Account, AccountSelectorState, type GlobalState } from '../../../../global/types';

import {
  selectCurrentAccountId,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import getTestId from '../../../../util/getTestId';
import { getVisibleWallets } from './helpers/visibleWallets';
import { handleWalletMenuItemClick, WALLET_CONTEXT_MENU_ITEMS } from './helpers/walletMenu';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMultipleAccountsBalances } from '../../../../hooks/useMultipleAccountsBalances';

import AccountRowContent from '../../../common/AccountRowContent';
import SettingsWalletHeader from '../../../settings/SettingsWalletHeader';
import Button from '../../../ui/Button';
import WithContextMenu from '../../../ui/WithContextMenu';
import LogOutModal from '../../modals/LogOutModal';

import styles from './WalletList.module.scss';

type OwnProps = {
  /** Shows the current wallet as a header above the list of the other ones */
  isInSettings?: boolean;
};

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

// The shift is needed to prevent the mouse cursor from highlighting the first menu item
const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;
const CONTEXT_MENU_LAYOUT: Partial<Layout> = {
  doNotCoverTrigger: false,
  isCenteredHorizontally: false,
  topShiftY: CONTEXT_MENU_VERTICAL_SHIFT_PX,
  preferredPositionX: 'left',
};

function WalletList({
  isInSettings = false,
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
}: OwnProps & StateProps) {
  const { switchAccount, openAddAccountModal, openAccountSelector } = getActions();

  const lang = useLang();
  const [logOutAccountId, setLogOutAccountId] = useState<string>();

  const { visibleWallets, hasExcessWallets } = useMemo(() => (
    getVisibleWallets(orderedAccounts, currentAccountId, isInSettings)
  ), [orderedAccounts, currentAccountId, isInSettings]);

  // The header shows the balance of the current wallet, which is not in the list of the other ones
  const accountsWithBalance = useMemo(() => {
    const currentAccount = isInSettings && orderedAccounts.find(([accountId]) => accountId === currentAccountId);

    return currentAccount ? [currentAccount, ...visibleWallets] : visibleWallets;
  }, [isInSettings, orderedAccounts, currentAccountId, visibleWallets]);

  const { balancesByAccountId, addressLineChainsByAccountId } = useMultipleAccountsBalances({
    filteredAccounts: accountsWithBalance,
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

  const handleAddWalletClick = useLastCallback(() => {
    openAddAccountModal({
      initialState: AccountSelectorState.AddAccountInitial,
      shouldHideBackButton: true,
    });
  });

  const handleLogOutModalClose = useLastCallback(() => {
    setLogOutAccountId(undefined);
  });

  const buttonClassName = buildClassName(styles.item, styles.itemButton, isInSettings && styles.itemButtonInSettings);

  return (
    <>
      {isInSettings && currentAccountId && (
        <SettingsWalletHeader
          accountId={currentAccountId}
          balanceData={balancesByAccountId[currentAccountId]}
          onRemove={setLogOutAccountId}
        />
      )}

      <div className={buildClassName(styles.root, isInSettings && styles.rootInSettings)}>
        {visibleWallets.map(([accountId, { title, byChain, type, isRecoveryRequired }]) => (
          <WithContextMenu
            key={accountId}
            items={WALLET_CONTEXT_MENU_ITEMS}
            layout={CONTEXT_MENU_LAYOUT}
            menuClassName={styles.menu}
            fontIconClassName={styles.menuIcon}
            onItemClick={(value) => handleWalletMenuItemClick(value, accountId, setLogOutAccountId)}
          >
            {(menuProps, isMenuOpen) => (
              <AccountRowContent
                ref={menuProps.ref as ElementRef<HTMLDivElement>}
                accountId={accountId}
                byChain={byChain}
                visibleChains={addressLineChainsByAccountId?.[accountId]}
                accountType={type}
                title={title}
                isRecoveryRequired={isRecoveryRequired}
                isSelected={accountId === currentAccountId}
                balanceData={balancesByAccountId[accountId]}
                cardBackgroundNft={settingsByAccountId?.[accountId]?.cardBackgroundNft}
                isSensitiveDataHidden={isSensitiveDataHidden}
                className={buildClassName(styles.item, isMenuOpen && styles.itemActive)}
                avatarClassName={styles.itemAvatar}
                testId={getTestId(isInSettings ? 'settings_account_row' : 'wallet_switcher_account')}
                onClick={handleSwitchAccount}
                onMouseDown={menuProps.onMouseDown}
                onContextMenu={menuProps.onContextMenu}
              />
            )}
          </WithContextMenu>
        ))}

        {hasExcessWallets && (
          <Button
            isText
            className={buttonClassName}
            testId={isInSettings ? undefined : getTestId('wallet_switcher_manage')}
            onClick={openAccountSelector}
          >
            <i className={buildClassName(styles.itemIcon, 'icon-more-alt')} aria-hidden />
            {lang('Show All Wallets')}
          </Button>
        )}
        <Button
          isText
          className={buttonClassName}
          testId={getTestId(isInSettings ? 'settings_item_add_account' : 'wallet_switcher_add')}
          onClick={handleAddWalletClick}
        >
          <i className={buildClassName(styles.itemIcon, 'icon-plus')} aria-hidden />
          {lang('Add Wallet')}
        </Button>
      </div>

      <LogOutModal
        isOpen={Boolean(logOutAccountId)}
        targetAccountId={logOutAccountId}
        onClose={handleLogOutModalClose}
      />
    </>
  );
}

export default memo(withGlobal<OwnProps>(
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
)(WalletList));
