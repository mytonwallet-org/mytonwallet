import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import Skeleton from '../ui/Skeleton';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface OwnProps {
  rows?: DappSkeletonRow[];
}

export type DappSkeletonRow = {
  isLarge?: boolean;
  hasFee?: boolean;
};

function DappSkeletonWithContent({ rows }: OwnProps) {
  return (
    <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
      <div className={styles.transactionDirection}>
        <div className={styles.transactionDirectionLeftSkeleton}>
          <Skeleton className={buildClassName(styles.nameSkeleton, styles.accountTitleSkeleton)} />
          <Skeleton className={buildClassName(styles.descSkeleton, styles.accountBalanceSkeleton)} />
        </div>
        <div className={styles.transactionDirectionRightSkeleton}>
          <Skeleton className={styles.dappInfoIconSkeleton} />
          <div className={styles.dappInfoDataSkeleton}>
            <Skeleton className={buildClassName(styles.nameSkeleton, styles.nameDappSkeleton)} />
            <Skeleton className={buildClassName(styles.descSkeleton, styles.descDappSkeleton)} />
          </div>
        </div>
      </div>
      {rows?.map(renderRow)}
    </div>
  );
}

export default memo(DappSkeletonWithContent);

function renderRow({ isLarge, hasFee }: DappSkeletonRow) {
  return (
    <div className={styles.rowContainerSkeleton}>
      <Skeleton className={buildClassName(styles.rowLabelSkeleton, isLarge && styles.rowTextLargeSkeleton)} />
      <Skeleton className={buildClassName(styles.rowSkeleton, isLarge && styles.rowLargeSkeleton)} />
      {hasFee && <Skeleton className={styles.rowFeeSkeleton} />}
    </div>
  );
}
