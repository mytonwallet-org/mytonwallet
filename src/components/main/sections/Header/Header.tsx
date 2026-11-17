import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { IS_EXPLORER, IS_EXTENSION, IS_TELEGRAM_APP, SELF_UNIVERSAL_HOST_URL } from '../../../../config';
import {
  selectCurrentAccountId,
  selectHasPassword,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { tryOpenNativeApp } from '../../../../util/deeplink';
import { IS_ELECTRON } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useQrScannerSupport from '../../../../hooks/useQrScannerSupport';

import AccountSelector from './AccountSelector';
import AppLockButton from './actionButtons/AppLockButton';
import BackButton from './actionButtons/BackButton';
import QrScannerButton from './actionButtons/QrScannerButton';
import ToggleFullscreenButton from './actionButtons/ToggleFullscreenButton';
import ToggleLayoutButton from './actionButtons/ToggleLayoutButton';
import ToggleSensitiveDataButton from './actionButtons/ToggleSensitiveDataButton';

import styles from './Header.module.scss';

import logoSrc from '../../../../assets/logoMinimalistic.svg';

export const HEADER_HEIGHT_REM = 3;

const CAN_TOGGLE_APP_LAYOUT = IS_EXTENSION || IS_ELECTRON;

interface OwnProps {
  isScrolled?: boolean;
  withBalance?: boolean;
}

interface StateProps {
  isViewMode?: boolean;
  isAppLockEnabled?: boolean;
  isSensitiveDataHidden: boolean;
  isFullscreen: boolean;
  isTemporaryAccount: boolean;
}

function Header({
  isScrolled,
  withBalance,
  isViewMode,
  isAppLockEnabled,
  isSensitiveDataHidden,
  isFullscreen,
  isTemporaryAccount,
}: OwnProps & StateProps) {
  const lang = useLang();

  const { isPortrait } = useDeviceScreen();
  const isQrScannerSupported = useQrScannerSupport() && !isViewMode;

  const handleOpenInAppClick = (e: React.MouseEvent) => {
    e.preventDefault();
    tryOpenNativeApp(SELF_UNIVERSAL_HOST_URL);
  };

  if (IS_EXPLORER) {
    return (
      <div className={buildClassName(styles.header, isScrolled && styles.isScrolled)}>
        <div className={styles.headerInner} style="--icons-amount: 3">
          <AccountSelector withBalance={withBalance} />
          {isPortrait && (
            <div className={styles.portraitActionsRight}>
              <a
                href={SELF_UNIVERSAL_HOST_URL}
                className={styles.openLink}
                onClick={handleOpenInAppClick}
              >
                <img src={logoSrc} alt="" className={styles.mtLogo} />
                {lang('Open')}
              </a>
            </div>
          )}
        </div>
      </div>
    );
  }

  // Both action groups take the width of the wider one, so the account title stays centred
  const buttonsAmount = Math.max(
    1 + (isTemporaryAccount ? 1 : 0) + (isAppLockEnabled ? 1 : 0),
    (isQrScannerSupported ? 1 : 0) + (CAN_TOGGLE_APP_LAYOUT ? 1 : 0) + (IS_TELEGRAM_APP ? 1 : 0),
  );
  const buttonsAmountClassName = styles[`landscapeActionsButtons${buttonsAmount}`];
  const innerClassName = buildClassName(styles.headerInner, styles.withActions);

  return (
    <div className={styles.header}>
      <div className={innerClassName} style={`--icons-amount: ${buttonsAmount}`}>
        <div className={buildClassName(styles.landscapeActions, buttonsAmountClassName)}>
          {isTemporaryAccount && <BackButton isIconOnly />}
          <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />
          {isAppLockEnabled && <AppLockButton />}
        </div>

        <AccountSelector withAccountSelector />

        <div className={buildClassName(styles.landscapeActions, styles.landscapeActionsEnd, buttonsAmountClassName)}>
          <QrScannerButton isViewMode={isViewMode} />
          {IS_TELEGRAM_APP && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
          {CAN_TOGGLE_APP_LAYOUT && <ToggleLayoutButton />}
        </div>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>(
  (global): StateProps => {
    const {
      isFullscreen,
      currentTemporaryViewAccountId,
      settings: {
        isAppLockEnabled,
        isSensitiveDataHidden,
      },
    } = global;

    return {
      isViewMode: selectIsCurrentAccountViewMode(global),
      isAppLockEnabled: isAppLockEnabled && selectHasPassword(global),
      isFullscreen: Boolean(isFullscreen),
      isSensitiveDataHidden: Boolean(isSensitiveDataHidden),
      isTemporaryAccount: Boolean(currentTemporaryViewAccountId),
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(Header));
