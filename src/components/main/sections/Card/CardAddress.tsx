import React, { memo, useEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';
import type { LangFn } from '../../../../hooks/useLang';
import type { AddressMenuItem } from './addressMenu/MenuItem';

import { IS_EXPLORER } from '../../../../config';
import {
  selectAccount,
  selectAccountChainDisplay,
  selectCurrentAccountId,
} from '../../../../global/selectors';
import { getAccountTitle } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle } from '../../../../util/chain';
import isEmptyObject from '../../../../util/isEmptyObject';
import { openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';
import { getExplorerAddressUrl, getExplorerName } from '../../../../util/url';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import useAddressMenu from './addressMenu/useAddressMenu';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import AddressMenu from './addressMenu/AddressMenu';
import AddressMenuButton from './AddressMenuButton';
import ViewModeIcon from './ViewModeIcon';

import styles from './Card.module.scss';

interface OwnProps {
  accountId?: string;
  withTextGradient?: boolean;
  isMinimized?: boolean;
  isDisabled?: boolean;
  testId?: string;
}

interface StateProps {
  title?: string;
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

const EMPTY_BY_CHAIN: Account['byChain'] = {};
const EMPTY_CHAINS: ApiChain[] = [];

function CardAddress({
  title,
  accountByChain,
  visibleChains,
  orderedChains,
  addressLineChains,
  isTestnet,
  accountType,
  withTextGradient,
  isMinimized,
  isDisabled,
  isTemporary,
  selectedExplorerIds,
  testId,
}: StateProps & OwnProps) {
  const lang = useLang();

  const ref = useRef<HTMLDivElement>();
  const menuRef = useRef<HTMLDivElement>();

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

  // The menu is rendered outside the card, so the `inert` attribute of the card does not reach it
  useEffect(() => {
    if (isDisabled) closeMenu();
  }, [isDisabled, closeMenu]);

  const byChain = accountByChain ?? EMPTY_BY_CHAIN;
  const chains = visibleChains ?? EMPTY_CHAINS;

  const isHardwareAccount = accountType === 'hardware';
  const isViewAccount = accountType === 'view';
  const { menuItems, hiddenMenuItems } = useMemo(() => {
    const hiddenChains = (orderedChains ?? EMPTY_CHAINS).filter((chain) => !chains.includes(chain));

    return {
      menuItems: chains.map((chain) => buildMenuItem(
        lang, chain, byChain[chain]!, isTemporary, selectedExplorerIds?.[chain],
      )),
      hiddenMenuItems: hiddenChains.map((chain) => buildMenuItem(
        lang, chain, byChain[chain]!, isTemporary, selectedExplorerIds?.[chain],
      )),
    };
  }, [byChain, chains, orderedChains, lang, isTemporary, selectedExplorerIds]);

  const { openReceiveModal } = getActions();

  const handleActionClick = useLastCallback((chain: ApiChain, address: string) => {
    if (isTemporary) {
      void openUrl(getExplorerAddressUrl(chain, address, isTestnet, selectedExplorerIds?.[chain])!);
    } else {
      openReceiveModal({ chain });
    }
  });

  return (
    <div ref={ref} className={buildClassName(styles.addressContainer, isMinimized && styles.minimized)}>
      {isViewAccount && (
        <ViewModeIcon
          canSave={isTemporary && !IS_EXPLORER && !isEmptyObject(byChain)}
          isMinimized={isMinimized}
        />
      )}
      {isHardwareAccount && <i className={buildClassName(styles.icon, 'icon-ledger')} aria-hidden />}
      {Boolean(addressLineChains?.length) && (
        <AddressMenuButton
          title={title!}
          withTextGradient={withTextGradient}
          isMinimized={isMinimized}
          testId={testId}
          toggleMenu={toggleMenu}
          onMouseEnter={!IS_TOUCH_ENV ? handleMouseEnter : undefined}
          onMouseLeave={!IS_TOUCH_ENV ? handleMouseLeave : undefined}
        />
      )}
      {!isMinimized && (
        <AddressMenu
          isOpen={isMenuOpen}
          anchor={menuAnchor}
          items={menuItems}
          hiddenItems={hiddenMenuItems}
          menuRef={menuRef}
          isTestnet={isTestnet}
          onClose={closeMenu}
          onActionClick={handleActionClick}
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

export default memo(withGlobal<OwnProps>((global, ownProps): StateProps => {
  const accountId = ownProps.accountId ?? selectCurrentAccountId(global);
  const account = accountId ? selectAccount(global, accountId) : undefined;
  const { type: accountType, byChain, isTemporary } = account || {};
  const chainDisplay = accountId ? selectAccountChainDisplay(global, accountId) : undefined;

  return {
    title: account ? getAccountTitle(account) : undefined,
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
  isTemporary?: boolean,
  explorerId?: string,
): AddressMenuItem {
  return {
    chain,
    address: wallet.address,
    shortAddress: shortenAddress(wallet.address)!,
    ...(wallet.domain && { domain: wallet.domain }),
    icon: getChainNetworkIcon(chain),
    title: getChainTitle(chain),
    // A temporary account is someone else's wallet being viewed, so its rows lead to the explorer instead of Fund
    actionIcon: isTemporary ? 'icon-explorer-small' : 'icon-qr-code',
    actionLabel: isTemporary
      ? (lang('View address on %explorer_name%', {
        explorer_name: getExplorerName(chain, explorerId),
      }) as string[]).join('')
      : lang('Receive'),
  };
}
