import React, { memo } from '../../../../lib/teact/teact';

import { ANIMATED_STICKER_BIG_SIZE_PX, ANIMATED_STICKER_SMALL_SIZE_PX } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useLang from '../../../../hooks/useLang';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';

import styles from './NewWalletGreeting.module.scss';

interface Props {
  isActive?: boolean;
  mode: 'panel' | 'emptyList';
}

function NewWalletGreeting({ isActive, mode }: Props) {
  const lang = useLang();

  return (
    <div className={buildClassName(styles.container, styles[mode])}>
      <AnimatedIconWithPreview
        play={isActive}
        tgsUrl={ANIMATED_STICKERS_PATHS.hello}
        previewUrl={ANIMATED_STICKERS_PATHS.helloPreview}
        nonInteractive
        noLoop={false}
        size={mode === 'emptyList' ? ANIMATED_STICKER_BIG_SIZE_PX : ANIMATED_STICKER_SMALL_SIZE_PX}
      />

      <div className={styles.text}>
        <p className={styles.header}>
          {lang('You have just created a new wallet')}
        </p>
        <p className={styles.description}>
          {lang('Send, receive, and trade tokens and collectibles.')}
        </p>
      </div>
    </div>
  );
}

export default memo(NewWalletGreeting);
