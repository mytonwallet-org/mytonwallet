import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { TokenChartMode } from '../../../../global/types';

import {
  IS_CORE_WALLET,
  IS_EXPLORER,
  IS_EXTENSION,
  IS_TELEGRAM_APP,
  SELF_UNIVERSAL_HOST_URL,
} from '../../../../config';
import {
  selectCurrentAccountId,
  selectIsCurrentAccountViewMode,
  selectIsPasswordPresent,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { tryOpenNativeApp } from '../../../../util/deeplink';
import { IS_ELECTRON } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useQrScannerSupport from '../../../../hooks/useQrScannerSupport';

import Button from '../../../ui/Button';
import TabList from '../../../ui/TabList';
import AccountSelector from './AccountSelector';
import AppLockButton from './actionButtons/AppLockButton';
import BackButton from './actionButtons/BackButton';
import QrScannerButton from './actionButtons/QrScannerButton';
import SettingsButton from './actionButtons/SettingsButton';
import ToggleFullscreenButton from './actionButtons/ToggleFullscreenButton';
import ToggleLayoutButton from './actionButtons/ToggleLayoutButton';
import ToggleSensitiveDataButton from './actionButtons/ToggleSensitiveDataButton';

import styles from './Header.module.scss';

import logoSrc from '../../../../assets/logoMonochromeWhite.svg';

export const HEADER_HEIGHT_REM = 3;

interface OwnProps {
  isScrolled?: boolean;
  withBalance?: boolean;
  areTabsStuck?: boolean;
  isChartCardOpen?: boolean;
  tokenChartMode?: TokenChartMode;
  isNetWorthChartAvailable?: boolean;
  onTokenChartModeChange?: (mode: TokenChartMode) => void;
  onChartCardBack?: NoneToVoidFunction;
}

interface StateProps {
  isViewMode?: boolean;
  isAppLockEnabled?: boolean;
  isSensitiveDataHidden: boolean;
  isFullscreen: boolean;
  isTemporaryAccount: boolean;
}

const TOKEN_CHART_TABS = [
  { id: 0, title: 'Price' },
  { id: 1, title: 'Net Worth' },
];

function Header({
  isViewMode,
  withBalance,
  areTabsStuck,
  isScrolled,
  isAppLockEnabled,
  isSensitiveDataHidden,
  isFullscreen,
  isTemporaryAccount,
  isChartCardOpen,
  isNetWorthChartAvailable,
  tokenChartMode,
  onTokenChartModeChange,
  onChartCardBack,
}: OwnProps & StateProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const canToggleAppLayout = IS_EXTENSION || IS_ELECTRON;
  const isQrScannerSupported = useQrScannerSupport() && !isViewMode;
  const tokenChartActiveTab = tokenChartMode === 'netWorth' ? 1 : 0;
  const tokenChartTabs = useMemo(() => {
    return TOKEN_CHART_TABS.map((tab) => ({
      ...tab,
      title: lang(tab.title),
    }));
  // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [lang.code]);

  const handleTokenChartModeChange = useLastCallback((modeId: number) => {
    onTokenChartModeChange?.(modeId === 0 ? 'price' : 'netWorth');
  });

  const handleOpenInAppClick = (e: React.MouseEvent) => {
    e.preventDefault();
    tryOpenNativeApp(SELF_UNIVERSAL_HOST_URL);
  };

  if (isChartCardOpen) {
    const fullClassName = isPortrait
      ? buildClassName(
        styles.header,
        areTabsStuck && styles.areTabsStuck,
        isScrolled && styles.isScrolled,
      )
      : styles.header;

    return (
      <div className={fullClassName}>
        <div className={buildClassName(styles.headerInner, styles.chartCardHeader)}>
          <Button
            isSimple
            isText
            onClick={onChartCardBack}
            className={styles.chartCardBackButton}
            ariaLabel={lang('Back')}
          >
            <i className={buildClassName(styles.chartCardBackIcon, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <div className={styles.tokenModeTabsWrapper}>
            {isNetWorthChartAvailable ? (
              <TabList
                isActive
                tabs={tokenChartTabs}
                activeTab={tokenChartActiveTab}
                onSwitchTab={handleTokenChartModeChange}
                className={styles.tokenModeTabs}
                overlayClassName={styles.tokenModeTabsOverlay}
              />
            ) : (
              <span className={styles.tokenModeTitle}>{lang('Price')}</span>
            )}
          </div>
        </div>
      </div>
    );
  }

  if (isPortrait) {
    const fullClassName = buildClassName(
      styles.header,
      areTabsStuck && styles.areTabsStuck,
      isScrolled && styles.isScrolled,
    );
    const showBackButton = isTemporaryAccount && !IS_EXPLORER;
    const iconsAmount = IS_EXTENSION
      ? 1 + (showBackButton ? 1 : 0) + (isAppLockEnabled ? 1 : 0)
      : 1 + (isAppLockEnabled ? 1 : 0) + (IS_TELEGRAM_APP ? 1 : 0) + (canToggleAppLayout ? 1 : 0);

    if (IS_EXPLORER) {
      return (
        <div className={fullClassName}>
          <div className={styles.headerInner} style="--icons-amount: 3">
            <AccountSelector withBalance={withBalance} withAccountSelector={!IS_CORE_WALLET && !IS_EXPLORER} />
            <div className={styles.portraitActionsRight}>
              <a
                href={SELF_UNIVERSAL_HOST_URL}
                className={styles.openLink}
                onClick={handleOpenInAppClick}
              >
                <img src={logoSrc} alt="" />
                {lang('Open')}
              </a>
            </div>
          </div>
        </div>
      );
    }

    return (
      <div className={fullClassName}>
        <div className={styles.headerInner} style={`--icons-amount: ${iconsAmount}`}>
          {IS_EXTENSION ? (
            <div className={styles.portraitActionsLeft}>
              {showBackButton ? <BackButton isIconOnly /> : <QrScannerButton isViewMode={isViewMode} />}
              <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />
              {isAppLockEnabled && <AppLockButton />}
            </div>
          ) : (
            showBackButton ? <BackButton /> : <QrScannerButton isViewMode={isViewMode} />
          )}
          <AccountSelector withBalance={withBalance} withAccountSelector={!IS_CORE_WALLET && !IS_EXPLORER} />

          <div className={styles.portraitActionsRight}>
            {!IS_EXTENSION && isAppLockEnabled && <AppLockButton />}
            {!IS_EXTENSION && <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />}
            {IS_TELEGRAM_APP && <ToggleFullscreenButton isFullscreen={isFullscreen} />}
            {canToggleAppLayout && <ToggleLayoutButton />}
          </div>
        </div>
      </div>
    );
  }

  const showBackButton = isTemporaryAccount && !IS_EXPLORER;
  const buttonsAmount = Math.max(
    1 + (showBackButton ? 1 : 0) + (isAppLockEnabled ? 1 : 0) + (isQrScannerSupported ? 1 : 0),
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
          {showBackButton && <BackButton isIconOnly />}
          {!IS_EXPLORER && <ToggleSensitiveDataButton isSensitiveDataHidden={isSensitiveDataHidden} />}
          <QrScannerButton isViewMode={isViewMode} />
          {isAppLockEnabled && <AppLockButton />}
        </div>

        <AccountSelector withBalance={withBalance} withAccountSelector={!IS_CORE_WALLET && !IS_EXPLORER} />

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
