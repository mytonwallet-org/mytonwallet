import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiStakingState } from '../../api/types';
import { ActiveTab, ContentTab, type Theme } from '../../global/types';

import { IS_CORE_WALLET } from '../../config';
import {
  selectAccountStakingState,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectIsHardwareAccount,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
} from '../../global/selectors';
import { useAccentColor } from '../../util/accentColor';
import buildClassName from '../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../util/captureEvents';
import { getStakingStateStatus } from '../../util/staking';
import {
  IS_DELEGATED_BOTTOM_SHEET, IS_ELECTRON, IS_TOUCH_ENV, REM,
} from '../../util/windowEnvironment';
import { calcSafeAreaTop } from './helpers/calcSafeAreaTop';

import useAppTheme from '../../hooks/useAppTheme';
import useBackgroundMode, { isBackgroundModeActive } from '../../hooks/useBackgroundMode';
import { useOpenFromMainBottomSheet } from '../../hooks/useDelegatedBottomSheet';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectOnce from '../../hooks/useEffectOnce';
import useElementVisibility from '../../hooks/useElementVisibility';
import useFlag from '../../hooks/useFlag';
import useInterval from '../../hooks/useInterval';
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
import UpdateAvailable from '../ui/UpdateAvailable';
import VestingModal from '../vesting/VestingModal';
import VestingPasswordModal from '../vesting/VestingPasswordModal';
import { LandscapeActions, PortraitActions } from './sections/Actions';
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
  stakingState?: ApiStakingState;
  isTestnet?: boolean;
  isLedger?: boolean;
  isViewMode?: boolean;
  isStakingInfoModalOpen?: boolean;
  isSwapDisabled?: boolean;
  isStakingDisabled?: boolean;
  isOnRampDisabled?: boolean;
  isMediaViewerOpen?: boolean;
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
  isMediaViewerOpen,
  theme,
  accentColorIndex,
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
    openReceiveModal,
    updatePendingSwaps,
  } = getActions();

  const cardRef = useRef<HTMLDivElement>();
  const portraitContainerRef = useRef<HTMLDivElement>();
  const landscapeContainerRef = useRef<HTMLDivElement>();

  const safeAreaTop = calcSafeAreaTop();
  const [isFocused, markIsFocused, unmarkIsFocused] = useFlag(!isBackgroundModeActive());
  const [areTabsStuck, setAreTabsStuck] = useState(false);
  const intersectionRootMarginTop = HEADER_HEIGHT_REM * REM + safeAreaTop;

  const stakingStatus = stakingState ? getStakingStateStatus(stakingState) : 'inactive';

  useBackgroundMode(unmarkIsFocused, markIsFocused);

  useOpenFromMainBottomSheet('receive', openReceiveModal);
  usePreventPinchZoomGesture(isMediaViewerOpen);

  const { isPortrait, isLandscape } = useDeviceScreen();

  useEffectOnce(() => {
    if (IS_CORE_WALLET) return;

    loadExploreSites({ isLandscape });
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

  const handleTokenCardClose = useLastCallback(() => {
    selectToken({ slug: undefined });
    setActiveContentTab({ tab: ContentTab.Assets });
  });

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isPortrait || !portraitContainerRef.current || !currentTokenSlug) {
      return undefined;
    }

    return captureEvents(portraitContainerRef.current, {
      excludedClosestSelector: '.token-card',
      onSwipe: (e, direction) => {
        if (direction === SwipeDirection.Right) {
          handleTokenCardClose();
          return true;
        }

        return false;
      },
    });
  }, [currentTokenSlug, handleTokenCardClose, isPortrait]);

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
          />

          <Card
            ref={cardRef}
            onTokenCardClose={handleTokenCardClose}
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

          <Header />

          <Card onTokenCardClose={handleTokenCardClose} onYieldClick={handleEarnClick} />
          {!isViewMode && (
            <LandscapeActions
              containerRef={landscapeContainerRef}
              stakingStatus={stakingStatus}
              isLedger={isLedger}
              theme={theme}
            />
          )}
        </div>
        <div className={styles.main}>
          <Content onStakedTokenClick={handleEarnClick} />
        </div>
      </div>
    );
  }

  return (
    <>
      {!IS_DELEGATED_BOTTOM_SHEET && (isPortrait ? renderPortraitLayout() : renderLandscapeLayout())}

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
      {!IS_ELECTRON && !IS_DELEGATED_BOTTOM_SHEET && <UpdateAvailable />}
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const isLedger = selectIsHardwareAccount(global);
      const accountState = selectCurrentAccountState(global);
      const { currentTokenSlug } = accountState ?? {};

      const { isOnRampDisabled } = global.restrictions;

      const stakingState = global.currentAccountId
        ? selectAccountStakingState(global, global.currentAccountId)
        : undefined;

      return {
        stakingState,
        currentTokenSlug,
        isTestnet: global.settings.isTestnet,
        isLedger,
        isViewMode: selectIsCurrentAccountViewMode(global),
        isStakingInfoModalOpen: global.isStakingInfoModalOpen,
        isMediaViewerOpen: Boolean(global.mediaViewer?.mediaId),
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
        isOnRampDisabled,
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    (global, _, stickToFirst) => stickToFirst(global.currentAccountId),
  )(Main),
);
