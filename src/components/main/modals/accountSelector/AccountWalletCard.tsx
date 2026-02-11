import React, { useLayoutEffect, useRef } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';

import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { formatAccountAddresses } from '../../../../util/formatAccountAddress';
import { OPEN_CONTEXT_MENU_CLASS_NAME } from './constants';

import { useCachedImage } from '../../../../hooks/useCachedImage';
import useCardCustomization from '../../../../hooks/useCardCustomization';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useFontScale from '../../../../hooks/useFontScale';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useWindowSize from '../../../../hooks/useWindowSize';
import useAccountContextMenu from './hooks/useAccountContextMenu';

import DropdownMenu from '../../../ui/DropdownMenu';
import MenuBackdrop from '../../../ui/MenuBackdrop';
import SensitiveData from '../../../ui/SensitiveData';
import getSensitiveDataMaskSkinFromCardNft from '../../sections/Card/helpers/getSensitiveDataMaskSkinFromCardNft';

import styles from './AccountWalletCard.module.scss';

interface OwnProps {
  isActive: boolean;
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
}

const CONTEXT_MENU_VERTICAL_SHIFT_PX = 6;
const NARROW_SCREEN_WIDTH_PX = 374;

function AccountWalletCard({
  isActive,
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
}: OwnProps) {
  const lang = useLang();
  const balanceRef = useRef<HTMLDivElement>();
  const contentRef = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const { updateFontScale } = useFontScale(balanceRef);

  // Screen width affects font size only in portrait orientation
  const screenWidthDep = isPortrait ? screenWidth : 0;
  const isHardware = accountType === 'hardware';
  const isViewMode = accountType === 'view';
  const isNarrowScreen = screenWidth < NARROW_SCREEN_WIDTH_PX;
  const formattedAddress = formatAccountAddresses(byChain, isNarrowScreen ? 'cardNarrow' : 'card');

  const {
    backgroundImageUrl,
    withTextGradient,
    classNames: mtwCardClassNames,
  } = useCardCustomization(cardBackgroundNft);
  const { imageUrl } = useCachedImage(backgroundImageUrl);
  const sensitiveDataMaskSkin = getSensitiveDataMaskSkinFromCardNft(cardBackgroundNft);

  const handleRenameClick = useLastCallback(() => {
    onRename(accountId);
  });

  const handleRemoveClick = useLastCallback(() => {
    onLogOut(accountId);
  });

  const getTriggerElement = useLastCallback(() => contentRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    doNotCoverTrigger: isPortrait,
    // The shift is needed to prevent the mouse cursor from highlighting the first menu item
    topShiftY: !isPortrait ? CONTEXT_MENU_VERTICAL_SHIFT_PX : undefined,
    preferredPositionX: 'left',
    isCenteredHorizontally: true,
  }));

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

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      e.preventDefault();
      onClick(accountId);
    }
  });

  useLayoutEffect(() => {
    if (balanceData?.wholePart !== undefined) {
      updateFontScale();
    }
  }, [balanceData, updateFontScale, screenWidthDep]);

  const buttonClassName = buildClassName(
    styles.button,
    isActive && styles.current,
    imageUrl && styles.customCard,
    imageUrl && mtwCardClassNames,
    isContextMenuOpen && OPEN_CONTEXT_MENU_CLASS_NAME,
  );

  return (
    <div className={styles.wrapper}>
      <MenuBackdrop
        isMenuOpen={isBackdropRendered}
        contentRef={contentRef}
        contentClassName={styles.contentVisible}
      />
      <div ref={contentRef} className={styles.content}>
        <div
          style={buildStyle(imageUrl && `--bg: url(${imageUrl})`)}
          className={buttonClassName}
          aria-label={lang('Switch Account')}
          role="button"
          tabIndex={isActive ? -1 : 0}
          aria-disabled={isActive}
          onKeyDown={handleKeyDown}
          onClick={() => onClick(accountId)}
          onMouseDown={handleBeforeContextMenu}
          onContextMenu={handleContextMenu}
        >
          {balanceData && (
            <SensitiveData
              isActive={isSensitiveDataHidden}
              rows={3}
              cols={12}
              cellSize={8}
              maskSkin={sensitiveDataMaskSkin}
              maskClassName={styles.balanceMask}
              className={styles.balanceWrapper}
              contentClassName={styles.balanceContent}
              align="center"
            >
              <div
                ref={balanceRef}
                className={buildClassName(styles.accountBalance, 'rounded-font', withTextGradient && 'gradientText')}
              >
                {balanceData.currencySymbol.length === 1 && (
                  <span className={styles.currencySymbol}>{balanceData.currencySymbol}</span>
                )}
                <span>{balanceData.wholePart}</span>
                {balanceData.fractionPart && (
                  <span className={styles.fractionPart}>.{balanceData.fractionPart}</span>
                )}
                {balanceData.currencySymbol.length > 1 && (
                  <span className={styles.fractionPart}>&nbsp;{balanceData.currencySymbol}</span>
                )}
              </div>
            </SensitiveData>
          )}
          <div className={buildClassName(styles.accountAddressBlock, withTextGradient && 'gradientText')}>
            {isTestnet && <i className="icon-testnet" aria-hidden />}
            {isHardware && <i className="icon-ledger" aria-hidden />}
            {isViewMode && <i className="icon-eye-filled" aria-hidden />}
            <span>{formattedAddress}</span>
          </div>
          <i
            tabIndex={-1}
            className={buildClassName(styles.menuDots, 'icon-menu-dots')}
            aria-hidden
            onClick={handleContextMenu}
          />
        </div>
        {title && <div className={styles.accountName}>{title}</div>}
        {withContextMenu && isContextMenuShown && (
          <DropdownMenu
            ref={menuRef}
            withPortal
            shouldTranslateOptions
            isOpen={isContextMenuOpen}
            items={items}
            menuAnchor={contextMenuAnchor}
            bubbleClassName={styles.menu}
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
      </div>
    </div>
  );
}

export default AccountWalletCard;
