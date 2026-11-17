import React, { memo } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { formatSignedPercent } from '../../../util/formatNumber';

import IconWithTooltip from '../../ui/IconWithTooltip';
import Skeleton from '../../ui/Skeleton';

import styles from './InfoMetric.module.scss';

interface OwnProps {
  label: string;
  hint?: string;
  /** Absent while it loads, and a skeleton keeps its place */
  value?: string;
  changePercent?: number;
}

function InfoMetric({ label, hint, value, changePercent }: OwnProps) {
  return (
    <div className={styles.root}>
      <span className={styles.label}>
        {label}
        {hint && (
          <>
            {' '}
            <IconWithTooltip message={hint} size="small" />
          </>
        )}
      </span>
      {value === undefined ? <Skeleton className={styles.valueSkeleton} /> : (
        <span className={styles.value}>
          {value}
          {changePercent !== undefined && (
            <span
              className={buildClassName(
                styles.change,
                changePercent >= 0 ? styles.changePositive : styles.changeNegative,
              )}
            >
              {formatSignedPercent(changePercent)}
            </span>
          )}
        </span>
      )}
    </div>
  );
}

export default memo(InfoMetric);
