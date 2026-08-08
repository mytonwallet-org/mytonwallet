import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';
import type { LangFn } from '../../../../hooks/useLang';
import type { AddressMenuItem } from './addressMenu/MenuItem';

import {
  selectAccount,
  selectCurrentAccountChainDisplay,
  selectCurrentAccountId,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle } from '../../../../util/chain';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';
import { getExplorerAddressUrl, getExplorerName } from '../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import useAddressMenu from './addressMenu/useAddressMenu';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useWindowSize from '../../../../hooks/useWindowSize';

import AddressMenu from './addressMenu/AddressMenu';
import AddressMenuButton from './AddressMenuButton';
import ViewModeIcon from './ViewModeIcon';

import styles from './Card.module.scss';

interface OwnProps {
  isMinimized?: boolean;
}

interface StateProps {
  accountType?: AccountType;
  accountByChain?: Account['byChain'];
  visibleChains?: ApiChain[];
  orderedChains?: ApiChain[];
  addressLineChains?: ApiChain[];
  isTestnet?: boolean;
  isTemporary?: boolean;
  withTextGradient?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

const TINY_WINDOW_SIZE_PX = 374;
const EMPTY_BY_CHAIN: Account['byChain'] = {};
const EMPTY_CHAINS: ApiChain[] = [];

function CardAddress({
  accountByChain,
  visibleChains,
  orderedChains,
  addressLineChains,
  isTestnet,
  accountType,
  withTextGradient,
  isMinimized,
  isTemporary,
  selectedExplorerIds,
}: StateProps & OwnProps) {
  const lang = useLang();

  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();
  const { isLandscape } = useDeviceScreen();
  const { width: windowWidth } = useWindowSize();

  const {
    menuAnchor,
    isMenuOpen,
    toggleMenu,
    closeMenu,
    getTriggerElement,
    getRootElement,
    getMenuElement,
    getLayout,
    handleMouseEnter,
    handleMouseLeave,
  } = useAddressMenu(ref, menuRef);

  const byChain = accountByChain ?? EMPTY_BY_CHAIN;
  const chains = visibleChains ?? EMPTY_CHAINS;
  // The address line collapses under the Gram Wallet gate while the menu keeps every visible chain,
  // matching Air (`AddressesMenu` renders un-gated `displayedChains` on iOS)
  const lineChains = addressLineChains ?? EMPTY_CHAINS;

  const isHardwareAccount = accountType === 'hardware';
  const isViewAccount = accountType === 'view';
  const isTinyFormat = isViewAccount && (isLandscape || windowWidth < TINY_WINDOW_SIZE_PX);
  const { menuItems, hiddenMenuItems } = useMemo(() => {
    const hiddenChains = (orderedChains ?? EMPTY_CHAINS).filter((chain) => !chains.includes(chain));

    return {
      menuItems: chains.map((chain) => buildMenuItem(lang, chain, byChain[chain]!)),
      hiddenMenuItems: hiddenChains.map((chain) => buildMenuItem(lang, chain, byChain[chain]!)),
    };
  }, [byChain, chains, orderedChains, lang]);

  const handleExplorerClick = useLastCallback((chain: ApiChain, address: string) => {
    void openUrl(getExplorerAddressUrl(chain, address, isTestnet, selectedExplorerIds?.[chain])!);
    closeMenu();
  });

  const { showToast } = getActions();

  const handleLongPress = useLastCallback((chain: ApiChain, address: string, domain?: string) => {
    void copyTextToClipboard(domain ?? address);
    const message = domain
      ? lang('%chain% Domain Copied', { chain: getChainTitle(chain) }) as string
      : lang('%chain% Address Copied', { chain: getChainTitle(chain) }) as string;
    showToast({ message, icon: 'icon-copy' });
  });

  return (
    <div ref={ref} className={buildClassName(styles.addressContainer, isMinimized && styles.minimized)}>
      {isViewAccount && <ViewModeIcon isTemporary={isTemporary} isMinimized={isMinimized} />}
      {isHardwareAccount && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
      <AddressMenuButton
        chains={lineChains}
        byChain={byChain}
        withTextGradient={withTextGradient}
        isMinimized={isMinimized}
        isTinyFormat={isTinyFormat}
        toggleMenu={toggleMenu}
        onLongPress={handleLongPress}
        onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
        onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
      />
      {!isMinimized && (
        <AddressMenu
          isOpen={isMenuOpen}
          anchor={menuAnchor}
          items={menuItems}
          hiddenItems={hiddenMenuItems}
          menuRef={menuRef}
          isTestnet={isTestnet}
          onClose={closeMenu}
          onExplorerClick={handleExplorerClick}
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
          getTriggerElement={getTriggerElement}
          getRootElement={getRootElement}
          getMenuElement={getMenuElement}
          getLayout={getLayout}
        />
      )}
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const account = accountId ? selectAccount(global, accountId) : undefined;
  const { type: accountType, byChain, isTemporary } = account || {};
  const chainDisplay = selectCurrentAccountChainDisplay(global);

  return {
    accountByChain: byChain,
    visibleChains: chainDisplay?.visibleChains,
    orderedChains: chainDisplay?.orderedChains,
    addressLineChains: chainDisplay?.addressLineChains,
    isTestnet: global.settings.isTestnet,
    accountType,
    isTemporary,
    selectedExplorerIds: global.settings.selectedExplorerIds,
  };
})(CardAddress));

function buildMenuItem(
  lang: LangFn,
  chain: ApiChain,
  wallet: NonNullable<Account['byChain'][ApiChain]>,
): AddressMenuItem {
  return {
    chain,
    address: wallet.address,
    shortAddress: shortenAddress(wallet.address)!,
    ...(wallet.domain && { domain: wallet.domain }),
    icon: getChainNetworkIcon(chain),
    title: getChainTitle(chain),
    label: (lang('View address on %explorer_name%', {
      explorer_name: getExplorerName(chain),
    }) as string[]
    ).join(''),
  };
}
