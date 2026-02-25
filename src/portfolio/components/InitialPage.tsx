import React, { memo } from '../../lib/teact/teact';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../config';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';

import styles from './InitialPage.module.scss';

import duckStairsUp from '../../assets/lottie/duck_stairs_up.tgs';
import duckStairsUpPreview from '../../assets/lottiePreview/duck_stairs_up.png';

function InitialPage() {
  return (
    <div className={styles.container}>
      <AnimatedIconWithPreview
        play
        tgsUrl={duckStairsUp}
        previewUrl={duckStairsUpPreview}
        size={ANIMATED_STICKER_BIG_SIZE_PX}
        className={styles.sticker}
        noLoop={false}
        nonInteractive
        forceInBackground
      />
      <h2 className={styles.title}>Portfolio Tracker</h2>
      <p className={styles.subtitle}>
        Connect MyTonWallet to view your assets
        <br />
        and track your balance over time.
      </p>
    </div>
  );
}

export default memo(InitialPage);
