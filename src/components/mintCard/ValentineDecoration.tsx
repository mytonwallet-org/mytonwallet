import React, { memo, useState } from '../../lib/teact/teact';

import { ANIMATION_LEVEL_MIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './ValentineDecoration.module.scss';

import valentineImageUrl from '../../assets/cards/valentine.svg';

interface OwnProps {
  animationLevel?: number;
  className?: string;
}

function ValentineDecoration({ animationLevel, className }: OwnProps) {
  const [animationKey, setAnimationKey] = useState(0);
  const shouldAnimate = animationLevel !== ANIMATION_LEVEL_MIN;

  const triggerAnimation = useLastCallback(() => {
    if (!shouldAnimate) return;
    setAnimationKey((current) => current + 1);
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.code !== 'Enter' && e.code !== 'Space') return;

    stopEvent(e);
    triggerAnimation();
  });

  return (
    <div
      className={buildClassName(styles.root, className)}
      role="button"
      tabIndex={0}
      onClick={triggerAnimation}
      onKeyDown={handleKeyDown}
    >
      <div
        key={`image-${animationKey}`}
        className={buildClassName(styles.imageWrap, animationKey > 0 && styles.imageWrapAnimated)}
      >
        <img
          src={valentineImageUrl}
          alt=""
          className={styles.image}
          aria-hidden
          loading="lazy"
          draggable={false}
        />
      </div>

      {animationKey > 0 && (
        <div key={`burst-${animationKey}`} className={styles.burst} aria-hidden>
          <span className={buildClassName(styles.particle, styles.particleOne)} />
          <span className={buildClassName(styles.particle, styles.particleTwo)} />
          <span className={buildClassName(styles.particle, styles.particleThree)} />
          <span className={buildClassName(styles.spark, styles.sparkOne)} />
          <span className={buildClassName(styles.spark, styles.sparkTwo)} />
        </div>
      )}
    </div>
  );
}

export default memo(ValentineDecoration);
