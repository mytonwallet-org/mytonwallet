import React, { memo, useEffect } from '../../lib/teact/teact';

import { requestMutation } from '../../lib/fasterdom/fasterdom';
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
const AVATAR_CLASS_NAME = buildClassName(styles.skeletonShape, styles.skeletonAvatar);
const TITLE_CLASS_NAME = buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonTitle);
const TIME_CLASS_NAME = buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonTime);
const LONG_PREVIEW_CLASS_NAME = buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonPreviewLong);
const SHORT_PREVIEW_CLASS_NAME = buildClassName(styles.skeletonShape, styles.skeletonBar, styles.skeletonPreviewShort);

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

  // Every shape raises its band by its own distance from the top, so that one band runs down them all
  useEffect(() => {
    const root = ref.current;
    if (!shouldRender || !root) return;

    const { top } = root.getBoundingClientRect();
    const shapes = Array.from(root.querySelectorAll<HTMLElement>(`.${styles.skeletonShape}`));
    const offsets = shapes.map((shape) => shape.getBoundingClientRect().top - top);
    requestMutation(() => {
      shapes.forEach((shape, index) => shape.style.setProperty('--skeleton-offset', `${offsets[index]}px`));
    });
  }, [ref, shouldRender]);

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={styles.skeleton} role="status" aria-label={lang('Loading...')}>
      {ROWS.map((index) => (
        <div key={index} className={styles.skeletonRow}>
          <div className={AVATAR_CLASS_NAME} />
          <div className={styles.skeletonText}>
            <div className={styles.skeletonLine}>
              <div className={TITLE_CLASS_NAME} />
              <div className={TIME_CLASS_NAME} />
            </div>
            <div className={styles.skeletonLine}>
              <div className={LONG_PREVIEW_CLASS_NAME} />
              <div className={SHORT_PREVIEW_CLASS_NAME} />
            </div>
            <div className={styles.skeletonLine}>
              <div className={SHORT_PREVIEW_CLASS_NAME} />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

export default memo(AgentThreadListSkeleton);
