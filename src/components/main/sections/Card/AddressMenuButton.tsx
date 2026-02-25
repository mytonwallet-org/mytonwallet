import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo, useMemo } from '../../../../lib/teact/teact';

import type { ApiChain } from '../../../../api/types';
import type { AccountChain } from '../../../../global/types';

import buildClassName from '../../../../util/buildClassName';
import { shortenAddress } from '../../../../util/shortenAddress';
import { shortenDomain } from '../../../../util/shortenDomain';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';

import useLastCallback from '../../../../hooks/useLastCallback';
import useLongPress from '../../../../hooks/useLongPress';

import styles from './Card.module.scss';

interface OwnProps {
  chains: ApiChain[];
  byChain: Map<ApiChain, AccountChain & {
    balance: number;
  }>;
  withTextGradient?: boolean;
  isMinimized?: boolean;
  openMenu: NoneToVoidFunction;
  onLongPress?: (chain: ApiChain, address: string, domain?: string) => void;
  onMouseEnter?: NoneToVoidFunction;
  onMouseLeave?: NoneToVoidFunction;
}

const MULTICHAIN_DOMAIN_LENGTH = 10;
const MULTICHAIN_ADDRESS_LENGTH = 6;

function AddressMenuButton({
  chains,
  withTextGradient,
  isMinimized,
  openMenu,
  onLongPress,
  onMouseEnter,
  onMouseLeave,
  byChain,
}: OwnProps) {
  const chain = chains[0];
  if (!chain) return undefined;

  const isMultiChain = chains.length > 1;
  const { domain, address } = byChain.get(chain) ?? {};

  const handleLongPressStart = useLastCallback((target: HTMLElement) => {
    const el = target.closest<HTMLElement>('[data-chain]');
    if (!el?.dataset.chain || !el.dataset.address) return;

    onLongPress?.(el.dataset.chain as ApiChain, el.dataset.address, el.dataset.domain);
  });

  const longPressHandlers = useLongPress({
    onClick: openMenu,
    onStart: handleLongPressStart,
  });

  const handleMouseLeave = useLastCallback((e: React.MouseEvent) => {
    onMouseLeave?.();
    longPressHandlers.onMouseLeave(e);
  });

  const multiChainButtonContent = useMemo(() => {
    if (!isMultiChain || !byChain) return undefined;

    const nodes: TeactNode[] = [];
    const chainsLength = chains.length;

    chains.forEach((chainItem, index) => {
      const { domain: chainDomain, address: chainAddress } = byChain.get(chainItem)!;
      const title = chainDomain
        ? shortenDomain(chainDomain, MULTICHAIN_DOMAIN_LENGTH)
        : shortenAddress(chainAddress, 0, MULTICHAIN_ADDRESS_LENGTH)!;

      nodes.push(
        <span
          key={`${chainItem}-item`}
          className={styles.multichainItem}
          data-chain={chainItem}
          data-address={chainAddress}
          data-domain={chainDomain}
        >
          <img src={getChainNetworkIcon(chainItem)} alt="" className={styles.chainIcon} />
          {[0, 1].includes(index) && (
            <span className={styles.multichainAddress}>
              {title}
              {index < chainsLength - 1 && ','}
            </span>
          )}
        </span>,
      );
    });

    return nodes;
  }, [byChain, chains, isMultiChain]);

  return (
    <button
      type="button"
      className={buildClassName(styles.address, withTextGradient && 'gradientText')}
      {...longPressHandlers}
      onMouseEnter={onMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {multiChainButtonContent ? (
        <span className={buildClassName(styles.multichainList, 'itemName')}>
          {multiChainButtonContent}
        </span>
      ) : (
        <span data-chain={chain} data-address={address} data-domain={domain}>
          <img src={getChainNetworkIcon(chain)} alt="" className={styles.chainIcon} />
          <span className={buildClassName(styles.itemName, 'itemName')}>
            {domain ? shortenDomain(domain) : shortenAddress(address!)}
          </span>
        </span>
      )}
      {!isMinimized && <i className={buildClassName('icon-expand', styles.iconExpand)} aria-hidden />}
    </button>
  );
}

export default memo(AddressMenuButton);
