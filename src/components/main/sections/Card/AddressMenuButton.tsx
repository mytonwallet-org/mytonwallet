import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo, useMemo } from '../../../../lib/teact/teact';

import type { ApiChain } from '../../../../api/types';
import type { Account } from '../../../../global/types';

import buildClassName from '../../../../util/buildClassName';
import { shortenAddress } from '../../../../util/shortenAddress';
import { shortenDomain } from '../../../../util/shortenDomain';
import getChainNetworkIcon from '../../../../util/swap/getChainNetworkIcon';

import styles from './Card.module.scss';

interface OwnProps {
  chains: ApiChain[];
  byChain?: Account['byChain'];
  withTextGradient?: boolean;
  isMinimized?: boolean;
  onClick: NoneToVoidFunction;
  onMouseEnter?: NoneToVoidFunction;
  onMouseLeave?: NoneToVoidFunction;
}

const MULTICHAIN_DOMAIN_LENGTH = 10;
const MULTICHAIN_ADDRESS_LENGTH = 6;

function AddressMenuButton({
  chains,
  withTextGradient,
  isMinimized,
  onClick,
  onMouseEnter,
  onMouseLeave,
  byChain,
}: OwnProps) {
  const chain = chains[0];
  if (!chain) return undefined;

  const isMultiChain = chains.length > 1;
  const { domain, address } = byChain?.[chain] ?? {};

  const multiChainButtonContent = useMemo(() => {
    if (!isMultiChain || !byChain) return undefined;

    const nodes: TeactNode[] = [];
    const chainsLength = chains.length;

    chains.forEach((chainItem, index) => {
      const { domain: chainDomain, address: chainAddress } = byChain[chainItem]!;
      const title = chainDomain
        ? shortenDomain(chainDomain, MULTICHAIN_DOMAIN_LENGTH)
        : shortenAddress(chainAddress, 0, MULTICHAIN_ADDRESS_LENGTH)!;

      nodes.push(
        <span key={`${chainItem}-item`} className={styles.multichainItem}>
          <img src={getChainNetworkIcon(chainItem)} alt="" className={styles.chainIcon} />
          <span className={styles.multichainAddress}>
            {title}
            {index < chainsLength - 1 && ','}
          </span>
        </span>,
      );
    });

    return nodes;
  }, [byChain, chains, isMultiChain]);

  return (
    <button
      type="button"
      className={buildClassName(styles.address, withTextGradient && 'gradientText')}
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
      onClick={onClick}
    >
      {multiChainButtonContent ? (
        <span className={buildClassName(styles.multichainList, 'itemName')}>
          {multiChainButtonContent}
        </span>
      ) : (
        <>
          <img src={getChainNetworkIcon(chain)} alt="" className={styles.chainIcon} />
          <span className={buildClassName(styles.itemName, 'itemName')}>
            {domain ? shortenDomain(domain) : shortenAddress(address!)}
          </span>
        </>
      )}
      {!isMinimized && <i className="icon-caret-down" aria-hidden />}
    </button>
  );
}

export default memo(AddressMenuButton);
