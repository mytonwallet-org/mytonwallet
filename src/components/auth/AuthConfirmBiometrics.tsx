import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';
import { getActions } from '../../global';

import buildClassName from '../../util/buildClassName';
import { SECOND } from '../../util/dateFormat';
import { PARTICLE_BURST_PARAMS, PARTICLE_PARAMS, setupParticles } from '../../util/particles';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useTimeout from '../../hooks/useTimeout';

import Button from '../ui/Button';
import ImageWithParticles, {
  PARTICLE_COLORS_GREEN,
  PARTICLE_HEIGHT,
  PARTICLE_LANDSCAPE_HEIGHT,
} from '../ui/ImageWithParticles';
import Header from './Header';

import styles from './Auth.module.scss';

import imgPath from '../../assets/settings/settings_biometrics.svg';

interface OwnProps {
  isActive?: boolean;
  isLoading?: boolean;
  error?: string;
  biometricsStep?: 1 | 2;
}

const START_BIOMETRICS_CONFIRMATION_DELAY_MS = SECOND;

function AuthConfirmBiometrics({
  isActive,
  biometricsStep,
  error,
  isLoading,
}: OwnProps) {
  const {
    afterCreateBiometrics,
    resetAuth,
    cancelCreateBiometrics,
  } = getActions();

  const lang = useLang();
  const canvasRef = useRef<HTMLCanvasElement>();
  const headerRef = useRef<HTMLDivElement>();
  const { isLandscape } = useDeviceScreen();
  const shouldRenderSteps = Boolean(biometricsStep);
  const shouldRenderError = Boolean(error && !shouldRenderSteps);
  const renderingError = useCurrentOrPrev(error, true);

  useTimeout(afterCreateBiometrics, isActive ? START_BIOMETRICS_CONFIRMATION_DELAY_MS : undefined, [isActive]);
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

  useHistoryBack({
    isActive,
    onBack: resetAuth,
  });

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={lang('Turn On Biometrics')}
        topTargetRef={headerRef}
        onBackClick={resetAuth}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <ImageWithParticles
          canvasRef={canvasRef}
          imgPath={imgPath}
          alt={lang('Turn On Biometrics')}
          className={styles.sticker}
          onClick={handleParticlesClick}
        />
        <div ref={headerRef} className={styles.title}>{lang('Turn On Biometrics')}</div>

        {shouldRenderSteps && (
          <div className={styles.biometricsStep}>
            {lang(biometricsStep === 1 ? 'Step 1 of 2. Registration' : 'Step 2 of 2. Verification')}
          </div>
        )}
        {shouldRenderError && (
          <div className={buildClassName(styles.biometricsError)}>
            <div>{lang(renderingError || 'Unknown error')}</div>
            <div>{lang('Please try to confirm your biometrics again')}</div>
          </div>
        )}

        <div className={styles.buttons}>
          {shouldRenderError && (
            <Button
              isPrimary
              className={styles.btn}
              isDisabled={Boolean(biometricsStep) || isLoading}
              onClick={afterCreateBiometrics}
            >
              {lang('Try Again')}
            </Button>
          )}
          <Button
            isDisabled={Boolean(biometricsStep) || isLoading}
            className={styles.btn}
            onClick={cancelCreateBiometrics}
          >
            {lang('Cancel')}
          </Button>
        </div>
      </div>
    </div>
  );
}

export default memo(AuthConfirmBiometrics);
