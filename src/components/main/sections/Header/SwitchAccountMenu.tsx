import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { Account, GlobalState, IAnchorPosition } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import { AccountSelectorState } from '../../../../global/types';

import {
  selectCurrentAccountId,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../../global/selectors';
import { getAccountTitle } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import { getTelegramAvatarUrlFromDomain } from '../../../../util/dns';
import { formatCurrency } from '../../../../util/formatNumber';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMultipleAccountsBalances } from '../../../../hooks/useMultipleAccountsBalances';

import Menu from '../../../ui/Menu';
import MenuItem from '../../../ui/MenuItem';
import SensitiveData from '../../../ui/SensitiveData';
import WalletAvatar from '../../../ui/WalletAvatar';

import styles from './SwitchAccountMenu.module.scss';

interface OwnProps {
  isOpen: boolean;
  anchor: IAnchorPosition;
  triggerRef: ElementRef<HTMLButtonElement>;
  onClose: NoneToVoidFunction;
  onCloseAnimationEnd: NoneToVoidFunction;
}

interface StateProps {
  currentAccountId: string;
  orderedAccounts: Array<[string, Account]>;
  networkAccounts?: Record<string, Account>;
  byAccountId: GlobalState['byAccountId'];
  tokenInfo: GlobalState['tokenInfo'];
  stakingDefault: ApiStakingState;
  currencyRates: ApiCurrencyRates;
  baseCurrency: ApiBaseCurrency;
  areTokensWithNoCostHidden?: boolean;
  settingsByAccountId: GlobalState['settings']['byAccountId'];
  isSensitiveDataHidden?: true;
}

const MAX_OTHER_ACCOUNTS = 9;
const MENU_LAYOUT: Layout = {
  withPortal: true,
  doNotCoverTrigger: true,
  isCenteredHorizontally: true,
};

function SwitchAccountMenu({
  isOpen,
  anchor,
  triggerRef,
  currentAccountId,
  orderedAccounts,
  networkAccounts,
  byAccountId,
  tokenInfo,
  stakingDefault,
  currencyRates,
  baseCurrency,
  areTokensWithNoCostHidden,
  settingsByAccountId,
  isSensitiveDataHidden,
  onClose,
  onCloseAnimationEnd,
}: OwnProps & StateProps) {
  const { openAccountSelector, openAddAccountModal, switchAccount } = getActions();

  const lang = useLang();
  const menuRef = useRef<HTMLDivElement>();

  const getTriggerElement = useLastCallback(() => triggerRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => MENU_LAYOUT);

  const currentAccount = networkAccounts?.[currentAccountId];

  const otherAccounts = useMemo(() => {
    return orderedAccounts
      .filter(([accountId]) => accountId !== currentAccountId)
      .slice(0, MAX_OTHER_ACCOUNTS);
  }, [orderedAccounts, currentAccountId]);

  const shownAccounts = useMemo(() => {
    return currentAccount
      ? [[currentAccountId, currentAccount] as [string, Account], ...otherAccounts]
      : otherAccounts;
  }, [currentAccountId, currentAccount, otherAccounts]);

  const { balancesByAccountId } = useMultipleAccountsBalances({
    filteredAccounts: shownAccounts,
    sourceAccounts: networkAccounts,
    byAccountId,
    tokenInfo,
    settingsByAccountId,
    areTokensWithNoCostHidden,
    baseCurrency,
    currencyRates,
    stakingDefault,
  });

  const handleManageWalletsClick = useLastCallback(() => {
    onClose();
    openAccountSelector();
  });

  const handleAccountClick = useLastCallback((_: React.SyntheticEvent, accountId: string) => {
    onClose();

    if (accountId !== currentAccountId) {
      switchAccount({ accountId });
    }
  });

  const handleAddWalletClick = useLastCallback(() => {
    onClose();
    openAddAccountModal({
      initialState: AccountSelectorState.AddAccountInitial,
      shouldHideBackButton: true,
    });
  });

  function renderAccount(accountId: string, account: Account) {
    const balance = balancesByAccountId[accountId];

    return (
      <MenuItem<string>
        key={accountId}
        className={styles.item}
        clickArg={accountId}
        onClick={handleAccountClick}
      >
        <WalletAvatar
          title={account.title}
          accountId={accountId}
          imageUrl={getTelegramAvatarUrlFromDomain(account.byChain.ton?.domain)}
          className={styles.accountAvatar}
        />
        <span className={styles.accountInfo}>
          <span className={styles.accountTitle}>{getAccountTitle(account)}</span>
          {balance && (
            <SensitiveData
              isActive={isSensitiveDataHidden}
              rows={2}
              cols={8}
              cellSize={6}
              className={styles.balance}
            >
              {formatCurrency(balance.value, balance.currencySymbol)}
            </SensitiveData>
          )}
        </span>
      </MenuItem>
    );
  }

  return (
    <Menu
      menuRef={menuRef}
      isOpen={isOpen}
      type="dropdown"
      withPortal
      bubbleClassName={styles.bubble}
      anchor={anchor}
      getTriggerElement={getTriggerElement}
      getRootElement={getRootElement}
      getMenuElement={getMenuElement}
      getLayout={getLayout}
      onClose={onClose}
      onCloseAnimationEnd={onCloseAnimationEnd}
    >
      <MenuItem<void> className={styles.item} onClick={handleManageWalletsClick}>
        <i className={buildClassName(styles.icon, 'icon-menu-dots')} aria-hidden />
        {lang('Manage Wallets')}
      </MenuItem>

      {currentAccount && (
        <>
          <div className={styles.separator} />
          <div className={styles.caption}>{lang('Current Wallet')}</div>
          {renderAccount(currentAccountId, currentAccount)}
        </>
      )}

      {Boolean(otherAccounts.length) && <div className={styles.separator} />}
      {otherAccounts.map(([accountId, account]) => renderAccount(accountId, account))}

      <div className={styles.separator} />
      <MenuItem<void> className={styles.item} onClick={handleAddWalletClick}>
        <i className={buildClassName(styles.icon, 'icon-menu-plus')} aria-hidden />
        {lang('Add Wallet')}
      </MenuItem>
    </Menu>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    byAccountId,
    currencyRates,
    stakingDefault,
    tokenInfo,
    settings: {
      byAccountId: settingsByAccountId,
      baseCurrency,
      areTokensWithNoCostHidden,
      isSensitiveDataHidden,
    },
  } = global;

  return {
    currentAccountId: selectCurrentAccountId(global)!,
    orderedAccounts: selectOrderedAccounts(global),
    networkAccounts: selectNetworkAccounts(global),
    byAccountId,
    tokenInfo,
    stakingDefault,
    currencyRates,
    baseCurrency,
    areTokensWithNoCostHidden,
    settingsByAccountId,
    isSensitiveDataHidden,
  };
})(SwitchAccountMenu));
