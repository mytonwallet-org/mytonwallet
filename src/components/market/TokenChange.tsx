import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { formatPercent } from '../../util/formatNumber';

import styles from './Market.module.scss';

// `formatPercent` keeps one decimal below 10%, so a smaller change rounds to zero
const ZERO_CHANGE_THRESHOLD = 0.05;

interface OwnProps {
  change: number;
  className?: string;
}

function TokenChange({ change, className }: OwnProps) {
  // A zero change has no direction to show
  if (Math.abs(change) < ZERO_CHANGE_THRESHOLD) return undefined;

  const isPositive = change >= 0;

  return (
    <span className={buildClassName(styles.change, isPositive ? styles.change_up : styles.change_down, className)}>
      <i className={isPositive ? 'icon-arrow-up' : 'icon-arrow-down'} aria-hidden />
      {formatPercent(Math.abs(change))}
    </span>
  );
}

export default memo(TokenChange);
