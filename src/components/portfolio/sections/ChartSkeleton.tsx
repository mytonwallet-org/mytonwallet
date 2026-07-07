import React, { memo } from '../../../lib/teact/teact';

import Skeleton from '../../ui/Skeleton';

import styles from './ChartSkeleton.module.scss';

// Varying widths so the pills wrap to roughly two rows, like the real chart legend
const LEGEND_PILL_WIDTHS = ['4rem', '5rem', '4.5rem', '3.5rem', '4.25rem', '4.75rem'];

function ChartSkeleton() {
  return (
    <>
      <Skeleton className={styles.plot} />
      <Skeleton className={styles.minimap} />

      <div className={styles.legend}>
        {LEGEND_PILL_WIDTHS.map((width) => (
          <Skeleton key={width} className={styles.pill} style={`width: ${width}`} />
        ))}
      </div>
    </>
  );
}

export default memo(ChartSkeleton);
