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
import { getChainConfig, getChainTitle, getOrderedAccountChains } from '../../../../util/chain';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { stopEvent } from '../../../../util/domEvents';
import { getShareIcon, shareUrl } from '../../../../util/share';
import { shortenDomain } from '../../../../util/shortenDomain';
import { getViewAccountUrl } from '../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';

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
}

const FULL_DOMAIN_LENGTH = 20;

function AddressMenu({
  isOpen,
  anchor,
  items,
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
}: OwnProps & StateProps) {
  const { showToast } = getActions();

  const lang = useLang();

  const handleItemClick = useLastCallback((value: string, kind: 'address' | 'domain', chain: ApiChain) => {
    const message = kind === 'domain'
      ? lang('%chain% Domain Copied', { chain: getChainTitle(chain) }) as string
      : lang('%chain% Address Copied', { chain: getChainTitle(chain) }) as string;
    showToast({
      message,
      icon: 'icon-copy',
    });
    void copyTextToClipboard(value);
    onClose();
  });

  const handleShareClick = useLastCallback((e: React.MouseEvent) => {
    stopEvent(e);

    const addressByChain = getAddressByChain(byChain);
    if (!addressByChain) return;

    void shareUrl(getViewAccountUrl(addressByChain, isTestnet));
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
          onMenuClose={onClose}
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

function MenuItem({
  item,
  index,
  onItemClick,
  onExplorerClick,
  onMenuClose,
}: {
  item: MenuItem;
  index: number;
  onItemClick: (address: string, kind: 'address' | 'domain', chain: ApiChain) => void;
  onExplorerClick: (chain: ApiChain, address: string) => void;
  onMenuClose: NoneToVoidFunction;
}) {
  const hasDomain = !!item.domain;
  const itemClassName = buildClassName(
    menuStyles.item,
    index > 0 && menuStyles.separator,
    styles.menuItem,
  );
  const copyIconClassName = buildClassName(
    `icon icon-${item.fontIcon}`,
    menuStyles.fontIcon,
    styles.menuFontIcon,
  );

  const handleItemClick = (e: React.MouseEvent) => {
    if (hasDomain) {
      onItemClick(item.domain!, 'domain', item.chain);
    } else {
      onItemClick(item.value, 'address', item.chain);
    }
  };

  const handleAddressClick = (e: React.MouseEvent) => {
    stopEvent(e);
    onItemClick(item.value, 'address', item.chain);
  };

  const handleExplorerClick = (e: React.MouseEvent) => {
    stopEvent(e);
    onMenuClose();
    onExplorerClick(item.chain, item.value);
  };

  return (
    <div role="button" tabIndex={0} onClick={handleItemClick} className={itemClassName}>
      <img
        src={item.icon}
        alt=""
        className={buildClassName('icon', menuStyles.itemIcon, styles.menuIcon)}
      />
      <div className={styles.menuItemContent}>
        <div className={buildClassName(menuStyles.itemName, styles.menuItemName)}>
          {hasDomain ? (
            <span className={styles.domainText}>
              {shortenDomain(item.domain!, FULL_DOMAIN_LENGTH)}
            </span>
          ) : (<span>{item.address}</span>)}
          <i className={copyIconClassName} aria-hidden />
        </div>

        <div className={styles.chainRow}>
          {hasDomain ? (
            <>
              <span
                tabIndex={0}
                role="button"
                className={styles.addressText}
                onClick={handleAddressClick}
              >
                {item.address}
              </span>
              <span className={styles.separator}>·</span>
              {item.chain.toUpperCase()}
            </>
          ) : (
            getChainConfig(item.chain).title
          )}
        </div>
      </div>
      <i
        tabIndex={0}
        role="button"
        className={buildClassName('icon icon-tonexplorer-small', styles.menuExplorerIcon)}
        aria-label={item.label}
        onClick={handleExplorerClick}
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
