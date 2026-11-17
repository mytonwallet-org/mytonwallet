import React, {
  memo, useEffect, useLayoutEffect, useRef,
} from '../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../global';

import type { Theme } from '../global/types';
import { AppState } from '../global/types';

import {
  ANIMATION_LEVEL_MIN,
  APP_NAME,
  INACTIVE_MARKER,
  IS_ANDROID_DIRECT,
  IS_EXPLORER,
  IS_GRAM_WALLET,
} from '../config';
import {
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsContentListOpen,
} from '../global/selectors';
import { useAccentColor } from '../util/accentColor';
import { setActiveTabChangeListener } from '../util/activeTabMonitor';
import buildClassName from '../util/buildClassName';
import { MINUTE } from '../util/dateFormat';
import getTestId from '../util/getTestId';
import { closeThisTab } from '../util/ledger/tab';
import { resolveRender } from '../util/renderPromise';
import resolveSlideTransitionName from '../util/resolveSlideTransitionName';
import {
  IS_ELECTRON, IS_LEDGER_EXTENSION_TAB, IS_LINUX,
} from '../util/windowEnvironment';
import { updateSizes } from '../util/windowSize';
import { callApi } from '../api';
import { SwapActivityModal, TransactionInfoModal, TransactionModal } from './main/modals/transaction';
import IFrameBrowser from './ui/IFrameBrowser';

import useAccountContentFade from '../hooks/useAccountContentFade';
import { useAppIntersectionObserver } from '../hooks/useAppIntersectionObserver';
import useAppTheme from '../hooks/useAppTheme';
import useBackgroundMode from '../hooks/useBackgroundMode';
import { useDeviceScreen } from '../hooks/useDeviceScreen';
import useFlag from '../hooks/useFlag';
import useForceUpdate from '../hooks/useForceUpdate';
import { useIsHomeToolbarHidden } from '../hooks/useHideHomeToolbar';
import useInterval from '../hooks/useInterval';
import useLastCallback from '../hooks/useLastCallback';
import useSyncEffect from '../hooks/useSyncEffect';
import useTimeout from '../hooks/useTimeout';

import Agent from './agent/AgentRuntime';
import AppEmpty from './AppEmpty';
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
import Futures from './futures/LazyFutures';
import FuturesModals from './futures/LazyModals';
import LedgerModal from './ledger/LedgerModal';
import Main from './main/Main';
import BackupModal from './main/modals/BackupModal';
import NftAttributesModal from './main/modals/NftAttributesModal';
import OffRampWidgetModal from './main/modals/OffRampWidgetModal';
import OnRampWidgetModal from './main/modals/OnRampWidgetModal';
import ReportNftModal from './main/modals/ReportNftModal';
import SignatureModal from './main/modals/SignatureModal';
import UnhideNftModal from './main/modals/UnhideNftModal';
import BottomBar from './main/sections/Actions/BottomBar';
import PortraitContent from './main/sections/Content/PortraitContent';
import HomeToolbar from './main/sections/Header/HomeToolbar';
import Toasts from './main/Toasts';
import WalletRenameModal from './main/WalletRenameModal';
import Market from './market/Market';
import MediaViewer from './mediaViewer/MediaViewer';
import MintCardModal from './mintCard/MintCardModal';
import Portfolio from './portfolio/Portfolio';
import Settings from './settings/Settings';
import SwapModal from './swap/SwapModal';
import TokenInfo from './tokenInfo/TokenInfo';
import TransferModal from './transfer/TransferModal';
import ConfettiContainer from './ui/ConfettiContainer';
import LoadingOverlay from './ui/LoadingOverlay';
import Transition from './ui/Transition';
import UpdateAvailable from './ui/UpdateAvailable';
import WalletConnectPayDataCollectionModal from './walletConnectPay/WalletConnectPayDataCollectionModal';
import WalletConnectPayModal from './walletConnectPay/WalletConnectPayModal';
import WalletConnectPayOptionSelectionModal from './walletConnectPay/WalletConnectPayOptionSelectionModal';

// import Test from './components/test/TestNoRedundancy';
import styles from './App.module.scss';
import mainStyles from './main/Main.module.scss';

interface StateProps {
  appState: AppState;
  accountId?: string;
  isBackupWalletModalOpen?: boolean;
  isHardwareModalOpen?: boolean;
  isCustomizeWalletModalOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isMarketOpen?: boolean;
  isFuturesOpen?: boolean;
  isPortfolioOpen?: boolean;
  currentTokenSlug?: string;
  marketTokenSlug?: string;
  isContentListOpen: boolean;
  isFullscreen: boolean;
  areSettingsOpen?: boolean;
  theme: Theme;
  accentColorIndex?: number;
  isAppReady?: boolean;
}

const APP_STATES_WITH_BOTTOM_BAR = new Set([
  AppState.Main, AppState.Agent, AppState.Settings, AppState.Explore, AppState.Market, AppState.Futures,
  AppState.TokenInfo, AppState.ContentList,
]);
const SLIDING_APP_STATES_WITH_BOTTOM_BAR = new Set([AppState.TokenInfo, AppState.ContentList]);
const APP_STATES_WITH_HOME_TOOLBAR = new Set([
  AppState.Main, AppState.Agent, AppState.Settings, AppState.Explore, AppState.Market,
]);
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
  isAgentOpen,
  isExploreOpen,
  isMarketOpen,
  isFuturesOpen,
  isPortfolioOpen,
  currentTokenSlug,
  marketTokenSlug,
  isContentListOpen,
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
    checkAppVersion,
  } = getActions();

  const { isPortrait } = useDeviceScreen();
  // Crossing the phone breakpoint swaps the portrait and landscape layouts at once: it is not a move to another screen,
  // and the two layouts would show the same screen twice while one faded into the other
  const isPortraitRef = useRef(isPortrait);
  const isLayoutSwitch = isPortraitRef.current !== isPortrait;
  isPortraitRef.current = isPortrait;

  const [isInactive, markInactive] = useFlag(false);
  const [canPrerenderMain, prerenderMain] = useFlag();
  const forceUpdate = useForceUpdate();
  const isContentListRenderedRef = useRef(isContentListOpen);

  const renderingKey = resolveRenderingKey({
    isInactive,
    areSettingsOpen,
    isAgentOpen,
    isExploreOpen,
    isMarketOpen,
    isFuturesOpen,
    isPortfolioOpen,
    currentTokenSlug,
    marketTokenSlug,
    isContentListOpen,
    isPortrait,
    appState,
  });
  const withBottomBar = isPortrait && (!IS_EXPLORER || isAppReady) && APP_STATES_WITH_BOTTOM_BAR.has(renderingKey);
  const hasPortraitToolbar = isPortrait && !IS_EXPLORER;
  const isToolbarHiddenByScreen = useIsHomeToolbarHidden();
  const isToolbarHidden = !APP_STATES_WITH_HOME_TOOLBAR.has(renderingKey) || isToolbarHiddenByScreen;
  // Screens sharing the bottom bar are sibling tabs, so they cross-fade into each other. The token and list
  // screens are the exception: the bar stays visible, but they slide in, as they have a back button.
  const withSlide = isPortrait && (!withBottomBar || SLIDING_APP_STATES_WITH_BOTTOM_BAR.has(renderingKey));
  const transitionName = isLayoutSwitch ? 'none' : withSlide ? resolveSlideTransitionName() : 'semiFade';

  // The closed list screen stays rendered until the transition that hides it ends, which only an animated one reports
  if (isContentListOpen) {
    isContentListRenderedRef.current = true;
  } else if (transitionName === 'none' || getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN) {
    isContentListRenderedRef.current = false;
  }

  const handleTransitionStop = useLastCallback(() => {
    if (isContentListOpen || !isContentListRenderedRef.current) return;

    isContentListRenderedRef.current = false;
    forceUpdate();
  });

  useTimeout(
    prerenderMain,
    renderingKey === AppState.Auth && !canPrerenderMain ? PRERENDER_MAIN_DELAY : undefined,
  );

  // Gram Wallet Web is deployed to a domain we do not own and has no store presence, so there is no version to nag about
  useInterval(checkAppVersion, IS_GRAM_WALLET ? undefined : APP_UPDATE_INTERVAL);

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
    document.documentElement.classList.toggle('with-home-toolbar', hasPortraitToolbar);
  }, [hasPortraitToolbar]);

  useLayoutEffect(() => {
    document.documentElement.classList.add('is-rendered');
    resolveRender();
  }, []);
  useLayoutEffect(() => {
    document.documentElement.classList.toggle('is-fullscreen', isFullscreen);
    requestAnimationFrame(updateSizes);
  }, [isFullscreen]);

  useSyncEffect(([previousAccountId]) => {
    // Keep the account carousel mounted while switching profiles, because account-specific panes reset in `Main`
    if (accountId && !previousAccountId) {
      mainKey += 1;
    }
  }, [accountId]);

  const accountContentRef = useAccountContentFade(accountId, !isPortrait || renderingKey === AppState.Main);
  const appTheme = useAppTheme(theme);
  useAccentColor('body', appTheme, accentColorIndex);

  useAppIntersectionObserver();

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: AppState) {
    const slideFullClassName = buildClassName(
      styles.appSlide,
      styles.appSlideContent,
      'custom-scroll',
      'app-slide-content',
    );

    switch (currentKey) {
      case AppState.Auth:
        return <Auth />;
      case AppState.Main: {
        return (
          <Transition
            name="semiFade"
            activeKey={mainKey}
            shouldCleanup
            nextKey={renderingKey === AppState.Auth && canPrerenderMain ? mainKey + 1 : undefined}
            className={styles.mainTab}
            slideClassName={slideFullClassName}
          >
            <Main
              key={mainKey}
              accountId={accountId}
              isActive={isActive}
            />
          </Transition>
        );
      }
      case AppState.Agent:
        return <Agent isActive={isActive} />;
      case AppState.Explore:
        return <Explore isActive={isActive} />;
      case AppState.Market:
        return <Market isActive={isActive} />;
      case AppState.Futures:
        // Another account starts its Futures from scratch, so its positions and history load right away
        return <Futures key={accountId} isActive={isActive} />;
      case AppState.Settings:
        return <Settings isActive={isActive} />;
      case AppState.Portfolio:
        return <Portfolio isActive={isActive} />;
      case AppState.TokenInfo:
        return <TokenInfo isActive={isActive} />;
      case AppState.ContentList:
        return (
          <div
            className={buildClassName(slideFullClassName, styles.appSlideContentWithOwnInset)}
            data-testid={isActive ? getTestId('content_list') : undefined}
          >
            <div className={mainStyles.portraitContainer}>
              {isContentListRenderedRef.current && <PortraitContent key={accountId} isListScreen />}
            </div>
          </div>
        );
      case AppState.Ledger:
        return <LedgerModal isOpen noBackdropClose onClose={closeThisTab} />;
      case AppState.Inactive:
        return <AppInactive />;
      case AppState.Empty:
        return <AppEmpty />;
    }
  }

  return (
    <>
      {IS_ELECTRON && <ElectronHeader withTitle />}

      <Transition
        ref={accountContentRef}
        name={transitionName}
        activeKey={renderingKey}
        renderCount={APP_STATE_RENDER_COUNT}
        shouldCleanup={!withBottomBar}
        className={styles.transitionContainer}
        onStop={handleTransitionStop}
        slideClassName={
          buildClassName(styles.appSlide, withBottomBar && styles.appSlide_fastTransition, 'custom-scroll')
        }
      >
        {renderContent}
      </Transition>

      {hasPortraitToolbar && (
        <HomeToolbar
          isHidden={isToolbarHidden}
          isOnFirstBackground={renderingKey === AppState.Agent || renderingKey === AppState.Explore}
          // The header of the list of chats reaches up under the toolbar
          isOverScreenHeader={renderingKey === AppState.Agent}
        />
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
          <SwapModal />
          <FuturesModals />
          <MintCardModal />
          <CustomizeWalletModal isOpen={isCustomizeWalletModalOpen} />
          <SignatureModal />
          <TransactionModal />
          <TransactionInfoModal />
          <SwapActivityModal />
          <DappConnectModal />
          <DappSignDataModal />
          <DappTransferModal />
          <OnRampWidgetModal />
          <OffRampWidgetModal />
          <WalletConnectPayModal />
          <WalletConnectPayOptionSelectionModal />
          <WalletConnectPayDataCollectionModal />
          <UnhideNftModal />
          <ReportNftModal />
          <NftAttributesModal />
          <Toasts />
          <WalletRenameModal />
          <Dialogs />
          <ConfettiContainer />
          <IFrameBrowser />
          <LoadingOverlay />
          {/* Outside `Main`, which portrait screens such as Portfolio and Agent replace. It stays off Auth, whose
          controls sit where the button floats. */}
          {!IS_ELECTRON && renderingKey !== AppState.Auth && <UpdateAvailable />}
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
    isAgentOpen: global.isAgentOpen,
    isExploreOpen: global.isExploreOpen,
    isMarketOpen: global.isMarketOpen,
    isFuturesOpen: global.isFuturesOpen,
    isPortfolioOpen: global.isPortfolioOpen,
    currentTokenSlug: selectCurrentAccountState(global)?.currentTokenSlug,
    marketTokenSlug: global.marketTokenSlug,
    isContentListOpen: selectIsContentListOpen(global),
    areSettingsOpen: global.areSettingsOpen,
    isFullscreen: Boolean(global.isFullscreen),
    theme: global.settings.theme,
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
    isAppReady: selectCurrentAccountState(global)?.isAppReady,
  };
})(App));

function resolveRenderingKey({
  isInactive,
  areSettingsOpen,
  isAgentOpen,
  isExploreOpen,
  isMarketOpen,
  isFuturesOpen,
  isPortfolioOpen,
  currentTokenSlug,
  marketTokenSlug,
  isContentListOpen,
  isPortrait,
  appState,
}: {
  isInactive: boolean;
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isMarketOpen?: boolean;
  isFuturesOpen?: boolean;
  isPortfolioOpen?: boolean;
  currentTokenSlug?: string;
  marketTokenSlug?: string;
  isContentListOpen: boolean;
  isPortrait: boolean;
  appState: AppState;
}) {
  if (isInactive) return AppState.Inactive;
  if (areSettingsOpen && isPortrait) return AppState.Settings;
  if (isAgentOpen && isPortrait) return AppState.Agent;
  if (isExploreOpen && isPortrait) return AppState.Explore;
  // A token opened from the market shows on top of the showcase, so the market tab stays selected.
  // A token opened in the wallet stays behind the market, like behind Explore
  if (isMarketOpen && isPortrait) {
    return currentTokenSlug && currentTokenSlug === marketTokenSlug ? AppState.TokenInfo : AppState.Market;
  }
  if (isFuturesOpen && isPortrait) return AppState.Futures;
  if (isPortfolioOpen && isPortrait) return AppState.Portfolio;
  // In landscape the token screen lives inside the main content, next to the wallet overview
  if (currentTokenSlug && isPortrait && appState === AppState.Main) return AppState.TokenInfo;
  if (isContentListOpen && isPortrait && appState === AppState.Main) return AppState.ContentList;
  return appState;
}
