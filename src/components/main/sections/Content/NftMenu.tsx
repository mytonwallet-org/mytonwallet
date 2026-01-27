import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiNft } from '../../../../api/types';
import type { IAnchorPosition } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';

import {
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectTonDnsLinkedAddress,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { stopEvent } from '../../../../util/domEvents';
import { vibrate } from '../../../../util/haptics';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { usePrevDuringAnimationSimple } from '../../../../hooks/usePrevDuringAnimationSimple';
import useNftMenu from '../../../mediaViewer/hooks/useNftMenu';

import DropdownMenu from '../../../ui/DropdownMenu';
import { ANIMATION_DURATION } from '../../../ui/Menu';

import styles from './NftMenu.module.scss';

interface OwnProps {
  nft: ApiNft;
  ref?: ElementRef<HTMLButtonElement>;
  isContextMenuMode?: boolean;
  dnsExpireInDays?: number;
  menuAnchor?: IAnchorPosition;
  className?: string;
  onOpen: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
  onCloseAnimationEnd?: NoneToVoidFunction;
}

interface StateProps {
  isViewMode: boolean;
  isTestnet?: boolean;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  cardBackgroundNft?: ApiNft;
  accentColorNft?: ApiNft;
  linkedAddress?: string;
}

const CONTEXT_MENU_VERTICAL_SHIFT_PX = 4;

function NftMenu({
  isViewMode,
  isTestnet,
  isContextMenuMode,
  nft,
  ref,
  dnsExpireInDays,
  linkedAddress,
  menuAnchor,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  cardBackgroundNft,
  accentColorNft,
  className,
  onOpen,
  onClose,
  onCloseAnimationEnd,
}: OwnProps & StateProps) {
  const isNftBlacklisted = useMemo(() => {
    return blacklistedNftAddresses?.includes(nft.address);
  }, [nft, blacklistedNftAddresses]);
  const isNftWhitelisted = useMemo(() => {
    return whitelistedNftAddresses?.includes(nft.address);
  }, [nft, whitelistedNftAddresses]);
  const isNftInstalled = usePrevDuringAnimationSimple(
    nft && nft.address === cardBackgroundNft?.address, ANIMATION_DURATION,
  );
  const isNftAccentColorInstalled = usePrevDuringAnimationSimple(
    nft && nft.address === accentColorNft?.address, ANIMATION_DURATION,
  );

  const { menuItems, handleMenuItemSelect } = useNftMenu({
    nft,
    isViewMode,
    dnsExpireInDays,
    linkedAddress,
    isNftBlacklisted,
    isNftWhitelisted,
    isNftInstalled,
    isNftAccentColorInstalled,
    isTestnet,
  });
  let buttonRef = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();
  const isOpen = Boolean(menuAnchor);
  if (ref) {
    buttonRef = ref;
  }

  const getTriggerElement = useLastCallback(() => buttonRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    topShiftY: isContextMenuMode ? CONTEXT_MENU_VERTICAL_SHIFT_PX : 0,
    preferredPositionX: isContextMenuMode ? 'left' : 'right',
  }));

  const lang = useLang();

  const handleButtonClick = (e: React.MouseEvent) => {
    stopEvent(e);

    if (isOpen) {
      onClose();
    } else {
      void vibrate();
      onOpen();
    }
  };

  return (
    <>
      <button
        ref={buttonRef}
        type="button"
        className={buildClassName(styles.button, className)}
        aria-label={lang('NFT Menu')}
        onClick={handleButtonClick}
      >
        <i className={buildClassName(styles.icon, 'icon-menu-dots')} aria-hidden />
      </button>
      <DropdownMenu
        isOpen={isOpen}
        ref={menuRef}
        withPortal
        menuAnchor={menuAnchor}
        menuPositionX="right"
        getTriggerElement={!isContextMenuMode ? getTriggerElement : undefined}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        items={menuItems}
        shouldTranslateOptions
        className={isContextMenuMode ? styles.contextMenu : styles.menu}
        bubbleClassName={styles.menuBubble}
        buttonClassName={styles.item}
        itemDescriptionClassName={styles.menuItemDescription}
        shouldCleanup
        onClose={onClose}
        onCloseAnimationEnd={onCloseAnimationEnd}
        onSelect={handleMenuItemSelect}
      />
    </>
  );
}

export default memo(withGlobal<OwnProps>((global, { nft }): StateProps => {
  const { blacklistedNftAddresses, whitelistedNftAddresses } = selectCurrentAccountState(global) || {};
  const { cardBackgroundNft, accentColorNft } = selectCurrentAccountSettings(global) || {};
  const linkedAddress = selectTonDnsLinkedAddress(global, nft);

  return {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    cardBackgroundNft,
    accentColorNft,
    isViewMode: selectIsCurrentAccountViewMode(global),
    isTestnet: global.settings.isTestnet,
    linkedAddress,
  };
})(NftMenu));
