import React, { memo } from '../../lib/teact/teact';

import type { JettonMetadataInfo } from '../utils/giveaway';

import buildClassName from '../../util/buildClassName';

import styles from './TokenInfo.module.scss';

import DEFAULT_TOKEN_IMAGE_URL from '../../assets/coins/coin_ton.svg';

const DEFAULT_TOKEN_SYMBOL = 'Toncoin';

interface OwnProps {
  amount: string;
  jettonMetadata?: JettonMetadataInfo;
  className?: string;
}

function TokenInfo({
  amount,
  jettonMetadata,
  className,
}: OwnProps) {
  if (!jettonMetadata) {
    return (
      <div className={buildClassName(styles.tokenInfo, 'glare-image', className)} />
    );
  }

  const symbol = 'symbol' in jettonMetadata ? jettonMetadata.symbol : DEFAULT_TOKEN_SYMBOL;
  const imageUrl = 'image' in jettonMetadata ? jettonMetadata.image : DEFAULT_TOKEN_IMAGE_URL;

  return (
    <div className={buildClassName(styles.tokenInfo, className)}>
      <div className={styles.tokenInfoWrapper}>
        <div className={styles.tokenImageWrapper}>
          <img src={imageUrl} alt={symbol} className={styles.tokenImage} />
        </div>
        {amount} {symbol}
      </div>
    </div>
  );
}

export default memo(TokenInfo);
