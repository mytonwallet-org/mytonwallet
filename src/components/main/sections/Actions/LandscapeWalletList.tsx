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
import { handleWalletMenuItemClick, WALLET_CONTEXT_MENU_ITEMS } from './helpers/walletMenu';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMultipleAccountsBalances } from '../../../../hooks/useMultipleAccountsBalances';

import AccountRowContent from '../../../common/AccountRowContent';
import Button from '../../../ui/Button';
import WithContextMenu from '../../../ui/WithContextMenu';
import LogOutModal from '../../modals/LogOutModal';

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
// The shift is needed to prevent the mouse cursor from highlighting the first menu item
const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;
const CONTEXT_MENU_LAYOUT: Partial<Layout> = {
  doNotCoverTrigger: false,
  isCenteredHorizontally: false,
  topShiftY: CONTEXT_MENU_VERTICAL_SHIFT_PX,
  preferredPositionX: 'left',
};

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
  const [logOutAccountId, setLogOutAccountId] = useState<string>();

  const filteredAccounts = useMemo(() => {
    return orderedAccounts.slice(0, MAX_VISIBLE_WALLETS);
  }, [orderedAccounts]);

  const { balancesByAccountId, addressLineChainsByAccountId } = useMultipleAccountsBalances({
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

  const handleLogOutModalClose = useLastCallback(() => {
    setLogOutAccountId(undefined);
  });

  return (
    <>
      <div className={styles.root}>
        {filteredAccounts.map(([accountId, { title, byChain, type }]) => (
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
                isSelected={accountId === currentAccountId}
                balanceData={balancesByAccountId[accountId]}
                cardBackgroundNft={settingsByAccountId?.[accountId]?.cardBackgroundNft}
                isSensitiveDataHidden={isSensitiveDataHidden}
                className={buildClassName(styles.item, isMenuOpen && styles.itemActive)}
                avatarClassName={styles.itemAvatar}
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

      <LogOutModal
        isOpen={Boolean(logOutAccountId)}
        targetAccountId={logOutAccountId}
        onClose={handleLogOutModalClose}
      />
    </>
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
