import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import renderText from '../../global/helpers/renderText';
import { getIsFaceIdAvailable, getIsTouchIdAvailable } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { PARTICLE_BURST_PARAMS, PARTICLE_PARAMS, setupParticles } from '../../util/particles';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import ImageWithParticles, {
  PARTICLE_COLORS_GREEN,
  PARTICLE_HEIGHT,
  PARTICLE_LANDSCAPE_HEIGHT,
} from '../ui/ImageWithParticles';
import Header from './Header';

import styles from './Auth.module.scss';

import touchIdSvg from '../../assets/settings/settings_biometrics.svg';
import faceIdSvg from '../../assets/settings/settings_face-id.svg';

interface OwnProps {
  isActive?: boolean;
  isLoading?: boolean;
  isImporting?: boolean;
}

const AuthChooseProtection = ({ isActive, isLoading, isImporting }: OwnProps) => {
  const { setupBiometricAuth, skipCreateBiometrics, resetAuth } = getActions();

  const lang = useLang();
  const canvasRef = useRef<HTMLCanvasElement>();
  const headerRef = useRef<HTMLDivElement>();
  const { isLandscape } = useDeviceScreen();

  const isFaceId = getIsFaceIdAvailable();
  const isTouchId = getIsTouchIdAvailable();
  const title = isFaceId
    ? lang('Use Face ID')
    : (isTouchId ? lang('Use Touch ID') : lang('enclave_use_biometrics'));

  useHistoryBack({
    isActive,
    onBack: resetAuth,
  });

  useLayoutEffect(() => {
    if (!isActive) return;

    return setupParticles(canvasRef.current!, {
      color: PARTICLE_COLORS_GREEN,
      ...PARTICLE_PARAMS,
      height: isLandscape ? PARTICLE_LANDSCAPE_HEIGHT : PARTICLE_HEIGHT,
    });
  }, [isActive, isLandscape]);

  const handleParticlesClick = useLastCallback(() => {
    setupParticles(canvasRef.current!, {
      color: PARTICLE_COLORS_GREEN,
      ...PARTICLE_PARAMS,
      ...PARTICLE_BURST_PARAMS,
      height: isLandscape ? PARTICLE_LANDSCAPE_HEIGHT : PARTICLE_HEIGHT,
    });
  });

  const handleSetupBiometrics = useLastCallback(() => {
    setupBiometricAuth();
  });

  const handleUsePassword = useLastCallback(() => {
    skipCreateBiometrics({ isImporting });
  });

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={title}
        topTargetRef={headerRef}
        onBackClick={resetAuth}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <ImageWithParticles
          canvasRef={canvasRef}
          imgPath={isFaceId ? faceIdSvg : touchIdSvg}
          className={styles.sticker}
          onClick={handleParticlesClick}
        />

        <div ref={headerRef} className={styles.title}>{title}</div>
        <p className={styles.info}>{renderText(lang('$auth_biometric_info'))}</p>

        <div className={styles.buttons}>
          <Button
            isPrimary
            className={styles.btn}
            isLoading={isLoading}
            onClick={!isLoading ? handleSetupBiometrics : undefined}
          >
            {lang(isFaceId ? 'Connect Face ID' : (isTouchId ? 'Connect Touch ID' : 'Connect Biometrics'))}
          </Button>
          <Button
            isText
            isDisabled={isLoading}
            className={buildClassName(styles.btn, styles.btn_text)}
            onClick={handleUsePassword}
          >
            {lang('Use Password')}
          </Button>
        </div>
      </div>
    </div>
  );
};

export default memo(AuthChooseProtection);
