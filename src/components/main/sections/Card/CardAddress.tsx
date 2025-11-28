import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';

import { selectAccount, selectCurrentAccountId } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getOrderedAccountChains } from '../../../../util/chain';
import { openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
import { shortenDomain } from '../../../../util/shortenDomain';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';
import { getExplorerAddressUrl, getExplorerName } from '../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useAddressMenu from './hooks/useAddressMenu';

import AddressMenu from './AddressMenu';
import AddressMenuButton from './AddressMenuButton';
import ViewModeIcon from './ViewModeIcon';

import styles from './Card.module.scss';

interface OwnProps {
  isMinimized?: boolean;
}

interface StateProps {
  accountType?: AccountType;
  byChain?: Account['byChain'];
  isTestnet?: boolean;
  isTemporary?: boolean;
  withTextGradient?: boolean;
}

function CardAddress({
  byChain,
  isTestnet,
  accountType,
  withTextGradient,
  isMinimized,
  isTemporary,
}: StateProps & OwnProps) {
  const lang = useLang();

  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();

  const {
    menuAnchor,
    isMenuOpen,
    openMenu,
    closeMenu,
    getTriggerElement,
    getRootElement,
    getMenuElement,
    getLayout,
    handleMouseEnter,
    handleMouseLeave,
  } = useAddressMenu(ref, menuRef);

  const chains = useMemo(() => getOrderedAccountChains(byChain ?? {}), [byChain]);
  const isHardwareAccount = accountType === 'hardware';
  const isViewAccount = accountType === 'view';
  const menuItems = useMemo(() => {
    return chains.map((chain) => {
      const accountChain = byChain![chain]!;

      return {
        value: accountChain.address,
        address: shortenAddress(accountChain.address)!,
        ...(accountChain.domain && { domain: shortenDomain(accountChain.domain) }),
        icon: getChainNetworkIcon(chain),
        fontIcon: 'copy',
        chain,
        label: (lang('View address on %explorer_name%', {
          explorer_name: getExplorerName(chain),
        }) as string[]
        ).join(''),
      };
    });
  }, [byChain, chains, lang]);

  const handleExplorerClick = useLastCallback((chain: ApiChain, address: string) => {
    void openUrl(getExplorerAddressUrl(chain, address, isTestnet)!);
    closeMenu();
  });

  return (
    <div ref={ref} className={buildClassName(styles.addressContainer, isMinimized && styles.minimized)}>
      {isViewAccount && <ViewModeIcon isTemporary={isTemporary} isMinimized={isMinimized} />}
      {isHardwareAccount && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
      <AddressMenuButton
        chains={chains}
        byChain={byChain}
        withTextGradient={withTextGradient}
        isMinimized={isMinimized}
        onClick={openMenu}
        onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
        onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
      />
      {!isMinimized && (
        <AddressMenu
          isOpen={isMenuOpen}
          anchor={menuAnchor}
          items={menuItems}
          menuRef={menuRef}
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

  return {
    byChain,
    isTestnet: global.settings.isTestnet,
    accountType,
    isTemporary,
  };
})(CardAddress));
