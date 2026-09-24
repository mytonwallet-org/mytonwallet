import type { TeactNode } from '../../lib/teact/teact';
import React, { useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useCardTilt from '../../hooks/useCardTilt';
import { useMediaQuery } from '../../hooks/useMediaQuery';

import styles from './CardTilt.module.scss';

export type CardGlare = 'radial' | 'spot';

interface OwnProps {
  children: TeactNode;
  className?: string;
  isDisabled?: boolean;
  glare: CardGlare;
}

/**
 * Wraps a card-shaped element in a pointer-driven 3D tilt with a glare on top.
 *
 * The wrapper is laid out by the caller: `className` is applied to the outer element, which has to
 * cover the card exactly, because the pointer position is measured against it. The glare is drawn
 * at `z-index` 2, so any content that must stay readable needs a higher one.
 *
 * The `radial` glare stays lit and turns with the tilt, and `spot` follows the pointer.
 */
function CardTilt({
  children,
  className,
  isDisabled,
  glare,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  // The system preference stands on its own. Someone who asked the OS for less motion gets none
  // here, whatever the in-app animation settings say.
  const isMotionDisabled = isDisabled || hasReducedMotion;

  useCardTilt({ cardRef: ref, isDisabled: isMotionDisabled });

  return (
    <div ref={ref} className={buildClassName(styles.root, className)}>
      <div className={buildClassName(styles.rotator, isMotionDisabled && styles.disabled)}>
        {children}
        {!isMotionDisabled && (
          <div className={buildClassName(styles.glare, styles[glare])}>
            {glare === 'spot' && <div className={styles.spotMover} />}
          </div>
        )}
      </div>
    </div>
  );
}

export default CardTilt;
