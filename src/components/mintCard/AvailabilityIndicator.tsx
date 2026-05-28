import React, { memo } from '../../lib/teact/teact';

import type { ApiCardInfo } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import { formatNumber } from '../../util/formatNumber';
import { round } from '../../util/round';

import useLang from '../../hooks/useLang';

import styles from './MintCardModal.module.scss';

interface OwnProps {
  cardInfo?: ApiCardInfo;
  label?: string;
  className?: string;
  progress?: number;
}

function AvailabilityIndicator({ cardInfo, label, className, progress }: OwnProps) {
  const lang = useLang();
  const { all, notMinted } = cardInfo || {};

  if (all !== undefined && notMinted !== undefined) {
    const sold = all - notMinted;
    const leftAmount = lang('%amount% left', { amount: formatNumber(notMinted) });
    const soldAmount = lang('%amount% sold', { amount: formatNumber(sold) });

    return (
      <div className={buildClassName(styles.availability, className)}>
        <div
          className={styles.progress}
          style={`--progress: ${round(notMinted / all, 2)};`}
        >
          <div className={buildClassName(styles.amount, styles.amountInner, styles.amountLeft)}>{leftAmount}</div>
          <div className={buildClassName(styles.amount, styles.amountInner, styles.amountSold)}>{soldAmount}</div>
        </div>
        <div className={buildClassName(styles.amount, styles.amountLeft)}>{leftAmount}</div>
        <div className={buildClassName(styles.amount, styles.amountSold)}>{soldAmount}</div>
      </div>
    );
  }

  const fallbackText = label || lang('This card has been sold out');

  return (
    <div className={buildClassName(styles.availability, className)}>
      {progress !== undefined && (
        <div className={styles.progress} style={`--progress: ${round(progress, 2)};`}>
          <div className={buildClassName(styles.amount, styles.amountInner, styles.center)}>{fallbackText}</div>
        </div>
      )}
      {!progress && <div className={styles.soldOut}>{fallbackText}</div>}
    </div>
  );
}

export default memo(AvailabilityIndicator);
