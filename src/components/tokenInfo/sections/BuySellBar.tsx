import React, { memo } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import buildStyle from '../../../util/buildStyle';
import { formatCompactCurrency } from '../../../util/formatNumber';

import styles from './BuySellBar.module.scss';

interface OwnProps {
  buy: number;
  sell: number;
  currencySymbol: string;
}

function BuySellBar({ buy, sell, currencySymbol }: OwnProps) {
  const total = buy + sell;
  // Without trades there is no ratio to show, and a zero-width segment would read as a one-sided market
  const buyShare = total > 0 ? buy / total : 0.5;

  return (
    <div className={styles.root}>
      <div
        className={buildClassName(styles.segment, styles.buy)}
        style={buildStyle(`--segment-share: ${buyShare}`)}
      >
        <span className={styles.value}>{formatCompactCurrency(buy, currencySymbol)}</span>
      </div>
      <div
        className={buildClassName(styles.segment, styles.sell)}
        style={buildStyle(`--segment-share: ${1 - buyShare}`)}
      >
        <span className={styles.value}>{formatCompactCurrency(sell, currencySymbol)}</span>
      </div>
    </div>
  );
}

export default memo(BuySellBar);
