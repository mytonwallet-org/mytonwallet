import type { ElementRef } from '../../../../../lib/teact/teact';
import React, { memo, useEffect, useRef, useState } from '../../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../../global';

import type { ApiChain } from '../../../../../api/types';
import type { Account } from '../../../../../global/types';
import type { IAnchorPosition } from '../../../../../global/types';
import type { Layout } from '../../../../../hooks/useMenuPosition';
import type { SubMenuPosition } from './calculateSubMenuPosition';
import type { AddressMenuItem } from './MenuItem';

import { selectCurrentAccount, selectCurrentAccountChainDisplay } from '../../../../../global/selectors';
import buildClassName from '../../../../../util/buildClassName';
import { getChainTitle } from '../../../../../util/chain';
import { copyTextToClipboard } from '../../../../../util/clipboard';
import { stopEvent } from '../../../../../util/domEvents';
import { shareUrl } from '../../../../../util/share';
import { shortenDomain } from '../../../../../util/shortenDomain';
import { getViewAccountUrl } from '../../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../../util/windowEnvironment';
import windowSize from '../../../../../util/windowSize';
import calculateSubMenuPosition from './calculateSubMenuPosition';
import { MOUSE_LEAVE_TIMEOUT } from './useAddressMenu';
import useDelayedAction from './useDelayedAction';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

import Menu from '../../../../ui/Menu';
import Portal from '../../../../ui/Portal';
import DomainMenuItem from './DomainMenuItem';
import MenuItem from './MenuItem';
import SafeTriangle from './SafeTriangle';
import ShareButton from './ShareButton';

import menuStyles from '../../../../ui/Dropdown.module.scss';
import styles from '../Card.module.scss';

interface OwnProps {
  isOpen: boolean;
  anchor?: IAnchorPosition;
  items: AddressMenuItem[];
  hiddenItems: AddressMenuItem[];
  menuRef: ElementRef<HTMLDivElement>;
  isTestnet?: boolean;
  onClose: NoneToVoidFunction;
  onExplorerClick: (chain: ApiChain, address: string) => void;
  onMouseEnter?: NoneToVoidFunction;
  onMouseLeave?: NoneToVoidFunction;
  getTriggerElement: () => HTMLElement | undefined | null;
  getRootElement: () => HTMLElement | undefined | null;
  getMenuElement: () => HTMLElement | undefined | null;
  getLayout: () => Layout;
}

interface StateProps {
  byChain?: Account['byChain'];
  visibleChains?: ApiChain[];
}

// Must match the `.chainItem` height in each pointer mode
const SUB_MENU_ROW_HEIGHT_PX = IS_TOUCH_ENV ? 56 : 54;
// Must match the `.allChainsMenuBubble` styles
const CHAINS_MENU_WIDTH_PX = 256;
const ALL_CHAINS_MENU_MAX_HEIGHT_PX = 420;
const ALL_CHAINS_MENU_MAX_HEIGHT_VH = 60;
// Must match the `.domainMenuBubble` max-width - the bubble grows with content up to it
const DOMAIN_MENU_MAX_WIDTH_PX = 256;
const DOMAIN_MENU_HEIGHT_PX = SUB_MENU_ROW_HEIGHT_PX * 2;
const ALL_CHAINS_LOGO_COUNT = 3;

function AddressMenu({
  isOpen,
  anchor,
  items,
  hiddenItems,
  menuRef,
  isTestnet,
  onClose,
  onExplorerClick,
  onMouseEnter,
  onMouseLeave,
  getTriggerElement,
  getRootElement,
  getMenuElement,
  getLayout,
  byChain,
  visibleChains,
}: OwnProps & StateProps) {
  const { showToast } = getActions();

  const lang = useLang();

  const [allChainsPosition, setAllChainsPosition] = useState<SubMenuPosition | undefined>();
  const [domainSubMenu, setDomainSubMenu] = useState<{ item: AddressMenuItem; position: SubMenuPosition }>();
  // The pointer position at the moment a sub-menu opens - its safe triangle starts from this point
  const lastMouseRef = useRef<IAnchorPosition>({ x: 0, y: 0 });

  const closeAllChainsMenu = useLastCallback(() => {
    setAllChainsPosition(undefined);
  });

  const closeDomainSubMenu = useLastCallback(() => {
    setDomainSubMenu(undefined);
  });

  const openAllChainsMenu = useLastCallback((rowEl: HTMLElement) => {
    closeDomainSubMenu();
    const menuHeight = Math.min(
      hiddenItems.length * SUB_MENU_ROW_HEIGHT_PX,
      windowSize.get().height * ALL_CHAINS_MENU_MAX_HEIGHT_VH / 100,
      ALL_CHAINS_MENU_MAX_HEIGHT_PX,
    );
    setAllChainsPosition(calculateSubMenuPosition(rowEl, CHAINS_MENU_WIDTH_PX, menuHeight, lang.isRtl));
  });

  // The close delay is a grace period, so a diagonal pointer path into a sub-menu survives crossing other rows;
  // the open delay filters out accidental hovers on the way to another row
  const [scheduleAllChainsClose, cancelAllChainsClose] = useDelayedAction(closeAllChainsMenu, MOUSE_LEAVE_TIMEOUT);
  const [scheduleDomainSubMenuClose, cancelDomainSubMenuClose] = useDelayedAction(
    closeDomainSubMenu,
    MOUSE_LEAVE_TIMEOUT,
  );
  const [scheduleAllChainsHoverOpen, cancelAllChainsHoverOpen] = useDelayedAction(
    openAllChainsMenu,
    MOUSE_LEAVE_TIMEOUT,
  );

  const scheduleSubMenusClose = useLastCallback(() => {
    scheduleAllChainsClose();
    scheduleDomainSubMenuClose();
  });

  const openDomainSubMenu = useLastCallback((rowEl: HTMLElement, item: AddressMenuItem) => {
    cancelDomainSubMenuClose();
    setDomainSubMenu({
      item,
      position: calculateSubMenuPosition(rowEl, DOMAIN_MENU_MAX_WIDTH_PX, DOMAIN_MENU_HEIGHT_PX, lang.isRtl),
    });
  });

  useEffect(() => {
    if (isOpen) return;

    cancelAllChainsHoverOpen();
    cancelAllChainsClose();
    cancelDomainSubMenuClose();
    setAllChainsPosition(undefined);
    setDomainSubMenu(undefined);
  }, [isOpen, cancelAllChainsClose, cancelAllChainsHoverOpen, cancelDomainSubMenuClose]);

  // The sub-menu holds an item snapshot - drop it only when its chain row is gone or its data actually changed.
  // The lists themselves get new references on every account data poll, so a plain reset would close the sub-menu
  // right after opening.
  useEffect(() => {
    if (!domainSubMenu) return;

    const { item } = domainSubMenu;
    const freshItem = items.concat(hiddenItems).find(({ chain }) => chain === item.chain);
    if (!freshItem || freshItem.address !== item.address || freshItem.domain !== item.domain) {
      setDomainSubMenu(undefined);
    }
  }, [items, hiddenItems, domainSubMenu]);

  // Without rows the `All Chains` menu unmounts, and a lingering position would keep
  // its safe triangle protecting an area with no menu in it
  useEffect(() => {
    if (!hiddenItems.length) {
      cancelAllChainsHoverOpen();
      setAllChainsPosition(undefined);
    }
  }, [hiddenItems, cancelAllChainsHoverOpen]);

  const handleItemClick = useLastCallback((value: string, kind: 'address' | 'domain', chain: ApiChain) => {
    const message = lang(
      kind === 'domain' ? '%chain% Domain Copied' : '%chain% Address Copied',
      { chain: getChainTitle(chain) },
    ) as string;
    showToast({
      message,
      icon: 'icon-copy',
    });
    void copyTextToClipboard(value);
    onClose();
  });

  const handleRowClick = useLastCallback((e: React.UIEvent<HTMLElement>, item: AddressMenuItem) => {
    lastMouseRef.current = getEventPosition(e);

    if (item.domain) {
      if (domainSubMenu?.item.chain === item.chain) {
        closeDomainSubMenu();
      } else {
        openDomainSubMenu(e.currentTarget, item);
      }
      return;
    }

    handleItemClick(item.address, 'address', item.chain);
  });

  // Opening a domain sub-menu from a main row replaces an open `All Chains` menu; a domain sub-menu
  // opened from an `All Chains` row keeps its parent, so the sub-menu row handlers do not close it
  const handleMainRowClick = useLastCallback((e: React.UIEvent<HTMLElement>, item: AddressMenuItem) => {
    if (item.domain) {
      closeAllChainsMenu();
    }
    handleRowClick(e, item);
  });

  const handleMainRowMouseEnter = useLastCallback((e: React.MouseEvent<HTMLElement>, item: AddressMenuItem) => {
    lastMouseRef.current = { x: e.clientX, y: e.clientY };

    if (item.domain) {
      openDomainSubMenu(e.currentTarget, item);
      closeAllChainsMenu();
    } else {
      scheduleSubMenusClose();
    }
  });

  const handleSubMenuRowMouseEnter = useLastCallback((e: React.MouseEvent<HTMLElement>, item: AddressMenuItem) => {
    lastMouseRef.current = { x: e.clientX, y: e.clientY };

    if (item.domain) {
      openDomainSubMenu(e.currentTarget, item);
    } else {
      scheduleDomainSubMenuClose();
    }
  });

  const handleRowExplorerClick = useLastCallback((e: React.UIEvent<HTMLElement>, item: AddressMenuItem) => {
    stopEvent(e);
    onClose();
    onExplorerClick(item.chain, item.address);
  });

  const toggleAllChainsMenu = useLastCallback((rowEl: HTMLElement) => {
    cancelAllChainsHoverOpen();
    cancelAllChainsClose();

    if (allChainsPosition) {
      closeAllChainsMenu();
    } else {
      openAllChainsMenu(rowEl);
    }
  });

  const handleAllChainsClick = useLastCallback((e: React.MouseEvent<HTMLElement>) => {
    lastMouseRef.current = { x: e.clientX, y: e.clientY };
    toggleAllChainsMenu(e.currentTarget);
  });

  const handleAllChainsKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLElement>) => {
    if (e.code !== 'Enter' && e.code !== 'Space') return;

    // Space scrolls the page by default
    if (e.code === 'Space') e.preventDefault();

    lastMouseRef.current = getEventPosition(e);
    toggleAllChainsMenu(e.currentTarget);
  });

  const handleAllChainsMouseEnter = useLastCallback((e: React.MouseEvent<HTMLElement>) => {
    lastMouseRef.current = { x: e.clientX, y: e.clientY };
    cancelAllChainsClose();
    scheduleDomainSubMenuClose();
    scheduleAllChainsHoverOpen(e.currentTarget);
  });

  const handleAllChainsMenuMouseEnter = useLastCallback(() => {
    cancelAllChainsClose();
    onMouseEnter?.();
  });

  const handleSubMenuMouseEnter = useLastCallback(() => {
    cancelAllChainsClose();
    cancelDomainSubMenuClose();
    onMouseEnter?.();
  });

  const handleTriangleMouseLeave = useLastCallback(() => {
    scheduleSubMenusClose();
    onMouseLeave?.();
  });

  const handleDomainCopyClick = useLastCallback(() => {
    const { item } = domainSubMenu!;
    handleItemClick(item.domain!, 'domain', item.chain);
  });

  const handleDomainAddressCopyClick = useLastCallback(() => {
    const { item } = domainSubMenu!;
    handleItemClick(item.address, 'address', item.chain);
  });

  const handleShareClick = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);

    if (!byChain || !visibleChains) return;

    const addressByChain = getAddressByChain(byChain, visibleChains);

    void shareUrl(getViewAccountUrl(addressByChain, isTestnet));
    onClose();
  });

  const handleBackdropClick = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);
    onClose();
  });

  if (!items.length) return undefined;

  const withHover = !IS_TOUCH_ENV;
  const hasHiddenItems = Boolean(hiddenItems.length);
  // The pointer travels toward the most recently opened sub-menu
  const trianglePosition = domainSubMenu?.position ?? allChainsPosition;

  return (
    <>
      {IS_TOUCH_ENV && isOpen && (
        // A single backdrop under the whole menu system. Everything closes in its `click` handler,
        // so the closing tap is always consumed here and never reaches the app beneath
        <Portal>
          <div className={styles.menuBackdrop} onClick={handleBackdropClick} />
        </Portal>
      )}

      <Menu
        menuRef={menuRef}
        isOpen={isOpen}
        type="dropdown"
        withPortal
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        anchor={anchor}
        bubbleClassName={buildClassName(styles.addressMenuBubble, !isOpen && styles.notActive)}
        noBackdrop
        onMouseEnter={withHover ? onMouseEnter : undefined}
        onMouseLeave={withHover ? onMouseLeave : undefined}
        onClose={onClose}
      >
        <ShareButton
          onClick={handleShareClick}
          onMouseEnter={withHover ? scheduleSubMenusClose : undefined}
        />
        {items.map((item, index) => (
          <MenuItem
            key={item.chain}
            item={item}
            withDelimiter={index === 0}
            onClick={handleMainRowClick}
            onMouseEnter={withHover ? handleMainRowMouseEnter : undefined}
            onExplorerClick={handleRowExplorerClick}
          />
        ))}
        {hasHiddenItems && (
          <div
            role="button"
            tabIndex={0}
            className={buildClassName(menuStyles.item, menuStyles.delimiter, styles.allChainsItem)}
            onClick={handleAllChainsClick}
            onKeyDown={handleAllChainsKeyDown}
            onMouseEnter={withHover ? handleAllChainsMouseEnter : undefined}
            onMouseLeave={withHover ? cancelAllChainsHoverOpen : undefined}
          >
            <span className={styles.allChainsLogos}>
              {hiddenItems.slice(0, ALL_CHAINS_LOGO_COUNT).map((item) => (
                <img key={item.chain} src={item.icon} alt="" className={styles.allChainsLogo} />
              ))}
            </span>
            <span className={styles.allChainsName}>{lang('All Chains')}</span>
            <i
              className={buildClassName('icon-chevron-right', styles.itemActionIcon, styles.itemChevronIcon)}
              aria-hidden
            />
          </div>
        )}
      </Menu>

      {hasHiddenItems && (
        <Menu
          isOpen={Boolean(allChainsPosition)}
          type="dropdown"
          withPortal
          anchor={allChainsPosition}
          positionX={allChainsPosition?.positionX}
          transformOriginY={allChainsPosition?.originY}
          bubbleClassName={buildClassName(
            styles.subMenuBubble,
            styles.allChainsMenuBubble,
            !allChainsPosition && styles.notActive,
          )}
          noBackdrop
          noHistoryBack
          onMouseEnter={withHover ? handleAllChainsMenuMouseEnter : undefined}
          onMouseLeave={withHover ? onMouseLeave : undefined}
          onClose={closeAllChainsMenu}
        >
          {hiddenItems.map((item) => (
            <MenuItem
              key={item.chain}
              item={item}
              onClick={handleRowClick}
              onMouseEnter={withHover ? handleSubMenuRowMouseEnter : undefined}
              onExplorerClick={handleRowExplorerClick}
            />
          ))}
        </Menu>
      )}

      {domainSubMenu && (
        <Menu
          key={domainSubMenu.item.chain}
          isOpen
          type="dropdown"
          withPortal
          anchor={domainSubMenu.position}
          positionX={domainSubMenu.position.positionX}
          transformOriginY={domainSubMenu.position.originY}
          bubbleClassName={buildClassName(styles.subMenuBubble, styles.domainMenuBubble)}
          noBackdrop
          noHistoryBack
          onMouseEnter={withHover ? handleSubMenuMouseEnter : undefined}
          onMouseLeave={withHover ? onMouseLeave : undefined}
          onClose={closeDomainSubMenu}
        >
          <DomainMenuItem
            title={shortenDomain(domainSubMenu.item.domain!)!}
            subtitle={lang('Domain')}
            onClick={handleDomainCopyClick}
          />
          <DomainMenuItem
            title={domainSubMenu.item.shortAddress}
            subtitle={lang('Address')}
            onClick={handleDomainAddressCopyClick}
          />
        </Menu>
      )}

      {withHover && trianglePosition && (
        <SafeTriangle
          key={domainSubMenu ? `domain-${domainSubMenu.item.chain}` : 'all-chains'}
          position={trianglePosition}
          initialMouse={lastMouseRef.current}
          onMouseEnter={handleSubMenuMouseEnter}
          onMouseLeave={handleTriangleMouseLeave}
        />
      )}
    </>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const account = selectCurrentAccount(global);
    return {
      byChain: account?.byChain,
      visibleChains: selectCurrentAccountChainDisplay(global)?.visibleChains,
    };
  })(AddressMenu),
);

function getEventPosition(e: React.UIEvent<HTMLElement>): IAnchorPosition {
  if ('clientX' in e) {
    const { clientX, clientY } = e as React.MouseEvent<HTMLElement>;
    return { x: clientX, y: clientY };
  }

  // A keyboard activation has no pointer coordinates, so the center of the focused row stands in
  const {
    left, top, width, height,
  } = e.currentTarget.getBoundingClientRect();
  return { x: left + width / 2, y: top + height / 2 };
}

function getAddressByChain(byChain: Account['byChain'], visibleChains: ApiChain[]) {
  return visibleChains.reduce((acc, chain) => {
    const chainData = byChain[chain];
    if (chainData) {
      acc[chain] = chainData.address;
    }
    return acc;
  }, {} as Partial<Record<ApiChain, string>>);
}
