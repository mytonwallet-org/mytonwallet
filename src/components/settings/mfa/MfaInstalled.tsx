import React, { memo } from '../../../lib/teact/teact';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../../config';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useLang from '../../../hooks/useLang';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';

import settingsStyles from '../Settings.module.scss';
import styles from './Mfa.module.scss';

interface OwnProps {
  isSlideActive?: boolean;
  onClick: () => void;
}

function MfaInstalled({ isSlideActive, onClick }: OwnProps) {
  const lang = useLang();

  return (
    <div className={settingsStyles.slide}>
      <div
        className={buildClassName(settingsStyles.content, 'custom-scroll')}
      >
        <AnimatedIconWithPreview
          tgsUrl={ANIMATED_STICKERS_PATHS.happy}
          previewUrl={ANIMATED_STICKERS_PATHS.happyPreview}
          play={isSlideActive}
          size={ANIMATED_STICKER_BIG_SIZE_PX}
          nonInteractive
          noLoop={false}
          className={buildClassName(settingsStyles.sticker, styles.sticker)}
        />

        <div className={styles.title}>{lang('All Set!')}</div>

        <div className={styles.description}>
          {lang('Telegram will be used to confirm transfers and important actions.')}
        </div>

        <div className={styles.actions}>
          <Button
            isPrimary
            className={styles.button}
            onClick={onClick}
          >
            {lang('Done')}
          </Button>
        </div>
      </div>
    </div>
  );
}

export default memo(MfaInstalled);
