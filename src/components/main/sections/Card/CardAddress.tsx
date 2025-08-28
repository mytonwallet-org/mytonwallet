import React, { memo, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Account, AccountType, IAnchorPosition } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';

import { selectAccount } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { handleUrlClick, openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';
import { getExplorerAddressUrl, getExplorerName } from '../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Menu from '../../../ui/Menu';

import menuStyles from '../../../ui/Dropdown.module.scss';
import styles from './Card.module.scss';

import multichainIconSrc from '../../../../assets/multichain_account.svg';

interface StateProps {
  addressByChain?: Account['addressByChain'];
  domainByChain?: Account['domainByChain'];
  isTestnet?: boolean;
  accountType?: AccountType;
  withTextGradient?: boolean;
}

const MOUSE_LEAVE_TIMEOUT = 150;

function CardAddress({
  addressByChain, domainByChain, isTestnet, accountType, withTextGradient,
}: StateProps) {
  const { showNotification } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isMenuOpen = Boolean(menuAnchor);

  const chains = useMemo(() => Object.keys(addressByChain || {}) as ApiChain[], [addressByChain]);
  const isHardwareAccount = accountType === 'hardware';
  const isViewAccount = accountType === 'view';
  const explorerTitle = lang('View on Explorer');
  const chainDropdownItems = useMemo(() => {
    const hasDomain = chains[0] && domainByChain?.[chains[0]];

    if (chains.length < 2 && !hasDomain) return undefined;

    return chains.map((chain) => ({
      value: addressByChain![chain]!,
      address: shortenAddress(addressByChain![chain]!, domainByChain?.[chain] ? 4 : undefined)!,
      ...(domainByChain?.[chain] && { domain: domainByChain[chain] }),
      icon: getChainNetworkIcon(chain),
      fontIcon: 'copy',
      chain,
      label: (lang('View address on %ton_explorer_name%', {
        ton_explorer_name: getExplorerName(chain),
      }) as string[]
      ).join(''),
    }));
  }, [addressByChain, domainByChain, chains, lang]);

  const openMenu = () => {
    const { left, width, bottom: y } = ref.current!.getBoundingClientRect();
    setMenuAnchor({ x: left + width / 2, y });
  };

  const closeMenu = () => {
    setMenuAnchor(undefined);
  };

  const handleCopyAddress = useLastCallback((address: string) => {
    showNotification({ message: lang('Address was copied!'), icon: 'icon-copy' });
    void copyTextToClipboard(address);
  });

  const handleItemClick = useLastCallback((e: React.MouseEvent, address: string) => {
    handleCopyAddress(address);
    closeMenu();
  });

  const handleDomainClick = useLastCallback((e: React.MouseEvent, domain: string) => {
    showNotification({ message: lang('Domain was copied!'), icon: 'icon-copy' });
    void copyTextToClipboard(domain);
    closeMenu();
  });

  const handleExplorerClick = useLastCallback((e: React.MouseEvent, chain: ApiChain, address: string) => {
    void openUrl(getExplorerAddressUrl(chain, address, isTestnet)!);
    closeMenu();
  });

  const closeTimeoutRef = useRef<number>();
  const handleMouseEnter = useLastCallback(() => {
    if (closeTimeoutRef.current) {
      clearTimeout(closeTimeoutRef.current);
    }
    openMenu();
  });
  const handleMouseLeave = useLastCallback(() => {
    closeTimeoutRef.current = window.setTimeout(closeMenu, MOUSE_LEAVE_TIMEOUT);
  });
  const getTriggerElement = useLastCallback(() => ref.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    centerHorizontally: isPortrait,
    preferredPositionX: 'left' as const,
    doNotCoverTrigger: isPortrait,
  }));

  function renderAddressMenu() {
    return (
      <Menu
        menuRef={menuRef}
        isOpen={isMenuOpen}
        type="dropdown"
        withPortal
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        anchor={menuAnchor}
        bubbleClassName={styles.addressMenuBubble}
        noBackdrop={!IS_TOUCH_ENV}
        onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
        onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
        onClose={closeMenu}
      >
        {chainDropdownItems!.map((item, index) => {
          const fullItemClassName = buildClassName(
            menuStyles.item,
            index > 0 && menuStyles.separator,
            styles.menuItem,
          );

          return (
            <div key={item.value} className={fullItemClassName}>
              {chainDropdownItems!.length > 1 && (
                <img src={item.icon} alt="" className={buildClassName('icon', menuStyles.itemIcon, styles.menuIcon)} />
              )}
              <span className={buildClassName(menuStyles.itemName, styles.menuItemName)}>
                {item.domain && (
                  <>
                    <span
                      tabIndex={0}
                      role="button"
                      className={styles.domainText}
                      onClick={(e) => handleDomainClick(e, item.domain!)}
                    >
                      {item.domain}
                    </span>
                    <span className={styles.separator}>·</span>
                  </>
                )}
                <span
                  tabIndex={0}
                  role="button"
                  onClick={(e) => handleItemClick(e, item.value)}
                  className={item.domain && styles.addressText}
                >
                  {item.address}
                </span>
                <i
                  className={buildClassName(`icon icon-${item.fontIcon}`, menuStyles.fontIcon, styles.menuFontIcon)}
                  aria-hidden
                  onClick={(e) => handleItemClick(e, item.value)}
                />
              </span>
              <i
                tabIndex={0}
                role="button"
                className={buildClassName(menuStyles.close, 'icon icon-tonexplorer-small', styles.menuExplorerIcon)}
                aria-label={item.label}
                onClick={(e) => handleExplorerClick(e, item.chain, item.value)}
              />
            </div>
          );
        })}
      </Menu>
    );
  }

  if (chainDropdownItems) {
    const chain = chains[0];
    const domain = domainByChain?.[chain];
    const buttonText = chains.length === 1 && domain ? domain : lang('Multichain');

    return (
      <div ref={ref} className={styles.addressContainer}>
        {isViewAccount && (
          <span className={styles.addressLabel}>
            <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />
            {lang('$view_mode')}
          </span>
        )}
        {isHardwareAccount && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
        <button
          type="button"
          className={buildClassName(styles.address, withTextGradient && 'gradientText')}
          onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
          onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
          onClick={openMenu}
        >
          {chains.length > 1
            ? <img src={multichainIconSrc} alt="" className={styles.multichainIcon} />
            : <img src={getChainNetworkIcon(chain)} alt="" className={styles.chainIcon} />}

          <span className={buildClassName(styles.itemName, 'itemName')}>
            {buttonText}
          </span>
          <i className={buildClassName(styles.iconCaretSmall, 'icon-caret-down')} aria-hidden />
        </button>
        {renderAddressMenu()}
      </div>
    );
  }

  const chain = chains[0];
  if (!chain) return undefined;

  const address = addressByChain![chain]!;
  const domain = domainByChain?.[chain];
  const displayText = domain || shortenAddress(address);

  return (
    <div className={styles.addressContainer}>
      {isViewAccount && (
        <span className={styles.addressLabel}>
          <i className={buildClassName(styles.icon, 'icon-eye-filled')} aria-hidden />
          {lang('$view_mode')}
        </span>
      )}
      {isHardwareAccount && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
      <button
        type="button"
        className={buildClassName(styles.address, withTextGradient && 'gradientText')}
        aria-label={lang('Copy wallet address')}
        onClick={() => handleCopyAddress(address)}
      >
        <img src={getChainNetworkIcon(chain)} alt="" className={styles.chainIcon} />
        {displayText}
        <i className={buildClassName(styles.icon, 'icon-copy')} aria-hidden />
      </button>
      <a
        href={getExplorerAddressUrl(chain, address, isTestnet)}
        className={styles.explorerButton}
        title={explorerTitle}
        aria-label={explorerTitle}
        target="_blank"
        rel="noreferrer noopener"
        onClick={handleUrlClick}
      >
        <i className={buildClassName(styles.icon, 'icon-tonexplorer-small')} aria-hidden />
      </a>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { type: accountType, addressByChain, domainByChain } = selectAccount(global, global.currentAccountId!) || {};

  return {
    addressByChain,
    domainByChain,
    isTestnet: global.settings.isTestnet,
    accountType,
  };
})(CardAddress));
