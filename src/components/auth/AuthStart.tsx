import React, { memo, useLayoutEffect, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { type Theme } from '../../global/types';

import { APP_NAME, IS_CORE_WALLET, IS_EXPLORER } from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainsSupportingLedger } from '../../util/chain';
import { stopEvent } from '../../util/domEvents';
import { PARTICLE_BURST_PARAMS, type ParticleConfig, setupParticles } from '../../util/particles';
import { IS_LEDGER_SUPPORTED, REM } from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useAppTheme from '../../hooks/useAppTheme';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useMediaTransition from '../../hooks/useMediaTransition';
import { CLOSE_DURATION } from '../../hooks/useShowTransition';
import useTimeout from '../../hooks/useTimeout';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Checkbox from '../ui/Checkbox';
import { PARTICLE_HEIGHT, PARTICLE_LANDSCAPE_HEIGHT } from '../ui/ImageWithParticles';

import styles from './Auth.module.scss';

import logoDarkPath from '../../assets/logoDark.svg';
import logoLightPath from '../../assets/logoLight.svg';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  hasAccounts?: boolean;
  isLoading?: boolean;
  theme: Theme;
}

const PARTICLE_PARAMS: Partial<ParticleConfig> = {
  width: 20.125 * REM,
  height: 12.75 * REM,
  particleCount: 35,
  centerShift: [0, 22] as const,
  distanceLimit: 0.75,
};

const PARTICLE_COLORS_LIGHT = [0, 136 / 255, 204 / 255] as [number, number, number]; // #0088cc
const PARTICLE_COLORS_DARK = [70 / 255, 156 / 255, 236 / 255] as [number, number, number]; // #469CEC

function AuthStart({
  isActive,
  hasAccounts,
  isLoading,
  theme,
}: OwnProps & StateProps) {
  const {
    startCreatingWallet,
    startImportingWallet,
    openAbout,
    openHardwareWalletModal,
    resetAuth,
    openAuthImportWalletModal,
    openDisclaimer,
  } = getActions();

  const lang = useLang();
  const canvasRef = useRef<HTMLCanvasElement>();
  const { isLandscape } = useDeviceScreen();
  const appTheme = useAppTheme(theme);
  const logoPath = appTheme === 'light' ? logoLightPath : logoDarkPath;
  const [isLogoReady, markLogoReady] = useFlag();
  const [isLogoAnimated, markLogoAnimated] = useFlag();
  const logoRef = useMediaTransition<HTMLImageElement>(isLogoReady);
  const [isAccepted, setIsAccepted] = useState(false);

  useTimeout(markLogoAnimated, isLogoReady ? CLOSE_DURATION : undefined, [isLogoReady]);

  useLayoutEffect(() => {
    if (!isActive) return;

    return setupParticles(canvasRef.current!, {
      color: appTheme === 'light' ? PARTICLE_COLORS_LIGHT : PARTICLE_COLORS_DARK,
      ...PARTICLE_PARAMS,
      height: isLandscape ? PARTICLE_LANDSCAPE_HEIGHT : PARTICLE_HEIGHT,
    });
  }, [appTheme, isActive, isLandscape]);

  const handleParticlesClick = useLastCallback(() => {
    setupParticles(canvasRef.current!, {
      color: appTheme === 'light' ? PARTICLE_COLORS_LIGHT : PARTICLE_COLORS_DARK,
      ...PARTICLE_PARAMS,
      ...PARTICLE_BURST_PARAMS,
      height: isLandscape ? PARTICLE_LANDSCAPE_HEIGHT : PARTICLE_HEIGHT,
    });
  });

  function handleDisclaimerClick(e: React.MouseEvent<HTMLAnchorElement>) {
    stopEvent(e);

    openDisclaimer();
  }

  const handleImportHardwareWalletClick = useLastCallback(() => {
    openHardwareWalletModal({ chain: getChainsSupportingLedger()[0] }); // todo: Add a chain selector screen for Ledger auth
  });

  function renderSimpleImportForm() {
    return (
      <>
        <span className={styles.importText}>{lang('or import from')}</span>
        <div className={styles.coreWalletStartButtons}>
          <Button
            isDisabled={!isAccepted}
            className={styles.btn}
            onClick={!isLoading ? startImportingWallet : undefined}
          >
            {lang('Secret Words')}
          </Button>
          {IS_LEDGER_SUPPORTED && (
            <Button
              isDisabled={!isAccepted}
              className={styles.btn}
              onClick={!isLoading ? handleImportHardwareWalletClick : undefined}
            >
              {lang('Ledger')}
            </Button>
          )}
        </div>
      </>
    );
  }

  return (
    <div className={buildClassName(styles.container, 'custom-scroll')}>
      {hasAccounts && (
        <Button isSimple isText onClick={resetAuth} className={styles.headerBack}>
          <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
      )}

      <div
        className={styles.logoContainer}
        tabIndex={-1}
        role="button"
        onClick={handleParticlesClick}
      >
        <canvas ref={canvasRef} className={styles.logoParticles} />
        {IS_CORE_WALLET ? (
          <AnimatedIconWithPreview
            play={isActive}
            tgsUrl={ANIMATED_STICKERS_PATHS.coreWalletLogo}
            previewUrl={ANIMATED_STICKERS_PATHS.coreWalletLogoPreview}
            className={buildClassName(
              styles.logo,
              isLogoAnimated && styles.logoReadyToScale,
            )}
            noLoop={false}
            nonInteractive
          />
        ) : (
          <img
            ref={logoRef}
            src={logoPath}
            alt={APP_NAME}
            className={buildClassName(
              styles.logo,
              isLogoAnimated && styles.logoReadyToScale,
            )}
            onLoad={markLogoReady}
          />
        )}
      </div>

      <div className={buildClassName(styles.appName, 'rounded-font')}>{APP_NAME}</div>
      {IS_EXPLORER ? (
        <div className={styles.info}>
          {lang('Waiting for a View deeplink to display a wallet address.')}
        </div>
      ) : (
        <>
          <div className={styles.info}>
            {renderText(lang('$auth_intro'))}
          </div>

          {!IS_CORE_WALLET && (
            <Button
              isText
              className={buildClassName(styles.btn, styles.btn_about)}
              onClick={openAbout}
            >
              {lang('More about %app_name%', { app_name: APP_NAME })}{' '}›
            </Button>
          )}
          <div className={buildClassName(styles.buttons, IS_CORE_WALLET && styles.coreWalletButtons)}>
            <Checkbox
              checked={isAccepted}
              onChange={setIsAccepted}
              className={IS_CORE_WALLET ? styles.responsibilityCheckboxSimple : styles.responsibilityCheckbox}
              contentClassName={styles.responsibilityCheckboxContent}
            >
              {lang('$accept_terms_with_link', {
                link: (
                  <a
                    href="#"
                    target="_blank"
                    rel="noreferrer"
                    className={styles.responsibilityCheckboxLink}
                    onClick={handleDisclaimerClick}
                  >
                    {lang('use the wallet responsibly')}
                  </a>
                ) },
              )}
            </Checkbox>
            <Button
              isPrimary
              isDisabled={!isAccepted}
              className={styles.btn}
              isLoading={isLoading}
              onClick={!isLoading ? startCreatingWallet : undefined}
            >
              {lang('Create New Wallet')}
            </Button>
            {IS_CORE_WALLET ? renderSimpleImportForm() : (
              <Button
                isText
                isDisabled={!isAccepted}
                className={buildClassName(styles.btn, styles.btn_text)}
                onClick={!isLoading ? openAuthImportWalletModal : undefined}
              >
                {lang('Import Existing Wallet')}
              </Button>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    hasAccounts: Boolean(selectCurrentAccountId(global)),
    isLoading: global.auth.isLoading,
    theme: global.settings.theme,
  };
})(AuthStart));
