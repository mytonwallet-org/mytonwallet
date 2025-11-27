import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { IS_CORE_WALLET, IS_EXTENSION, IS_TELEGRAM_APP } from '../../../../config';
import {
  selectCurrentAccountId,
  selectIsCurrentAccountViewMode,
  selectIsPasswordPresent,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { IS_ELECTRON } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useQrScannerSupport from '../../../../hooks/useQrScannerSupport';

import AccountSelector from './AccountSelector';
import AppLockButton from './actionButtons/AppLockButton';
import BackButton from './actionButtons/BackButton';
import QrScannerButton from './actionButtons/QrScannerButton';
import SettingsButton from './actionButtons/SettingsButton';
import ToggleFullscreenButton from './actionButtons/ToggleFullscreenButton';
import ToggleLayoutButton from './actionButtons/ToggleLayoutButton';
import ToggleSensitiveDataButton from './actionButtons/ToggleSensitiveDataButton';

import styles from './Header.module.scss';

export const HEADER_HEIGHT_REM = 3;

interface OwnProps {
  isScrolled?: boolean;
  withBalance?: boolean;
  areTabsStuck?: boolean;
}

interface StateProps {
  isViewMode?: boolean;
  isAppLockEnabled?: boolean;
  isSensitiveDataHidden: boolean;
  isFullscreen: boolean;
  isTemporaryAccount: boolean;
}

function Header({
  isViewMode,
  withBalance,
  areTabsStuck,
  isScrolled,
  isAppLockEnabled,
  isSensitiveDataHidden,
  isFullscreen,
  isTemporaryAccount,
}: OwnProps & StateProps) {
  const { isPortrait } = useDeviceScreen();
  const canToggleAppLayout = IS_EXTENSION || IS_ELECTRON;
  const isQrScannerSupported = useQrScannerSupport() && !isViewMode;

  if (isPortrait) {
    const fullClassName = buildClassName(
      styles.header,
      areTabsStuck && styles.areTabsStuck,
      isScrolled && styles.isScrolled,
    );
    const iconsAmount = 1 + (isAppLockEnabled ? 1 : 0) + (IS_TELEGRAM_APP ? 1 : 0) + (canToggleAppLayout ? 1 : 0);

    return (
      <div className={fullClassName}>
        <div className={styles.headerInner} style={`--icons-amount: ${iconsAmount}`}>
          {isTemporaryAccount ? <BackButton /> : <QrScannerButton isViewMode={isViewMode} />}
          <AccountSelector withBalance={withBalance} withAccountSelector={!IS_CORE_WALLET} />

          <div className={styles.portraitActions}>
            {isAppLockEnabled && <AppLockButton />}
            <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />
            {IS_TELEGRAM_APP && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
            {canToggleAppLayout && <ToggleLayoutButton />}
          </div>
        </div>
      </div>
    );
  }

  const buttonsAmount = Math.max(
    1 + (isTemporaryAccount ? 1 : 0) + (isAppLockEnabled ? 1 : 0) + (isQrScannerSupported ? 1 : 0),
    1 + (canToggleAppLayout ? 1 : 0) + (IS_TELEGRAM_APP ? 1 : 0),
  );

  return (
    <div className={styles.header}>
      <div className={styles.headerInner}>
        <div className={buildClassName(
          styles.landscapeActions,
          styles[`landscapeActionsButtons${buttonsAmount}`],
          styles.landscapeActionsStart,
        )}
        >
          {isTemporaryAccount && <BackButton isIconOnly />}
          <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />
          <QrScannerButton isViewMode={isViewMode} />
          {isAppLockEnabled && <AppLockButton />}
        </div>

        <AccountSelector withBalance={withBalance} withAccountSelector={!IS_CORE_WALLET} />

        <div className={buildClassName(
          styles.landscapeActions,
          buttonsAmount > 1 && styles[`landscapeActionsButtons${buttonsAmount}`],
          styles.landscapeActionsEnd,
        )}
        >
          {IS_TELEGRAM_APP && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
          {canToggleAppLayout && <ToggleLayoutButton />}
          <SettingsButton />
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

    const isPasswordPresent = selectIsPasswordPresent(global);
    const isViewMode = selectIsCurrentAccountViewMode(global);

    return {
      isViewMode,
      isAppLockEnabled: isAppLockEnabled && isPasswordPresent,
      isFullscreen: Boolean(isFullscreen),
      isSensitiveDataHidden: Boolean(isSensitiveDataHidden),
      isTemporaryAccount: Boolean(currentTemporaryViewAccountId),
    };
  },
  (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
)(Header));
