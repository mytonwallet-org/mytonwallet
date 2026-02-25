import React, { memo } from '../../lib/teact/teact';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../config';
import { ANIMATED_STICKERS_PATHS } from '../../components/ui/helpers/animatedAssets';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';

import styles from './LoadingPage.module.scss';

type OwnProps = {
  subtitle?: string;
};

function LoadingPage({ subtitle }: OwnProps) {
  return (
    <div className={styles.container}>
      <AnimatedIconWithPreview
        play
        tgsUrl={ANIMATED_STICKERS_PATHS.forge}
        previewUrl={ANIMATED_STICKERS_PATHS.forgePreview}
        size={ANIMATED_STICKER_BIG_SIZE_PX}
        className={styles.sticker}
        noLoop={false}
        nonInteractive
        forceInBackground
      />
      <h2 className={styles.title}>Preparing Balance Chart</h2>
      <p className={styles.subtitle}>{subtitle || 'Analyzing wallet data and balance history...'}</p>
    </div>
  );
}

export default memo(LoadingPage);
