import React, { memo, useEffect, useLayoutEffect } from '../lib/teact/teact';
import { getActions, withGlobal } from '../global';

import type { Theme } from '../global/types';
import { AppState } from '../global/types';

import {
  APP_NAME,
  INACTIVE_MARKER,
  IS_ANDROID_DIRECT,
  IS_CAPACITOR,
  IS_CORE_WALLET,
  IS_EXPLORER,
} from '../config';
import { selectCurrentAccountId, selectCurrentAccountSettings, selectCurrentAccountState } from '../global/selectors';
import { useAccentColor } from '../util/accentColor';
import { setActiveTabChangeListener } from '../util/activeTabMonitor';
import buildClassName from '../util/buildClassName';
import { MINUTE } from '../util/dateFormat';
import { closeThisTab } from '../util/ledger/tab';
import { resolveRender } from '../util/renderPromise';
import {
  IS_ANDROID, IS_ELECTRON, IS_IOS, IS_LEDGER_EXTENSION_TAB, IS_LINUX,
} from '../util/windowEnvironment';
import { updateSizes } from '../util/windowSize';
import { callApi } from '../api';
import { SwapActivityModal, TransactionInfoModal, TransactionModal } from './main/modals/transaction';
import IFrameBrowser from './ui/IFrameBrowser';

import { useAppIntersectionObserver } from '../hooks/useAppIntersectionObserver';
import useAppTheme from '../hooks/useAppTheme';
import useBackgroundMode from '../hooks/useBackgroundMode';
import { useDeviceScreen } from '../hooks/useDeviceScreen';
import useFlag from '../hooks/useFlag';
import useInterval from '../hooks/useInterval';
import useSyncEffect from '../hooks/useSyncEffect';
import useTimeout from '../hooks/useTimeout';

import AppInactive from './AppInactive';
import AppLocked from './appLocked/AppLocked';
import Auth from './auth/Auth';
import AuthImportWalletModal from './auth/AuthImportWalletModal';
import CustomizeWalletModal from './customizeWallet/CustomizeWalletModal';
import DappConnectModal from './dapps/DappConnectModal';
import DappSignDataModal from './dapps/DappSignDataModal';
import DappTransferModal from './dapps/DappTransferModal';
import Dialogs from './Dialogs';
import ElectronHeader from './electron/ElectronHeader';
import Explore from './explore/Explore';
import LedgerModal from './ledger/LedgerModal';
import Main from './main/Main';
import BackupModal from './main/modals/BackupModal';
import NftAttributesModal from './main/modals/NftAttributesModal';
import OffRampWidgetModal from './main/modals/OffRampWidgetModal';
import OnRampWidgetModal from './main/modals/OnRampWidgetModal';
import QrScannerModal from './main/modals/QrScannerModal';
import SignatureModal from './main/modals/SignatureModal';
import UnhideNftModal from './main/modals/UnhideNftModal';
import BottomBar from './main/sections/Actions/BottomBar';
import Toasts from './main/Toasts';
import MediaViewer from './mediaViewer/MediaViewer';
import MintCardModal from './mintCard/MintCardModal';
import Settings from './settings/Settings';
import SettingsModal from './settings/SettingsModal';
import SwapModal from './swap/SwapModal';
import TransferModal from './transfer/TransferModal';
import ConfettiContainer from './ui/ConfettiContainer';
import InAppBrowser from './ui/InAppBrowser';
import LoadingOverlay from './ui/LoadingOverlay';
import Transition from './ui/Transition';

// import Test from './components/test/TestNoRedundancy';
import styles from './App.module.scss';

interface StateProps {
  appState: AppState;
  accountId?: string;
  isBackupWalletModalOpen?: boolean;
  isQrScannerOpen?: boolean;
  isHardwareModalOpen?: boolean;
  isCustomizeWalletModalOpen?: boolean;
  isExploreOpen?: boolean;
  isFullscreen: boolean;
  areSettingsOpen?: boolean;
  theme: Theme;
  accentColorIndex?: number;
  isAppReady?: boolean;
}

const APP_STATES_WITH_BOTTOM_BAR = new Set([AppState.Main, AppState.Settings, AppState.Explore]);
const APP_UPDATE_INTERVAL = (IS_ELECTRON && !IS_LINUX) || IS_ANDROID_DIRECT
  ? 5 * MINUTE
  : undefined;
const PRERENDER_MAIN_DELAY = 1200;
let mainKey = 0;

const APP_STATE_RENDER_COUNT = Object.keys(AppState).length / 2;

function App({
  appState,
  accountId,
  isBackupWalletModalOpen,
  isHardwareModalOpen,
  isCustomizeWalletModalOpen,
  isQrScannerOpen,
  isExploreOpen,
  isFullscreen,
  areSettingsOpen,
  theme,
  accentColorIndex,
  isAppReady,
}: StateProps) {
  const {
    closeBackupWalletModal,
    closeHardwareWalletModal,
    closeSettings,
    cancelCaching,
    closeQrScanner,
    checkAppVersion,
  } = getActions();

  const { isPortrait } = useDeviceScreen();
  const areSettingsInModal = !isPortrait;

  const [isInactive, markInactive] = useFlag(false);
  const [canPrerenderMain, prerenderMain] = useFlag();

  const renderingKey = isInactive
    ? AppState.Inactive
    : areSettingsOpen && !areSettingsInModal
      ? AppState.Settings
      : isExploreOpen && isPortrait
        ? AppState.Explore : appState;
  const withBottomBar = isPortrait && (!IS_EXPLORER || isAppReady) && APP_STATES_WITH_BOTTOM_BAR.has(renderingKey);
  const transitionName = withBottomBar
    ? 'semiFade'
    : isPortrait
      ? (IS_ANDROID ? 'slideFadeAndroid' : IS_IOS ? 'slideLayers' : 'slideFade')
      : 'semiFade';

  useTimeout(
    prerenderMain,
    renderingKey === AppState.Auth && !canPrerenderMain ? PRERENDER_MAIN_DELAY : undefined,
  );

  useInterval(checkAppVersion, IS_CORE_WALLET ? undefined : APP_UPDATE_INTERVAL);

  useEffect(() => {
    document.documentElement.classList.toggle('with-bottombar', withBottomBar);
  }, [withBottomBar]);

  useEffect(() => {
    updateSizes();
    setActiveTabChangeListener(() => {
      document.title = `${APP_NAME} ${INACTIVE_MARKER}`;

      markInactive();
      closeSettings();
      cancelCaching();
    });
  }, [markInactive]);

  useBackgroundMode(() => {
    void callApi('setIsAppFocused', false);
  }, () => {
    void callApi('setIsAppFocused', true);
  }, IS_LEDGER_EXTENSION_TAB);

  useLayoutEffect(() => {
    document.documentElement.classList.add('is-rendered');
    resolveRender();
  }, []);
  useLayoutEffect(() => {
    document.documentElement.classList.toggle('is-fullscreen', isFullscreen);
    requestAnimationFrame(updateSizes);
  }, [isFullscreen]);

  useSyncEffect(() => {
    if (accountId) {
      mainKey += 1;
    }
  }, [accountId]);

  const appTheme = useAppTheme(theme);
  useAccentColor('body', appTheme, accentColorIndex);

  useAppIntersectionObserver();

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: AppState) {
    switch (currentKey) {
      case AppState.Auth:
        return <Auth />;
      case AppState.Main: {
        const slideFullClassName = buildClassName(
          styles.appSlide,
          styles.appSlideContent,
          'custom-scroll',
          'app-slide-content',
        );
        return (
          <Transition
            name="semiFade"
            activeKey={mainKey}
            shouldCleanup
            nextKey={renderingKey === AppState.Auth && canPrerenderMain ? mainKey + 1 : undefined}
            slideClassName={slideFullClassName}
          >
            <Main
              key={mainKey}
              isActive={isActive}
            />
          </Transition>
        );
      }
      case AppState.Explore:
        return <Explore isActive={isActive} />;
      case AppState.Settings:
        return <Settings isActive={isActive} />;
      case AppState.Ledger:
        return <LedgerModal isOpen noBackdropClose onClose={closeThisTab} />;
      case AppState.Inactive:
        return <AppInactive />;
    }
  }

  return (
    <>
      {IS_ELECTRON && <ElectronHeader withTitle />}

      <Transition
        name={transitionName}
        activeKey={renderingKey}
        renderCount={APP_STATE_RENDER_COUNT}
        shouldCleanup={!withBottomBar}
        className={styles.transitionContainer}
        slideClassName={
          buildClassName(styles.appSlide, withBottomBar && styles.appSlide_fastTransition, 'custom-scroll')
        }
      >
        {renderContent}
      </Transition>

      {areSettingsInModal && (
        <SettingsModal
          isOpen={areSettingsOpen}
          onClose={closeSettings}
        >
          <Settings isActive={!!areSettingsOpen} isInsideModal />
        </SettingsModal>
      )}
      <AppLocked />
      <MediaViewer />
      {!isInactive && (
        <>
          <AuthImportWalletModal />
          <LedgerModal isOpen={isHardwareModalOpen} onClose={closeHardwareWalletModal} />
          <BackupModal
            isOpen={isBackupWalletModalOpen}
            onClose={closeBackupWalletModal}
          />
          <TransferModal />
          {!IS_CORE_WALLET && (
            <>
              <SwapModal />
              <MintCardModal />
              <CustomizeWalletModal isOpen={isCustomizeWalletModalOpen} />
            </>
          )}
          <SignatureModal />
          <TransactionModal />
          <TransactionInfoModal />
          <SwapActivityModal />
          <DappConnectModal />
          <DappSignDataModal />
          <DappTransferModal />
          <OnRampWidgetModal />
          <OffRampWidgetModal />
          <UnhideNftModal />
          <NftAttributesModal />
          {IS_CAPACITOR && (
            <QrScannerModal
              isOpen={isQrScannerOpen}
              onClose={closeQrScanner}
            />
          )}
          <Toasts />
          <Dialogs />
          <ConfettiContainer />
          {IS_CAPACITOR ? <InAppBrowser /> : <IFrameBrowser />}
          <LoadingOverlay />
        </>
      )}
      {withBottomBar && <BottomBar />}
    </>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    appState: global.appState,
    accountId: selectCurrentAccountId(global),
    isBackupWalletModalOpen: global.isBackupWalletModalOpen,
    isHardwareModalOpen: global.isHardwareModalOpen,
    isCustomizeWalletModalOpen: global.isCustomizeWalletModalOpen,
    isExploreOpen: global.isExploreOpen,
    areSettingsOpen: global.areSettingsOpen,
    isQrScannerOpen: global.isQrScannerOpen,
    isFullscreen: Boolean(global.isFullscreen),
    theme: global.settings.theme,
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
    isAppReady: selectCurrentAccountState(global)?.isAppReady,
  };
})(App));
