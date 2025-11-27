import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Account } from '../../../../global/types';
import type { IAnchorPosition } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';

import { IS_CAPACITOR } from '../../../../config';
import { selectCurrentAccount } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getOrderedAccountChains } from '../../../../util/chain';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { stopEvent } from '../../../../util/domEvents';
import { shareUrl } from '../../../../util/share';
import { shortenDomain } from '../../../../util/shortenDomain';
import { getViewAccountUrl } from '../../../../util/url';
import { IS_ANDROID_APP, IS_IOS_APP, IS_TOUCH_ENV } from '../../../../util/windowEnvironment';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Menu from '../../../ui/Menu';

import menuStyles from '../../../ui/Dropdown.module.scss';
import styles from './Card.module.scss';

interface MenuItem {
  value: string;
  address: string;
  domain?: string;
  icon: string;
  fontIcon: string;
  chain: ApiChain;
  label: string;
}

interface OwnProps {
  isOpen: boolean;
  anchor?: IAnchorPosition;
  items: MenuItem[];
  menuRef: ElementRef<HTMLDivElement>;
  onClose: NoneToVoidFunction;
  onExplorerClick: (e: React.MouseEvent, chain: ApiChain, address: string) => void;
  onMouseEnter?: NoneToVoidFunction;
  onMouseLeave?: NoneToVoidFunction;
  getTriggerElement: () => HTMLElement | undefined | null;
  getRootElement: () => HTMLElement | undefined | null;
  getMenuElement: () => HTMLElement | undefined | null;
  getLayout: () => Layout;
}

interface StateProps {
  byChain?: Account['byChain'];
}

const FULL_DOMAIN_LENGTH = 20;

function AddressMenu({
  isOpen,
  anchor,
  items,
  menuRef,
  onClose,
  onExplorerClick,
  onMouseEnter,
  onMouseLeave,
  getTriggerElement,
  getRootElement,
  getMenuElement,
  getLayout,
  byChain,
}: OwnProps & StateProps) {
  const lang = useLang();
  const { showNotification } = getActions();

  const handleItemClick = useLastCallback((e: React.MouseEvent, value: string, kind: 'address' | 'domain') => {
    showNotification({
      message: lang(kind === 'domain' ? 'Domain was copied!' : 'Address was copied!'),
      icon: 'icon-copy',
    });
    void copyTextToClipboard(value);
    onClose();
  });

  const handleShareClick = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);

    const addressByChain = getAddressByChain(byChain);
    if (!addressByChain) return;

    void shareUrl(getViewAccountUrl(addressByChain));
    onClose();
  });

  if (!items.length) return undefined;

  return (
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
      bubbleClassName={styles.addressMenuBubble}
      noBackdrop={!IS_TOUCH_ENV}
      onMouseEnter={!IS_TOUCH_ENV ? onMouseEnter : undefined}
      onMouseLeave={!IS_TOUCH_ENV ? onMouseLeave : undefined}
      onClose={onClose}
    >
      {items.map((item, index) => (
        <MenuItem
          key={item.value}
          item={item}
          index={index}
          onItemClick={handleItemClick}
          onExplorerClick={onExplorerClick}
        />
      ))}
      <ShareButton onClick={handleShareClick} lang={lang} />
    </Menu>
  );
}

export default memo(
  withGlobal<OwnProps>((global): StateProps => {
    const account = selectCurrentAccount(global);
    return {
      byChain: account?.byChain,
    };
  })(AddressMenu),
);

function getShareIcon(): string {
  if (IS_IOS_APP) return 'icon-share-ios';
  if (IS_ANDROID_APP) return 'icon-share-android';
  return 'icon-link';
}

function getAddressByChain(byChain: Account['byChain'] | undefined): Partial<Record<ApiChain, string>> | undefined {
  if (!byChain) return undefined;

  const orderedChains = getOrderedAccountChains(byChain);
  return orderedChains.reduce((acc, chain) => {
    const chainData = byChain[chain];
    if (chainData) {
      acc[chain] = chainData.address;
    }
    return acc;
  }, {} as Partial<Record<ApiChain, string>>);
}

function MenuItemName({
  item,
  hasDomain,
  onItemClick,
}: {
  item: MenuItem;
  hasDomain: boolean;
  onItemClick: (e: React.MouseEvent, value: string, kind: 'address' | 'domain') => void;
}) {
  const copyIconClassName = buildClassName(
    `icon icon-${item.fontIcon}`,
    menuStyles.fontIcon,
    styles.menuFontIcon,
  );

  if (hasDomain) {
    return (
      <div className={buildClassName(menuStyles.itemName, styles.menuItemName)}>
        <span
          tabIndex={0}
          role="button"
          className={styles.domainText}
          onClick={(event) => onItemClick(event, item.domain!, 'domain')}
        >
          {shortenDomain(item.domain!, FULL_DOMAIN_LENGTH)}
        </span>
        <i
          className={copyIconClassName}
          aria-hidden
          onClick={(event) => onItemClick(event, item.value, 'domain')}
        />
      </div>
    );
  }

  return (
    <div className={buildClassName(menuStyles.itemName, styles.menuItemName)}>
      <span
        tabIndex={0}
        role="button"
        onClick={(event) => onItemClick(event, item.value, 'address')}
      >
        {item.address}
      </span>
      <i
        className={copyIconClassName}
        aria-hidden
        onClick={(event) => onItemClick(event, item.value, 'address')}
      />
    </div>
  );
}

function ChainName({
  item,
  hasDomain,
  onItemClick,
}: {
  item: MenuItem;
  hasDomain: boolean;
  onItemClick: (e: React.MouseEvent, value: string, kind: 'address' | 'domain') => void;
}) {
  if (!hasDomain) {
    return <div className={styles.chainName}>{item.chain.toUpperCase()}</div>;
  }

  return (
    <div className={styles.chainName}>
      <span
        tabIndex={0}
        role="button"
        className={styles.addressText}
        onClick={(event) => onItemClick(event, item.value, 'address')}
      >
        {item.address}
      </span>
      <span className={styles.separator}>·</span>
      {item.chain.toUpperCase()}
    </div>
  );
}

function MenuItem({
  item,
  index,
  onItemClick,
  onExplorerClick,
}: {
  item: MenuItem;
  index: number;
  onItemClick: (e: React.MouseEvent, value: string, kind: 'address' | 'domain') => void;
  onExplorerClick: (e: React.MouseEvent, chain: ApiChain, address: string) => void;
}) {
  const hasDomain = !!item.domain;
  const itemClassName = buildClassName(
    menuStyles.item,
    index > 0 && menuStyles.separator,
    styles.menuItem,
  );

  return (
    <div className={itemClassName}>
      <img
        src={item.icon}
        alt=""
        className={buildClassName('icon', menuStyles.itemIcon, styles.menuIcon)}
      />
      <div className={styles.menuItemContent}>
        <MenuItemName
          item={item}
          hasDomain={hasDomain}
          onItemClick={onItemClick}
        />
        <ChainName item={item} hasDomain={hasDomain} onItemClick={onItemClick} />
      </div>
      <i
        tabIndex={0}
        role="button"
        className={buildClassName('icon icon-tonexplorer-small', styles.menuExplorerIcon)}
        aria-label={item.label}
        onClick={(event) => onExplorerClick(event, item.chain, item.value)}
      />
    </div>
  );
}

function ShareButton({
  onClick,
  lang,
}: {
  onClick: (e: React.MouseEvent) => void;
  lang: ReturnType<typeof useLang>;
}) {
  const shareIconClassName = buildClassName(
    menuStyles.fontIcon,
    menuStyles.fontIconBig,
    getShareIcon(),
  );

  return (
    <button
      type="button"
      className={buildClassName(menuStyles.item, menuStyles.delimiter, styles.menuItem)}
      onClick={onClick}
    >
      <i className={shareIconClassName} aria-hidden />
      <span className={buildClassName(menuStyles.itemName, styles.menuItemName)}>
        {lang(IS_CAPACITOR ? 'Share Wallet Link' : 'Copy Wallet Link')}
      </span>
    </button>
  );
}
