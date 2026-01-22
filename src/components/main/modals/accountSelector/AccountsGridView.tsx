import React, { memo, useEffect, useRef } from '../../../../lib/teact/teact';

import type { Account, AccountSettings, AccountType } from '../../../../global/types';
import type { AccountTab } from './constants';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';

import Transition from '../../../ui/Transition';
import AccountsEmptyState from './AccountsEmptyState';
import AccountWalletCard from './AccountWalletCard';

import styles from './AccountSelectorModal.module.scss';

interface OwnProps {
  isActive: boolean;
  isTestnet?: boolean;
  filteredAccounts: Array<[string, Account]>;
  activeTab: AccountTab;
  balancesByAccountId: Record<string, { wholePart: string; fractionPart?: string; currencySymbol: string }>;
  settingsByAccountId?: Record<string, AccountSettings>;
  currentAccountId: string;
  isSensitiveDataHidden?: true;
  onSwitchAccount: (accountId: string) => void;
  onRename: (accountId: string) => void;
  onReorder: NoneToVoidFunction;
  onLogOut: (accountId: string) => void;
  onScroll: (e: React.UIEvent<HTMLElement>) => void;
  onScrollInitialize: (scrollContainer: HTMLDivElement) => void;
}

function AccountsGridView({
  isActive,
  isTestnet,
  filteredAccounts,
  activeTab,
  balancesByAccountId,
  settingsByAccountId,
  currentAccountId,
  isSensitiveDataHidden,
  onSwitchAccount,
  onRename,
  onReorder,
  onLogOut,
  onScroll,
  onScrollInitialize,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();

  useEffect(() => {
    if (isActive && ref.current?.parentElement) {
      onScrollInitialize(ref.current.parentElement as HTMLDivElement);
    }
  }, [isActive, activeTab, onScrollInitialize]);

  function renderCard(
    accountId: string,
    byChain: Account['byChain'],
    accountType: AccountType,
    title?: string,
  ) {
    const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};
    const isActive = accountId === currentAccountId;
    const balanceData = balancesByAccountId[accountId];

    return (
      <AccountWalletCard
        key={accountId}
        isTestnet={isTestnet}
        accountId={accountId}
        byChain={byChain}
        accountType={accountType}
        isActive={isActive}
        title={title}
        balanceData={balanceData}
        cardBackgroundNft={cardBackgroundNft}
        withContextMenu={!IS_CORE_WALLET}
        isSensitiveDataHidden={isSensitiveDataHidden}
        onClick={onSwitchAccount}
        onRename={onRename}
        onReorder={onReorder}
        onLogOut={onLogOut}
      />
    );
  }

  return (
    <Transition
      shouldWrap
      isScrollOnWrap
      activeKey={activeTab}
      name="semiFade"
      slideClassName={buildClassName(styles.contentSlide, 'custom-scroll')}
      onScroll={onScroll}
    >
      {filteredAccounts.length === 0 ? (
        <AccountsEmptyState ref={ref} isActive={isActive} tab={activeTab} />
      ) : (
        <div
          ref={ref}
          className={buildClassName(styles.gridContainer, styles.container)}
        >
          {filteredAccounts.map(
            ([accountId, {
              title,
              byChain,
              type,
            }]) => {
              return renderCard(accountId, byChain, type, title);
            },
          )}
        </div>
      )}
    </Transition>
  );
}

export default memo(AccountsGridView);
