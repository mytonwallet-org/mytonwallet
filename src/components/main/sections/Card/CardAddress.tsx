import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { AccountChain, AccountType } from '../../../../global/types';

import { selectAccount, selectCurrentAccountId, selectCurrentAccountTokens } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getChainConfig, getChainTitle, getSupportedChains } from '../../../../util/chain';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { toDecimal } from '../../../../util/decimals';
import { openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
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
  byChain: Map<ApiChain, AccountChain & {
    balance: number;
  }>;
  isTestnet?: boolean;
  isTemporary?: boolean;
  withTextGradient?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

function CardAddress({
  byChain,
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

  const chains = useMemo(() => {
    const dynamicOrder: ApiChain[] = [];
    const staticOrder: ApiChain[] = [];

    [...byChain].map((e) => {
      if (e[1].balance > 0) {
        dynamicOrder.push(e[0]);
      } else {
        staticOrder.push(e[0]);
      }
    });

    return [
      ...dynamicOrder,
      ...getSupportedChains().filter((chain) => staticOrder.includes(chain)),
    ];
  }, [byChain]);

  const isHardwareAccount = accountType === 'hardware';
  const isViewAccount = accountType === 'view';
  const menuItems = useMemo(() => {
    return chains.map((chain) => {
      const accountChain = byChain.get(chain)!;

      return {
        value: accountChain.address,
        address: shortenAddress(accountChain.address)!,
        ...(accountChain.domain && { domain: accountChain.domain }),
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
        chains={chains}
        byChain={byChain}
        withTextGradient={withTextGradient}
        isMinimized={isMinimized}
        openMenu={openMenu}
        onLongPress={handleLongPress}
        onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
        onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
      />
      {!isMinimized && (
        <AddressMenu
          isOpen={isMenuOpen}
          anchor={menuAnchor}
          items={menuItems}
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

  const accountTokens = selectCurrentAccountTokens(global);

  // Maps preserve an order
  const byChainWithBalances = new Map(Object.entries(byChain || {}).map(([chain, account]) => {
    const token = accountTokens?.filter((token) =>
      token.chain === chain
      && (
        token.slug === getChainConfig(chain).nativeToken.slug
        || token.slug === getChainConfig(chain).usdtSlug.mainnet
      ),
    ).reduce((acc, token) => acc + token.priceUsd * Number(toDecimal(token.amount || 0n, token.decimals || 0)), 0);

    return [
      chain,
      {
        ...account,
        balance: token,
      }] as [ApiChain, AccountChain & { balance: number }];
  }).sort((a, b) => b[1].balance - a[1].balance));

  return {
    byChain: byChainWithBalances,
    isTestnet: global.settings.isTestnet,
    accountType,
    isTemporary,
    selectedExplorerIds: global.settings.selectedExplorerIds,
  };
})(CardAddress));
