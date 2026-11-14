import React, { memo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { APP_NAME } from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';
import { IS_ANDROID, IS_IOS } from '../../util/windowEnvironment';

import useLang from '../../hooks/useLang';

import GramDiamond from '../common/GramDiamond';
import Button from '../ui/Button';
import TextDivider from '../ui/TextDivider';
import AuthLegalNotice from './AuthLegalNotice';
import WelcomeParticles from './WelcomeParticles';

import styles from './GramAuthStart.module.scss';

import appleIcon from '../../assets/gramWelcome/apple.svg';
import googlePlayIcon from '../../assets/gramWelcome/googlePlay.svg';
import qrIcon from '../../assets/gramWelcome/qr.svg';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  hasAccounts: boolean;
  isLoading?: boolean;
}

const APP_STORE_URL = 'https://gramwallet.io/ios-store';
const GOOGLE_PLAY_URL = 'https://gramwallet.io/android-store';
const DOWNLOAD_URL = 'https://get.gramwallet.io/';
const DIAMOND_SIZE = 184;
const DIAMOND_HOVER_SPEED = 2;
const DIAMOND_MAX_GROW = 1.15;

function GramAuthStart({ isActive, hasAccounts, isLoading }: OwnProps & StateProps) {
  const { startCreatingWallet, openAuthImportWalletModal, openAbout, resetAuth } = getActions();
  const lang = useLang();
  const logoRef = useRef<HTMLDivElement>();
  const isMobile = IS_IOS || IS_ANDROID;
  const downloadSource = isMobile ? 'mobile_web' : 'desktop_app';

  return (
    <div className={buildClassName(styles.root, 'custom-scroll')}>
      <div className={styles.content}>
        {hasAccounts && (
          <Button isSimple isText className={styles.back} onClick={resetAuth}>
            <i className="icon-chevron-left" aria-hidden />
            {lang('Back')}
          </Button>
        )}
        <div className={styles.hero}>
          <WelcomeParticles isActive={isActive} interactionRef={logoRef} />
          <div ref={logoRef} className={styles.logo}>
            <GramDiamond
              isOpen={isActive}
              size={DIAMOND_SIZE}
              hoverSpeed={DIAMOND_HOVER_SPEED}
              shouldRotateOnTap
              maxGrow={DIAMOND_MAX_GROW}
              className={styles.diamond}
            />
          </div>
          <h1 className={buildClassName(styles.title, 'rounded-font')}>{APP_NAME}</h1>
          <p className={styles.description}>
            {renderText(lang('$auth_intro').replace(/\s*\n\s*/g, ' ').trim())}{' '}
            <Button isSimple isText className={styles.more} onClick={openAbout}>
              {lang('$auth_more')}{' '}›
            </Button>
          </p>
          <div className={styles.stores}>
            {!IS_ANDROID && (
              <a
                href={`${APP_STORE_URL}?utm_source=${downloadSource}`}
                target="_blank"
                rel="noopener noreferrer"
                className={buildClassName(styles.store, styles.apple,
                  isMobile && styles.mobileStore)}
                aria-label="App Store"
              >
                <span className={styles.storeIcon}>
                  <span className={styles.appleIcon} style={`mask-image: url("${appleIcon}");`} aria-hidden />
                </span>
                <span className={buildClassName(styles.storeLabel, styles.appleLabel,
                  isMobile && styles.mobileStoreLabel)}
                >
                  App Store
                </span>
              </a>
            )}
            {!IS_IOS && (
              <a
                href={`${GOOGLE_PLAY_URL}?utm_source=${downloadSource}`}
                target="_blank"
                rel="noopener noreferrer"
                className={buildClassName(styles.store, styles.googlePlay,
                  isMobile && styles.mobileStore)}
                aria-label="Google Play"
              >
                <span className={styles.storeIcon}><img src={googlePlayIcon} alt="" /></span>
                <span className={buildClassName(styles.storeLabel, styles.googlePlayLabel,
                  isMobile && styles.mobileStoreLabel)}
                >
                  Google Play
                </span>
              </a>
            )}
            {!IS_IOS && !IS_ANDROID && (
              <a
                href={`${DOWNLOAD_URL}?utm_source=${downloadSource}`}
                target="_blank"
                rel="noopener noreferrer"
                className={buildClassName(styles.store, styles.qrButton)}
                aria-label={lang('Scan QR')}
              >
                <span className={styles.qrIcon} style={`mask-image: url("${qrIcon}");`} aria-hidden />
              </a>
            )}
          </div>
        </div>
        <div className={styles.footer}>
          <TextDivider className={styles.divider}>{lang('or use web version')}</TextDivider>
          <div className={styles.actions}>
            <Button
              isPrimary
              testId={getTestId('intro_create_wallet')}
              className={styles.action}
              isLoading={isLoading}
              onClick={startCreatingWallet}
            >
              {lang('Create New Wallet')}
            </Button>
            <Button
              isText
              testId={getTestId('intro_import_wallet')}
              className={styles.action}
              isDisabled={isLoading}
              onClick={openAuthImportWalletModal}
            >
              {lang('Import Existing Wallet')}
            </Button>
          </div>
          <AuthLegalNotice className={styles.terms} />
        </div>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => ({
  hasAccounts: Boolean(selectCurrentAccountId(global)),
  isLoading: global.auth.isLoading,
}))(GramAuthStart));
