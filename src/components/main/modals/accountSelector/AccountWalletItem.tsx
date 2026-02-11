import React, { type ElementRef, useRef } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { AccountBalance } from './hooks/useAccountsBalances';

import buildClassName from '../../../../util/buildClassName';
import { OPEN_CONTEXT_MENU_CLASS_NAME } from './constants';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLastCallback from '../../../../hooks/useLastCallback';
import useAccountContextMenu from './hooks/useAccountContextMenu';

import AccountRowInner from '../../../common/AccountRowInner';
import Draggable from '../../../ui/Draggable';
import DropdownMenu from '../../../ui/DropdownMenu';
import MenuBackdrop from '../../../ui/MenuBackdrop';

import accountRowStyles from '../../../common/AccountRowContent.module.scss';
import styles from './AccountWalletItem.module.scss';

interface OwnProps {
  isSelected: boolean;
  isTestnet?: boolean;
  accountId: string;
  byChain: Account['byChain'];
  accountType: AccountType;
  title?: string;
  balanceData?: AccountBalance;
  cardBackgroundNft?: ApiNft;
  withContextMenu?: boolean;
  isSensitiveDataHidden?: true;
  onClick: (accountId: string) => void;
  onRename: (accountId: string) => void;
  onReorder: NoneToVoidFunction;
  onLogOut: (accountId: string) => void;
  // Reorder mode props (optional)
  isReorder?: boolean;
  onDrag?: (translation: { x: number; y: number }, id: string | number) => void;
  onDragEnd?: NoneToVoidFunction;
  draggableStyle?: string;
  parentRef?: ElementRef<HTMLDivElement>;
  scrollRef?: ElementRef<HTMLDivElement>;
}

const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;

function AccountWalletItem({
  isSelected,
  isTestnet,
  accountId,
  byChain,
  accountType,
  title,
  balanceData,
  cardBackgroundNft,
  withContextMenu,
  isSensitiveDataHidden,
  onClick,
  onRename,
  onReorder,
  onLogOut,
  isReorder,
  onDrag,
  onDragEnd,
  draggableStyle,
  parentRef,
  scrollRef,
}: OwnProps) {
  const contentRef = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();

  const getTriggerElement = useLastCallback(() => contentRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    doNotCoverTrigger: isPortrait,
    // The shift is needed to prevent the mouse cursor from highlighting the first menu item
    topShiftY: !isPortrait ? CONTEXT_MENU_VERTICAL_SHIFT_PX : undefined,
    preferredPositionX: 'left',
  }));

  const handleRenameClick = useLastCallback(() => {
    onRename(accountId);
  });

  const handleRemoveClick = useLastCallback(() => {
    onLogOut(accountId);
  });

  const {
    isContextMenuOpen,
    isContextMenuShown,
    contextMenuAnchor,
    items,
    isBackdropRendered,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
    handleMenuItemSelect,
  } = useAccountContextMenu(contentRef, {
    isPortrait,
    withContextMenu,
    accountId,
    onReorderClick: onReorder,
    onRenameClick: handleRenameClick,
    onRemoveClick: handleRemoveClick,
  });

  const rowClassName = buildClassName(
    styles.item,
    isSelected && accountRowStyles.selected,
    isContextMenuOpen && OPEN_CONTEXT_MENU_CLASS_NAME,
    isReorder && styles.draggableItem,
  );

  const handleDraggableClick = useLastCallback((e: React.MouseEvent | React.TouchEvent) => {
    if (isReorder) return;

    onClick(accountId);
  });

  const handleDrag = useLastCallback((translation: { x: number; y: number }, id: string | number) => {
    onDrag?.(translation, id);
  });

  const handleDragEnd = useLastCallback(() => {
    onDragEnd?.();
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (isReorder) return;

    if (e.code === 'Enter' || e.code === 'Space') {
      e.preventDefault();
      onClick(accountId);
    }
  });

  const content = (
    <>
      <MenuBackdrop
        isMenuOpen={isBackdropRendered}
        contentRef={contentRef}
        contentClassName={styles.contentVisible}
      />
      <div
        ref={contentRef}
        className={buildClassName(accountRowStyles.row, rowClassName)}
        role="button"
        tabIndex={isSelected ? -1 : 0}
        onKeyDown={handleKeyDown}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
      >
        <AccountRowInner
          accountId={accountId}
          byChain={byChain}
          accountType={accountType}
          title={title}
          isTestnet={isTestnet}
          balanceData={balanceData}
          cardBackgroundNft={cardBackgroundNft}
          isSensitiveDataHidden={isSensitiveDataHidden}
        />
      </div>

      {withContextMenu && isContextMenuShown && (
        <DropdownMenu
          ref={menuRef}
          withPortal
          shouldTranslateOptions
          isOpen={isContextMenuOpen}
          items={items}
          menuAnchor={contextMenuAnchor}
          bubbleClassName={styles.verticalMenu}
          fontIconClassName={styles.menuIcon}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
          onSelect={handleMenuItemSelect}
          onClose={handleContextMenuClose}
          onCloseAnimationEnd={handleContextMenuHide}
        />
      )}
    </>
  );

  return (
    <Draggable
      key={accountId}
      id={accountId}
      style={draggableStyle}
      isDisabled={!isReorder}
      parentRef={parentRef}
      scrollRef={scrollRef}
      className={styles.draggable}
      onClick={handleDraggableClick}
      onDrag={handleDrag}
      onDragEnd={handleDragEnd}
    >
      {content}
    </Draggable>
  );
}

export default AccountWalletItem;
