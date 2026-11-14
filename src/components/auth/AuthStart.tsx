import React, { memo, useEffect, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import {
  APP_INSTALL_URL, APP_NAME, IS_EXPLORER, IS_GRAM_WALLET, NEW_APP_URL,
  PRODUCTION_URL,
} from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';
import { vibrate } from '../../util/haptics';
import {
  IS_LEGACY_APP_HOST, IS_NEW_WALLET_CREATION_HIDDEN,
} from '../../util/windowEnvironment';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useMediaTransition from '../../hooks/useMediaTransition';
import { CLOSE_DURATION } from '../../hooks/useShowTransition';
import useTimeout from '../../hooks/useTimeout';

import Button from '../ui/Button';
import AuthLegalNotice from './AuthLegalNotice';
import WelcomeParticles from './WelcomeParticles';

import styles from './Auth.module.scss';

import logoWebpPath from '../../assets/logo.webp';
import gramWalletLogoPath from '../../assets/logoGramWallet.svg';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  hasAccounts?: boolean;
  isLoading?: boolean;
}

const NEW_DOMAIN = new URL(PRODUCTION_URL).hostname;

function AuthStart({
  isActive,
  hasAccounts,
  isLoading,
}: OwnProps & StateProps) {
  const {
    startCreatingWallet,
    openAbout,
    resetAuth,
    openAuthImportWalletModal,
  } = getActions();

  const lang = useLang();
  const interactionRef = useRef<HTMLDivElement>();
  const [isLogoReady, markLogoReady] = useFlag();
  const [isLogoAnimated, markLogoAnimated] = useFlag();
  const logoRef = useMediaTransition<HTMLImageElement>(isLogoReady);

  useTimeout(markLogoAnimated, isLogoReady ? CLOSE_DURATION : undefined, [isLogoReady]);

  useEffect(() => {
    const logo = interactionRef.current!;
    function handlePress(event: PointerEvent) {
      if (event.isPrimary && event.button === 0) vibrate(true);
    }
    logo.addEventListener('pointerdown', handlePress);
    return () => logo.removeEventListener('pointerdown', handlePress);
  }, []);

  return (
    <>
      {IS_LEGACY_APP_HOST && (
        <div className={styles.legacyBar}>
          {lang('This version is deprecated. Re-import your wallets on %new_domain% or %download_app%.', {
            new_domain: (
              <a href={NEW_APP_URL} target="_blank" rel="noopener noreferrer" className={styles.legacyBarLink}>
                {NEW_DOMAIN}
              </a>
            ),
            download_app: (
              <a href={APP_INSTALL_URL} target="_blank" rel="noopener noreferrer" className={styles.legacyBarLink}>
                {lang('download the app')}
              </a>
            ),
          })}
        </div>
      )}
      <div className={buildClassName(
        styles.container, 'custom-scroll', IS_LEGACY_APP_HOST && styles.containerWithLegacyBar,
      )}
      >
        {hasAccounts && (
          <Button isSimple isText onClick={resetAuth} className={styles.headerBack}>
            <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
        )}

        <div className={styles.logoContainer}>
          <WelcomeParticles
            isActive={isActive}
            interactionRef={interactionRef}
            className={styles.logoParticles}
          />
          <div ref={interactionRef} className={styles.logoInteraction}>
            <img
              ref={logoRef}
              src={IS_GRAM_WALLET ? gramWalletLogoPath : logoWebpPath}
              alt={APP_NAME}
              className={buildClassName(
                styles.logo,
                isLogoAnimated && styles.logoReadyToScale,
              )}
              onLoad={markLogoReady}
            />
          </div>
        </div>

        <div className={buildClassName(styles.appName, 'brand-font')}>{APP_NAME}</div>
        {IS_EXPLORER ? (
          <div className={styles.info}>
            {lang('Waiting for a View deeplink to display a wallet address.')}
          </div>
        ) : (
          <>
            <div className={styles.info}>
              {renderText(lang('$auth_intro'))}
            </div>

            <Button
              isText
              className={buildClassName(styles.btn, styles.btn_about)}
              onClick={openAbout}
            >
              {lang('More about %app_name%', { app_name: APP_NAME })}{' '}›
            </Button>
            <div className={styles.buttons}>
              {!IS_NEW_WALLET_CREATION_HIDDEN && (
                <Button
                  isPrimary
                  testId={getTestId('intro_create_wallet')}
                  className={styles.btn}
                  isLoading={isLoading}
                  onClick={!isLoading ? startCreatingWallet : undefined}
                >
                  {lang('Create New Wallet')}
                </Button>
              )}
              <Button
                isText
                testId={getTestId('intro_import_wallet')}
                isDisabled={isLoading}
                className={buildClassName(styles.btn, styles.btn_text)}
                onClick={!isLoading ? openAuthImportWalletModal : undefined}
              >
                {lang('Import Existing Wallet')}
              </Button>
            </div>
            <AuthLegalNotice className={styles.legalNotice} />
          </>
        )}
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    hasAccounts: Boolean(selectCurrentAccountId(global)),
    isLoading: global.auth.isLoading,
  };
})(AuthStart));
