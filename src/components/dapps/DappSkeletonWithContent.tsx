import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import Skeleton from '../ui/Skeleton';

import styles from './Dapp.module.scss';

interface OwnProps {
  rows?: DappSkeletonRow[];
  shouldRenderHeader?: boolean;
  shouldRenderHeroAmount?: boolean;
}

export type DappSkeletonRow = {
  isLarge?: boolean;
  hasFee?: boolean;
};

/** Only the placeholders: the caller provides the padded content around them, together with its buttons */
function DappSkeletonWithContent({
  rows,
  shouldRenderHeader = true,
  shouldRenderHeroAmount,
}: OwnProps) {
  return (
    <div className={buildClassName(styles.skeletonBackground, styles.skeleton)}>
      {shouldRenderHeader && (
        <div className={styles.requestHeader}>
          <div className={buildClassName(styles.headerPill, styles.headerPillSkeleton)}>
            <Skeleton className={buildClassName(styles.headerPillAvatarSkeleton, styles.headerPillLeadingIcon)} />
            <div className={styles.headerPillText}>
              <Skeleton className={styles.headerPillTitleSkeleton} />
              <Skeleton className={styles.headerPillSubtitleSkeleton} />
            </div>
          </div>
          <i className={styles.headerPillLink} aria-hidden />
          <div
            className={buildClassName(styles.headerPill, styles.headerPill_dapp, styles.headerPillSkeleton)}
          >
            <div className={buildClassName(styles.headerPillText, styles.headerPillText_dapp)}>
              <Skeleton className={styles.headerPillTitleSkeleton} />
              <Skeleton className={styles.headerPillSubtitleSkeleton} />
            </div>
            <Skeleton className={buildClassName(styles.headerPillAvatarSkeleton, styles.headerPillTrailingIcon)} />
          </div>
        </div>
      )}
      {shouldRenderHeroAmount && <Skeleton className={styles.heroAmountSkeleton} />}
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
