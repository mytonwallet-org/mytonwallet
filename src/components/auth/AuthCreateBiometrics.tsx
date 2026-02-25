import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AuthMethod } from '../../global/types';

import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive?: boolean;
  method?: AuthMethod;
}

const AuthCreateBiometrics = ({
  isActive,
  method,
}: OwnProps) => {
  const {
    startCreatingBiometrics,
    resetAuth,
    skipCreateBiometrics,
  } = getActions();

  const lang = useLang();
  const headerRef = useRef<HTMLDivElement>();
  const isImporting = method !== 'createAccount';
  const title = lang(isImporting ? 'Wallet is imported!' : 'Wallet is ready!');

  useHistoryBack({
    isActive,
    onBack: resetAuth,
  });

  const handleUsePasswordClick = useLastCallback(() => {
    skipCreateBiometrics({ isImporting });
  });

  const description = getDoesUsePinPad()
    ? 'Use biometric authentication or create a passcode to protect it.'
    : 'Use biometric authentication or create a password to protect it.';

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={title}
        topTargetRef={headerRef}
        onBackClick={resetAuth}
      />
      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.guard}
          previewUrl={ANIMATED_STICKERS_PATHS.guardPreview}
          noLoop={false}
          nonInteractive
          className={styles.sticker}
        />
        <div ref={headerRef} className={styles.title}>{title}</div>
        <p className={styles.info}>
          {lang(description)}
        </p>

        <div className={styles.buttons}>
          <Button
            isPrimary
            className={styles.btn}
            onClick={startCreatingBiometrics}
          >
            {lang('Connect Biometrics')}
          </Button>
          <Button
            isText
            className={buildClassName(styles.btn, styles.btn_text)}
            onClick={handleUsePasswordClick}
          >
            {lang(getDoesUsePinPad() ? 'Use Passcode' : 'Use Password')}
          </Button>
        </div>
      </div>
    </div>
  );
};

export default memo(AuthCreateBiometrics);
