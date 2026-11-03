import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import styles from './AgentThreadList.module.scss';

interface OwnProps {
  isOpen: boolean;
}

// More rows than the tallest list shows; the placeholder clips the rest
const ROW_COUNT = 14;
// The placeholder fades out as the loaded rows fade in
const CLOSE_DURATION = 300;
const ROWS = Array.from({ length: ROW_COUNT }, (_, index) => index);

/** The chat rows' outlines with a shimmer, shown until the first page of chats loads, as on mobile */
function AgentThreadListSkeleton({ isOpen }: OwnProps) {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition({
    isOpen,
    withShouldRender: true,
    noMountTransition: true,
    closeDuration: CLOSE_DURATION,
    className: 'slow',
  });

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={styles.skeleton} role="status" aria-label={lang('Loading...')}>
      {ROWS.map((index) => (
        <div key={index} className={styles.skeletonRow}>
          <div className={buildClassName(styles.skeletonShape, styles.skeletonAvatar)} />
          <div className={styles.skeletonText}>
            <div className={styles.skeletonLine}>
              <div className={buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonTitle)} />
              <div className={buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonTime)} />
            </div>
            <div className={styles.skeletonLine}>
              <div className={buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonPreviewLong)} />
              <div className={buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonPreviewShort)} />
            </div>
            <div className={styles.skeletonLine}>
              <div className={buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonPreviewShort)} />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

export default memo(AgentThreadListSkeleton);
