import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useGridLimit from './hooks/useGridLimit';

import Skeleton from '../ui/Skeleton';

import styles from './Market.module.scss';

const MOVER_CARDS_COUNT = 5;
const GRID_SECTIONS_COUNT = 2;

function ShowcaseSkeleton() {
  const gridLimit = useGridLimit();

  return (
    <>
      <div className={styles.section}>
        {renderTitle()}
        <div className={styles.movers}>
          {Array.from({ length: MOVER_CARDS_COUNT }, (_, index) => (
            <Skeleton key={index} className={styles.moverCardSkeleton} />
          ))}
        </div>
      </div>
      {Array.from({ length: GRID_SECTIONS_COUNT }, (_, sectionIndex) => (
        <div key={sectionIndex} className={styles.section}>
          {renderTitle()}
          <div className={buildClassName(styles.card, styles.grid)}>
            {Array.from({ length: gridLimit }, (_, index) => (
              <div key={index} className={styles.gridItem}>
                <Skeleton className={styles.gridIconSkeleton} />
                <Skeleton className={styles.gridTextSkeleton} />
                <Skeleton className={styles.gridTextSkeleton} />
              </div>
            ))}
          </div>
        </div>
      ))}
    </>
  );
}

export default memo(ShowcaseSkeleton);

function renderTitle() {
  return (
    <div className={styles.sectionHeader}>
      <Skeleton className={styles.titleSkeleton} />
    </div>
  );
}
