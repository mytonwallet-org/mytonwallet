import React, { type ElementRef, useMemo, useRef } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';

import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { formatAccountAddresses } from '../../../../util/formatAccountAddress';
import getPseudoRandomNumber from '../../../../util/getPseudoRandomNumber';
import { getAvatarGradientColors } from './utils/getAvatarGradientColor';
import { getAvatarInitials } from './utils/getAvatarInitials';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLastCallback from '../../../../hooks/useLastCallback';
import useAccountContextMenu, { OPEN_CONTEXT_MENU_CLASS_NAME } from './hooks/useAccountContextMenu';

import Draggable from '../../../ui/Draggable';
import DropdownMenu from '../../../ui/DropdownMenu';
import MenuBackdrop from '../../../ui/MenuBackdrop';
import SensitiveData from '../../../ui/SensitiveData';
import CustomCardPreview from './CustomCardPreview';

import styles from './AccountWalletItem.module.scss';

interface OwnProps {
  isSelected: boolean;
  isTestnet?: boolean;
  accountId: string;
  byChain: Account['byChain'];
  accountType: AccountType;
  title?: string;
  balanceData?: {
    wholePart: string;
    fractionPart?: string;
    currencySymbol: string;
  };
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

  const isHardware = accountType === 'hardware';
  const isViewMode = accountType === 'view';
  const formattedAddress = formatAccountAddresses(byChain, 'list');

  const amountCols = useMemo(() => getPseudoRandomNumber(4, 12, title || ''), [title]);
  const fiatAmountCols = 5 + (amountCols % 6);

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

  const handleLogOutClick = useLastCallback(() => {
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
    onLogOutClick: handleLogOutClick,
  });

  const initials = getAvatarInitials(title);
  const gradientColors = getAvatarGradientColors(accountId);

  const itemClassName = buildClassName(
    styles.item,
    isSelected && styles.selected,
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
        className={itemClassName}
        role="button"
        tabIndex={isSelected ? -1 : 0}
        onKeyDown={handleKeyDown}
        onMouseDown={handleBeforeContextMenu}
        onContextMenu={handleContextMenu}
      >
        <div
          className={styles.avatar}
          style={buildStyle(`--start-color: ${gradientColors[0]}; --end-color: ${gradientColors[1]}`)}
        >
          {initials}
        </div>

        <div className={styles.info}>
          <div className={styles.titleRow}>
            <span className={styles.title}>{title}</span>
            {cardBackgroundNft && (
              <CustomCardPreview nft={cardBackgroundNft} className={styles.nftIndicator} />
            )}
          </div>
          <div className={styles.address}>
            {isTestnet && <i className={buildClassName(styles.icon, 'icon-testnet')} aria-hidden />}
            {isHardware && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
            {isViewMode && <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />}
            {formattedAddress}
          </div>
        </div>

        {balanceData && (
          <SensitiveData
            isActive={isSensitiveDataHidden}
            rows={2}
            cols={fiatAmountCols}
            cellSize={8}
            align="right"
          >
            <div className={buildClassName(styles.balance, 'rounded-font')}>
              {balanceData.currencySymbol.length === 1 && balanceData.currencySymbol}
              {balanceData.wholePart}
              {balanceData.fractionPart && (
                <>.{balanceData.fractionPart}</>
              )}
              {balanceData.currencySymbol.length > 1 && (
                <>&nbsp;{balanceData.currencySymbol}</>
              )}
            </div>
          </SensitiveData>
        )}
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
