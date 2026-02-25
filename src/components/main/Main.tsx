import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiStakingState, ApiTokenWithPrice } from '../../api/types';
import { ActiveTab, ContentTab, type Theme, type TokenChartMode } from '../../global/types';

import { IS_CORE_WALLET, IS_EXPLORER } from '../../config';
import {
  selectAccountStakingState,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsHardwareAccount,
  selectIsOffRampAllowed,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
  selectToken,
} from '../../global/selectors';
import { useAccentColor } from '../../util/accentColor';
import { isNetWorthChartAvailable } from '../../util/assets/netWorth';
import buildClassName from '../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../util/captureEvents';
import { getStakingStateStatus } from '../../util/staking';
import {
  IS_ELECTRON, IS_TOUCH_ENV, REM,
} from '../../util/windowEnvironment';
import { calcSafeAreaTop } from './helpers/calcSafeAreaTop';

import useAppTheme from '../../hooks/useAppTheme';
import useBackgroundMode, { isBackgroundModeActive } from '../../hooks/useBackgroundMode';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectOnce from '../../hooks/useEffectOnce';
import useElementVisibility from '../../hooks/useElementVisibility';
import useFlag from '../../hooks/useFlag';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePreventPinchZoomGesture from '../../hooks/usePreventPinchZoomGesture';

import LinkingDomainModal from '../domain/LinkingDomainModal';
import RenewDomainModal from '../domain/RenewDomainModal';
import InvoiceModal from '../receive/InvoiceModal';
import ReceiveModal from '../receive/ReceiveModal';
import StakeModal from '../staking/StakeModal';
import StakingClaimModal from '../staking/StakingClaimModal';
import StakingInfoModal from '../staking/StakingInfoModal';
import UnstakeModal from '../staking/UnstakeModal';
import Transition from '../ui/Transition';
import UpdateAvailable from '../ui/UpdateAvailable';
import VestingModal from '../vesting/VestingModal';
import VestingPasswordModal from '../vesting/VestingPasswordModal';
import MainSkeleton from './MainSkeleton';
import AccountSelectorModal from './modals/accountSelector/AccountSelectorModal';
import PromotionModal from './modals/PromotionModal';
import { LandscapeActions, PortraitActions } from './sections/Actions';
import PromoteWallet from './sections/Actions/PromoteWallet';
import Card from './sections/Card';
import Content from './sections/Content';
import Header, { HEADER_HEIGHT_REM } from './sections/Header/Header';
import Warnings from './sections/Warnings';

import styles from './Main.module.scss';

interface OwnProps {
  isActive?: boolean;
}

type StateProps = {
  currentTokenSlug?: string;
  currentToken?: ApiTokenWithPrice;
  stakingState?: ApiStakingState;
  isTestnet?: boolean;
  isLedger?: boolean;
  isViewMode: boolean;
  isStakingInfoModalOpen?: boolean;
  isSwapDisabled?: boolean;
  isStakingDisabled?: boolean;
  isOnRampDisabled?: boolean;
  isOffRampAllowed?: boolean;
  isMediaViewerOpen?: boolean;
  isAppReady?: boolean;
  theme: Theme;
  accentColorIndex?: number;
};

const UPDATE_SWAPS_INTERVAL_NOT_FOCUSED = 15000; // 15 sec
const UPDATE_SWAPS_INTERVAL = 3000; // 3 sec

function Main({
  isActive,
  currentTokenSlug,
  stakingState,
  isTestnet,
  isViewMode,
  isLedger,
  isStakingInfoModalOpen,
  isSwapDisabled,
  isStakingDisabled,
  isOnRampDisabled,
  isOffRampAllowed,
  isMediaViewerOpen,
  isAppReady,
  theme,
  accentColorIndex,
  currentToken,
}: OwnProps & StateProps) {
  const {
    selectToken,
    openBackupWalletModal,
    setActiveContentTab,
    closeStakingInfo,
    openStakingInfoOrStart,
    changeCurrentStaking,
    setLandscapeActionsActiveTabIndex,
    loadExploreSites,
    updatePendingSwaps,
  } = getActions();

  const lang = useLang();
  const cardRef = useRef<HTMLDivElement>();
  const portraitContainerRef = useRef<HTMLDivElement>();
  const landscapeContainerRef = useRef<HTMLDivElement>();

  const safeAreaTop = calcSafeAreaTop();
  const [isFocused, markIsFocused, unmarkIsFocused] = useFlag(!isBackgroundModeActive());
  const [areTabsStuck, setAreTabsStuck] = useState(false);
  const [tokenChartMode, setTokenChartMode] = useState<TokenChartMode>('price');
  const intersectionRootMarginTop = HEADER_HEIGHT_REM * REM + safeAreaTop;

  const stakingStatus = stakingState ? getStakingStateStatus(stakingState) : 'inactive';

  useBackgroundMode(unmarkIsFocused, markIsFocused);

  usePreventPinchZoomGesture(isMediaViewerOpen);

  const { isPortrait, isLandscape } = useDeviceScreen();

  useEffectOnce(() => {
    if (IS_CORE_WALLET) return;

    loadExploreSites({ isLandscape, langCode: lang.code });
  });

  useInterval(updatePendingSwaps, isFocused ? UPDATE_SWAPS_INTERVAL : UPDATE_SWAPS_INTERVAL_NOT_FOCUSED);

  // Use scroll detection for portrait mode
  const { isVisible: isPageAtTop } = useElementVisibility({
    isDisabled: !isPortrait || !isActive,
    targetRef: cardRef,
    rootMargin: `-${intersectionRootMarginTop}px 0px 0px 0px`,
    threshold: [1],
  });

  const { isVisible: shouldHideBalanceInHeader } = useElementVisibility({
    isDisabled: !isPortrait || !isActive,
    targetRef: cardRef,
    rootMargin: `-${intersectionRootMarginTop}px 0px 0px 0px`,
  });

  const handleChartCardClose = useLastCallback(() => {
    selectToken({ slug: undefined });
    setActiveContentTab({ tab: ContentTab.Assets });
  });

  const isNetWorthChartSupported = isNetWorthChartAvailable(currentToken);

  useEffect(() => {
    if (!currentTokenSlug || !isNetWorthChartSupported) {
      setTokenChartMode('price');
    }
  }, [currentTokenSlug, isNetWorthChartSupported]);

  const handleTokenChartModeChange = useLastCallback((mode: TokenChartMode) => {
    setTokenChartMode(mode);
  });

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isPortrait || !portraitContainerRef.current || !currentTokenSlug) {
      return undefined;
    }

    return captureEvents(portraitContainerRef.current, {
      excludedClosestSelector: '.chart-card',
      onSwipe: (e, direction) => {
        if (direction === SwipeDirection.Right) {
          handleChartCardClose();
          return true;
        }

        return false;
      },
    });
  }, [currentTokenSlug, handleChartCardClose, isPortrait]);

  const appTheme = useAppTheme(theme);
  useAccentColor(isPortrait ? portraitContainerRef : landscapeContainerRef, appTheme, accentColorIndex);

  const handleEarnClick = useLastCallback((stakingId?: string) => {
    if (stakingId) changeCurrentStaking({ stakingId });

    if (isPortrait || isViewMode) {
      openStakingInfoOrStart();
    } else {
      setLandscapeActionsActiveTabIndex({ index: ActiveTab.Stake });
    }
  });

  function renderPortraitLayout() {
    return (
      <div ref={portraitContainerRef} className={styles.portraitContainer}>
        <div className={styles.head}>
          <Warnings onOpenBackupWallet={openBackupWalletModal} />

          <Header
            withBalance={!shouldHideBalanceInHeader}
            areTabsStuck={areTabsStuck}
            isScrolled={!isPageAtTop}
            isChartCardOpen={Boolean(currentTokenSlug)}
            tokenChartMode={tokenChartMode}
            isNetWorthChartAvailable={isNetWorthChartSupported}
            onChartCardBack={handleChartCardClose}
            onTokenChartModeChange={handleTokenChartModeChange}
          />

          <Card
            ref={cardRef}
            onChartCardClose={handleChartCardClose}
            tokenChartMode={tokenChartMode}
            onYieldClick={handleEarnClick}
          />

          {!isViewMode && (
            <PortraitActions
              containerRef={portraitContainerRef}
              isTestnet={isTestnet}
              stakingStatus={stakingStatus}
              isStakingDisabled={isStakingDisabled}
              isSwapDisabled={isSwapDisabled}
              isOnRampDisabled={isOnRampDisabled}
              isOffRampDisabled={!isOffRampAllowed}
              onEarnClick={handleEarnClick}
            />
          )}
        </div>

        <Content
          isActive={isActive}
          onStakedTokenClick={handleEarnClick}
          onTabsStuck={setAreTabsStuck}
        />
      </div>
    );
  }

  function renderLandscapeLayout() {
    return (
      <div ref={landscapeContainerRef} className={styles.landscapeContainer}>
        <div className={buildClassName(styles.sidebar, 'custom-scroll')}>
          <Warnings onOpenBackupWallet={openBackupWalletModal} />

          <Header
            isChartCardOpen={Boolean(currentTokenSlug)}
            tokenChartMode={tokenChartMode}
            isNetWorthChartAvailable={isNetWorthChartSupported}
            onChartCardBack={handleChartCardClose}
            onTokenChartModeChange={handleTokenChartModeChange}
          />

          <Card
            onChartCardClose={handleChartCardClose}
            tokenChartMode={tokenChartMode}
            onYieldClick={handleEarnClick}
          />
          {!isViewMode && (
            <LandscapeActions
              containerRef={landscapeContainerRef}
              stakingStatus={stakingStatus}
              isLedger={isLedger}
              isOffRampDisabled={!isOffRampAllowed}
              theme={theme}
            />
          )}

          {IS_EXPLORER && (
            <PromoteWallet />
          )}
        </div>
        <div className={styles.main}>
          <Content onStakedTokenClick={handleEarnClick} />
        </div>
      </div>
    );
  }

  function renderContent() {
    if (IS_EXPLORER) {
      return (
        <Transition name="semiFade" activeKey={isAppReady ? 1 : 0}>
          {isAppReady
            ? (isPortrait ? renderPortraitLayout() : renderLandscapeLayout())
            : <MainSkeleton isViewMode={isViewMode} />}
        </Transition>
      );
    }

    return isPortrait ? renderPortraitLayout() : renderLandscapeLayout();
  }

  return (
    <>
      {renderContent()}

      <StakeModal />
      <StakingInfoModal isOpen={isStakingInfoModalOpen} onClose={closeStakingInfo} />
      <ReceiveModal />
      <InvoiceModal />
      <UnstakeModal />
      <StakingClaimModal />
      <VestingModal />
      <VestingPasswordModal />
      <RenewDomainModal />
      <LinkingDomainModal />
      <PromotionModal />
      {!IS_ELECTRON && <UpdateAvailable />}
      {!IS_CORE_WALLET && <AccountSelectorModal />}
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const isLedger = selectIsHardwareAccount(global);
      const currentAccountId = selectCurrentAccountId(global);
      const accountState = selectCurrentAccountState(global);
      const { currentTokenSlug, isAppReady } = accountState ?? {};
      const currentToken = currentTokenSlug ? selectToken(global, currentTokenSlug) : undefined;

      const { isOnRampDisabled } = global.restrictions;

      const stakingState = currentAccountId
        ? selectAccountStakingState(global, currentAccountId)
        : undefined;

      return {
        stakingState,
        currentTokenSlug,
        currentToken,
        isTestnet: global.settings.isTestnet,
        isLedger,
        isViewMode: selectIsCurrentAccountViewMode(global),
        isStakingInfoModalOpen: global.isStakingInfoModalOpen,
        isMediaViewerOpen: Boolean(global.mediaViewer?.mediaId),
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
        isOnRampDisabled,
        isOffRampAllowed: selectIsOffRampAllowed(global),
        isAppReady,
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Main),
);
