import React, { memo, useEffect, useRef } from '../../../../lib/teact/teact';

import type { Account, AccountSettings } from '../../../../global/types';
import type { AccountTab } from './constants';
import type { AccountBalance } from './hooks/useAccountsBalances';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { REM } from '../../../../util/windowEnvironment';

import Transition from '../../../ui/Transition';
import AccountsEmptyState from './AccountsEmptyState';
import AccountWalletItem from './AccountWalletItem';

import styles from './AccountSelectorModal.module.scss';

interface SortState {
  orderedAccountIds?: string[];
  dragOrderAccountIds?: string[];
  draggedIndex?: number;
}

interface OwnProps {
  isActive: boolean;
  isTestnet?: boolean;
  filteredAccounts: Array<[string, Account]>;
  activeTab: AccountTab;
  balancesByAccountId: Record<string, AccountBalance>;
  settingsByAccountId?: Record<string, AccountSettings>;
  currentAccountId: string;
  isSensitiveDataHidden?: true;
  onSwitchAccount: (accountId: string) => void;
  onRename: (accountId: string) => void;
  onReorder: NoneToVoidFunction;
  onLogOut: (accountId: string) => void;
  onScroll: (e: React.UIEvent<HTMLElement>) => void;
  onScrollInitialize: (scrollContainer: HTMLDivElement) => void;
  // Reorder mode
  isReorder?: boolean;
  sortState?: SortState;
  onDrag?: (translation: { x: number; y: number }, id: string | number) => void;
  onDragEnd?: NoneToVoidFunction;
}

export const ACCOUNT_HEIGHT_PX = 4 * REM;

function AccountsListView({
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
  isReorder,
  sortState,
  onDrag,
  onDragEnd,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();

  useEffect(() => {
    if (isActive && ref.current?.parentElement) {
      onScrollInitialize(ref.current.parentElement as HTMLDivElement);
    }
  }, [isActive, activeTab, onScrollInitialize]);

  // Precompute O(1) lookup maps to avoid O(n²) indexOf calls during reordering
  const orderedIndexMap = isReorder && sortState?.orderedAccountIds
    ? new Map(sortState.orderedAccountIds.map((id, idx) => [id, idx]))
    : undefined;
  const dragOrderIndexMap = isReorder && sortState?.dragOrderAccountIds
    ? new Map(sortState.dragOrderAccountIds.map((id, idx) => [id, idx]))
    : undefined;

  return (
    <Transition
      shouldWrap
      isScrollOnWrap
      activeKey={activeTab}
      name="semiFade"
      slideClassName={buildClassName(styles.contentSlide, 'custom-scroll', isReorder && 'capture-scroll')}
      onScroll={onScroll}
    >
      {filteredAccounts.length === 0 ? (
        <AccountsEmptyState ref={ref} isActive={isActive} tab={activeTab} />
      ) : (
        <div
          className={buildClassName(
            styles.listContainer,
            styles.sortableContainer,
            styles.container,
          )}
          style={buildStyle(`height: ${filteredAccounts.length * ACCOUNT_HEIGHT_PX}px`)}
          ref={ref}
        >
          {filteredAccounts.map(([accountId, {
            title,
            byChain,
            type,
          }], index) => {
            const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};
            const isCurrentAccount = accountId === currentAccountId;
            const balanceData = balancesByAccountId[accountId];

            let draggableStyle: string;
            if (isReorder && sortState) {
              const isDragged = sortState.draggedIndex === index;
              const lookupMap = isDragged ? orderedIndexMap : dragOrderIndexMap;
              const lookupIndex = lookupMap?.get(accountId);
              const top = lookupIndex !== undefined
                ? lookupIndex * ACCOUNT_HEIGHT_PX
                : index * ACCOUNT_HEIGHT_PX;
              draggableStyle = buildStyle(`top: ${top}px`);
            } else {
              const top = index * ACCOUNT_HEIGHT_PX;
              draggableStyle = buildStyle(`top: ${top}px`);
            }

            return (
              <AccountWalletItem
                key={accountId}
                isTestnet={isTestnet}
                accountId={accountId}
                byChain={byChain}
                accountType={type}
                isSelected={isCurrentAccount}
                title={title}
                balanceData={balanceData}
                cardBackgroundNft={cardBackgroundNft}
                withContextMenu={!IS_CORE_WALLET && !isReorder}
                isSensitiveDataHidden={isSensitiveDataHidden}
                onClick={onSwitchAccount}
                onRename={onRename}
                onReorder={onReorder}
                onLogOut={onLogOut}
                isReorder={isReorder}
                onDrag={onDrag}
                onDragEnd={onDragEnd}
                draggableStyle={draggableStyle}
                parentRef={ref}
                scrollRef={ref}
              />
            );
          })}
        </div>
      )}
    </Transition>
  );
}

export default memo(AccountsListView);
