import React, { memo, useMemo } from '../../lib/teact/teact';

import type { NftTransfer } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';

import styles from './NftChips.module.scss';

interface OwnProps {
  nfts: NftTransfer[];
  className?: string;
}

const LIMIT = 10;

function NftChips({ nfts, className }: OwnProps) {
  const lang = useLang();
  const [isCollapsed, , expand] = useFlag(true);
  const shouldRenderExpander = isCollapsed && nfts.length > LIMIT + 1;
  const renderedNfts = useMemo(
    () => (shouldRenderExpander ? nfts.slice(0, LIMIT) : nfts),
    [shouldRenderExpander, nfts],
  );

  function renderNft(nft: NftTransfer) {
    return (
      <div key={nft.address} className={styles.nft}>
        <img src={nft.thumbnail} alt={nft.name} className={styles.image} />
        <span className={styles.name}>{nft.name || nft.address}</span>
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.root, 'custom-scroll', className)}>
      {renderedNfts.map(renderNft)}
      {shouldRenderExpander && (
        <button type="button" className={styles.expander} onClick={() => expand()}>
          +{lang('%amount% NFTs', { amount: nfts.length - LIMIT })}
        </button>
      )}
    </div>
  );
}

export default memo(NftChips);
