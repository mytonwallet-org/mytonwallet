import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions } from '../../global';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { vibrateOnSuccess } from '../../util/haptics';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive?: boolean;
  hardwareWalletsAmount?: number;
  isImporting?: boolean;
}

function AuthCongratulations({
  isActive,
  hardwareWalletsAmount,
  isImporting,
}: OwnProps) {
  const { afterCongratulations, requestConfetti } = getActions();

  const lang = useLang();

  useEffect(() => {
    if (isActive) {
      requestConfetti();
      void vibrateOnSuccess();
    }
  }, [isActive]);

  const handleClick = useLastCallback(() => {
    afterCongratulations({ isImporting: isImporting && !hardwareWalletsAmount });
  });

  function getInfo() {
    if (isImporting) {
      return lang('$wallet_import_done', hardwareWalletsAmount ?? 0, 'i');
    }

    return lang('$wallet_create_done');
  }

  return (
    <div className={buildClassName(styles.container, 'custom-scroll')}>
      <AnimatedIconWithPreview
        play={isActive}
        tgsUrl={ANIMATED_STICKERS_PATHS.guard}
        previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
        noLoop={false}
        nonInteractive
        className={styles.sticker}
      />
      <div className={styles.title}>{lang('All Set!')}</div>
      <div className={styles.info}>
        <p><b>{getInfo()}</b></p>
        <p>{renderText(lang('$wallet_done_description'))}</p>
      </div>

      <div className={styles.buttons}>
        <Button
          isPrimary
          className={styles.btn}
          onClick={handleClick}
        >
          {lang('Open Wallet')}
        </Button>
      </div>
    </div>
  );
}

export default memo(AuthCongratulations);
