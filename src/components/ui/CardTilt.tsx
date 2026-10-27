import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef } from '../../lib/teact/teact';

import type { CardMotionFrame } from '../../util/card/types';

import buildClassName from '../../util/buildClassName';

import useCardPress from '../../hooks/useCardPress';

import styles from './CardTilt.module.scss';

interface OwnProps {
  children: TeactNode;
  className?: string;
  isDisabled?: boolean;
  onMotionFrame?: (frame: CardMotionFrame) => void;
}

/**
 * The outer element (`className`) must cover the card exactly, since the pointer position is measured against it.
 * Buttons and links inside keep their own gestures unless they have `data-card-play-allowed`.
 */
function CardTilt({
  children,
  className,
  isDisabled,
  onMotionFrame,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();
  const rotatorRef = useRef<HTMLDivElement>();

  useCardPress({ cardRef: ref, rotatorRef, isDisabled, onMotionFrame });

  return (
    <div ref={ref} className={buildClassName(styles.root, className)}>
      <div ref={rotatorRef} className={buildClassName(styles.rotator, isDisabled && styles.disabled)}>
        <div className={styles.plane}>
          {children}
        </div>
      </div>
    </div>
  );
}

export default CardTilt;
