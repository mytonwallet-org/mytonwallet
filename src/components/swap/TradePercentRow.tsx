import React, { memo } from '../../lib/teact/teact';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  /** The shares of the largest amount, in percent */
  percents: number[];
  isDisabled?: boolean;
  formatPercent: (percent: number) => string;
  onSelect: (percent: number) => void;
}

/** The buttons under the amount of a trade form, which take a share of the largest amount */
function TradePercentRow({
  percents, isDisabled, formatPercent, onSelect,
}: OwnProps) {
  return (
    <div className={styles.percentRow}>
      {percents.map((percent) => (
        <button
          key={percent}
          type="button"
          className={styles.percentButton}
          disabled={isDisabled}
          onClick={() => onSelect(percent)}
        >
          {formatPercent(percent)}
        </button>
      ))}
    </div>
  );
}

export default memo(TradePercentRow);
