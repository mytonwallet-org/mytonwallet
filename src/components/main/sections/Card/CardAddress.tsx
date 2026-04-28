import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain, ApiStakingState } from '../../../../api/types';
import type { AccountChain, AccountType, UserToken } from '../../../../global/types';

import { PRIORITY_TOKENS, STAKED_TOKEN_SLUGS } from '../../../../config';
import { Big } from '../../../../lib/big.js';
import {
  selectAccount,
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle } from '../../../../util/chain';
import { copyTextToClipboard } from '../../../../util/clipboard';
import { toBig } from '../../../../util/decimals';
import { buildArrayCollectionByKey } from '../../../../util/iteratees';
import { openUrl } from '../../../../util/openUrl';
import { shortenAddress } from '../../../../util/shortenAddress';
import { getFullStakingBalance } from '../../../../util/staking';
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

const CHAIN_ORDER = PRIORITY_TOKENS.reduce((acc, token) => {
  if (!acc.has(token.chain)) {
    acc.set(token.chain, acc.size);
  }

  return acc;
}, new Map<ApiChain, number>());

function calculateChainBalanceUsd(
  chain: ApiChain,
  tokens?: UserToken[],
  stakingStates?: ApiStakingState[],
) {
  const stakingStateBySlug = buildArrayCollectionByKey(stakingStates ?? [], 'tokenSlug');

  return (tokens ?? []).reduce((acc, token) => {
    if (token.chain !== chain || STAKED_TOKEN_SLUGS.has(token.slug)) {
      return acc;
    }

    const tokenStakingStates = stakingStateBySlug[token.slug] ?? [];
    for (const stakingState of tokenStakingStates) {
      const stakingAmount = toBig(getFullStakingBalance(stakingState), token.decimals);

      acc = acc.plus(stakingAmount.mul(token.priceUsd));
    }

    return acc.plus(toBig(token.amount, token.decimals).mul(token.priceUsd));
  }, Big(0)).toNumber();
}

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
    return [...byChain.keys()];
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
  const stakingStates = accountId ? selectAccountStakingStates(global, accountId) : undefined;

  // Maps preserve an order
  const byChainWithBalances = new Map(Object.entries(byChain || {}).map(([chainKey, account]) => {
    const chain = chainKey as ApiChain;

    const balance = calculateChainBalanceUsd(chain, accountTokens, stakingStates);

    return [
      chain,
      {
        ...account,
        balance,
      }] as [ApiChain, AccountChain & { balance: number }];
  }).sort((a, b) => {
    const balanceDiff = b[1].balance - a[1].balance;

    if (balanceDiff !== 0) {
      return balanceDiff;
    }

    return (CHAIN_ORDER.get(a[0]) ?? Infinity) - (CHAIN_ORDER.get(b[0]) ?? Infinity);
  }));

  return {
    byChain: byChainWithBalances,
    isTestnet: global.settings.isTestnet,
    accountType,
    isTemporary,
    selectedExplorerIds: global.settings.selectedExplorerIds,
  };
})(CardAddress));
