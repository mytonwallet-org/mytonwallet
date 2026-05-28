import React, { memo } from '../../../../lib/teact/teact';

import type { SqueezeState } from './hooks/useDraggablePill';

import buildClassName from '../../../../util/buildClassName';

import styles from './Pill.module.scss';

interface OwnProps {
  isDragging: boolean;
  squeeze?: SqueezeState;
}

// Sliding indicator for a draggable segmented control. Reads `--tab-count`, `--active-index`
// and `--drag-offset-px` from the capsule ancestor; pair with `useDraggablePill`.
function Pill({ isDragging, squeeze }: OwnProps) {
  return (
    <div className={buildClassName(styles.wrapper, isDragging && styles.dragging)}>
      <div
        className={buildClassName(
          styles.pill,
          squeeze && (squeeze.animationKey === 'a' ? styles.squeezeA : styles.squeezeB),
        )}
        data-direction={squeeze?.direction}
      />
    </div>
  );
}

export default memo(Pill);
