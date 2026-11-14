import React, { memo, useEffect, useLayoutEffect, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiStakingState } from '../../api/types';
import type { Theme } from '../../global/types';

import { IS_EXPLORER } from '../../config';
import { requestForcedReflow } from '../../lib/fasterdom/fasterdom';
import {
  selectAccountStakingState,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectDefaultOffRampChain,
  selectDefaultOnRampChain,
  selectIsCardAccountPending,
  selectIsCurrentAccountViewMode,
  selectIsOffRampAllowed,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
} from '../../global/selectors';
import { useAccentColor } from '../../util/accentColor';
import { getIsAccountContentTransitionActive } from '../../util/accountContentTransition';
import buildClassName from '../../util/buildClassName';
import { animateContentShift } from '../../util/layoutChangeAnimation';
import { getStakingStateStatus } from '../../util/staking';
import { REM } from '../../util/windowEnvironment';
import { calcSafeAreaTop } from './helpers/calcSafeAreaTop';
import { getIsMainActive } from './helpers/getIsMainActive';
import { getScrollableContainer, getScrollContainerClosestSelector } from './helpers/scrollableContainer';

import useAccountContentFade from '../../hooks/useAccountContentFade';
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
import useTimeout from '../../hooks/useTimeout';

import LinkingDomainModal from '../domain/LinkingDomainModal';
import RenewDomainModal from '../domain/RenewDomainModal';
import InvoiceModal from '../receive/InvoiceModal';
import ReceiveModal from '../receive/ReceiveModal';
import StakeModal from '../staking/StakeModal';
import StakingClaimModal from '../staking/StakingClaimModal';
import StakingInfoModal from '../staking/StakingInfoModal';
import UnstakeModal from '../staking/UnstakeModal';
import Transition from '../ui/Transition';
import VestingModal from '../vesting/VestingModal';
import VestingPasswordModal from '../vesting/VestingPasswordModal';
import MainSkeleton from './MainSkeleton';
import AccountSelectorModal from './modals/accountSelector/AccountSelectorModal';
import PromotionModal from './modals/PromotionModal';
import {
  LandscapeNavBar,
  LandscapeWalletList,
  PortraitActions,
} from './sections/Actions';
import PromoteWallet from './sections/Actions/PromoteWallet';
import Card from './sections/Card';
import PortraitContent from './sections/Content/PortraitContent';
import Header, { HEADER_HEIGHT_REM } from './sections/Header/Header';
import HomeBanners from './sections/HomeBanners';
import LandscapeLayout from './sections/LandscapeLayout';
import Warnings from './sections/Warnings';
import TestnetWarning from './sections/Warnings/TestnetWarning';

import styles from './Main.module.scss';

interface OwnProps {
  accountId?: string;
  isActive?: boolean;
}

type StateProps = {
  stakingState?: ApiStakingState;
  isTestnet?: boolean;
  isViewMode: boolean;
  isAccountPending: boolean;
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
// Keeps the market request away from the wallet start, yet the showcase is ready by the time the tab is opened
const MARKET_PRELOAD_DELAY = 5000; // 5 sec
// Picks up the token details that expired since the last preload
const TOKEN_DETAILS_PRELOAD_INTERVAL = 60000; // 1 min

function Main({
  isActive,
  accountId,
  stakingState,
  isTestnet,
  isViewMode,
  isAccountPending,
  isStakingInfoModalOpen,
  isSwapDisabled,
  isStakingDisabled,
  isOnRampDisabled,
  isOffRampAllowed,
  isMediaViewerOpen,
  isAppReady,
  theme,
  accentColorIndex,
}: OwnProps & StateProps) {
  const {
    openBackupWalletModal,
    closeStakingInfo,
    openStakingInfoOrStart,
    changeCurrentStaking,
    loadExploreSites,
    loadMarketAssets,
    updatePendingSwaps,
    preloadTokenDetails,
  } = getActions();

  const lang = useLang();
  const cardRef = useRef<HTMLDivElement>();
  const portraitContainerRef = useRef<HTMLDivElement>();
  const landscapeContainerRef = useRef<HTMLDivElement>();
  const navBarAndWalletListRef = useRef<HTMLDivElement>();
  const sidebarRef = useRef<HTMLDivElement>();

  const safeAreaTop = calcSafeAreaTop();
  const [isFocused, markIsFocused, unmarkIsFocused] = useFlag(!isBackgroundModeActive());
  const [areTabsStuck, setAreTabsStuck] = useState(false);
  const intersectionRootMarginTop = HEADER_HEIGHT_REM * REM + safeAreaTop;

  const stakingStatus = stakingState ? getStakingStateStatus(stakingState) : 'inactive';

  useBackgroundMode(unmarkIsFocused, markIsFocused);

  // This component stays mounted across accounts, and every account opens from the top.
  // The reset happens in the frame that paints the new account, before the account regions measure it.
  useLayoutEffect(() => {
    requestForcedReflow(() => {
      const scrollContainer = getScrollableContainer(portraitContainerRef.current, true) ?? sidebarRef.current;

      if (scrollContainer?.scrollTop) scrollContainer.scrollTo({ top: 0, behavior: 'instant' });
    });
  }, [accountId]);

  // After the scroll reset above, so that each region measures where it ends up for the new account
  const accountContentRef = useAccountContentFade(accountId);
  const accountHeaderRef = useAccountContentFade(accountId);
  const accountListRef = useAccountContentFade(accountId);
  const accountNavRef = useAccountContentFade(accountId);
  const accountActionsRef = useAccountContentFade(accountId);
  const accountNoticesRef = useAccountContentFade(accountId);
  const portraitContentRef = useAccountContentFade(accountId);
  const homeBannersRef = useAccountContentFade(accountId);

  usePreventPinchZoomGesture(isMediaViewerOpen);

  const { isPortrait, isLandscape } = useDeviceScreen();

  useEffectOnce(() => {
    loadExploreSites({ isLandscape, langCode: lang.code });
  });

  useTimeout(loadMarketAssets, MARKET_PRELOAD_DELAY);

  useInterval(updatePendingSwaps, isFocused ? UPDATE_SWAPS_INTERVAL : UPDATE_SWAPS_INTERVAL_NOT_FOCUSED);

  useEffect(() => {
    if (isFocused) preloadTokenDetails();
  }, [isFocused, accountId, lang.code]);

  useInterval(preloadTokenDetails, isFocused ? TOKEN_DETAILS_PRELOAD_INTERVAL : undefined, true);

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

  const appTheme = useAppTheme(theme);
  useAccentColor(isPortrait ? portraitContainerRef : landscapeContainerRef, appTheme, accentColorIndex);

  const handleEarnClick = useLastCallback((stakingId?: string) => {
    if (stakingId) changeCurrentStaking({ stakingId });

    openStakingInfoOrStart();
  });

  const handleBannersHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    // An account switch replaces the content under a crossfade, so there is nothing to shift
    if (getIsAccountContentTransitionActive()) return;

    animateContentShift(
      isPortrait ? portraitContentRef.current! : navBarAndWalletListRef.current!,
      getScrollContainerClosestSelector(true, isPortrait)!,
      prevHeight - nextHeight,
    );
  });

  const handleNoticesHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    if (getIsAccountContentTransitionActive()) return;

    animateContentShift(
      homeBannersRef.current!,
      getScrollContainerClosestSelector(true, isPortrait)!,
      prevHeight - nextHeight,
    );
    handleBannersHeightChange(prevHeight, nextHeight);
  });

  function renderNoticesAndBanners() {
    return (
      <>
        <div ref={accountNoticesRef} className={styles.accountRegion} inert={isAccountPending}>
          <Warnings
            key={accountId}
            onOpenBackupWallet={openBackupWalletModal}
            onHeightChange={handleNoticesHeightChange}
          />
        </div>

        <div ref={homeBannersRef} className={styles.accountRegion} inert={isAccountPending}>
          <HomeBanners onHeightChange={handleBannersHeightChange} />
        </div>
      </>
    );
  }

  function renderPortraitLayout() {
    return (
      <div
        ref={portraitContainerRef}
        className={buildClassName(styles.portraitContainer, isAccountPending && styles.isAccountPending)}
        data-portrait-wallet
      >
        <div className={styles.head}>
          <TestnetWarning />

          <div ref={accountHeaderRef} className={styles.accountRegion} inert={isAccountPending}>
            <Header
              key={accountId}
              withBalance={!shouldHideBalanceInHeader}
              areTabsStuck={areTabsStuck}
              isScrolled={!isPageAtTop}
            />
          </div>

          <Card ref={cardRef} onYieldClick={handleEarnClick} />

          {/* Mounted for view wallets too, or its outgoing view would vanish with the actions */}
          <div ref={accountActionsRef} className={styles.accountRegion} inert={isAccountPending}>
            {!isViewMode && (
              <PortraitActions
                key={accountId}
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

          {renderNoticesAndBanners()}
        </div>

        <div ref={portraitContentRef} className={styles.portraitContentRegion} inert={isAccountPending}>
          <PortraitContent
            key={accountId}
            isActive={isActive}
            onStakedTokenClick={handleEarnClick}
            onTabsStuck={setAreTabsStuck}
          />
        </div>
      </div>
    );
  }

  function renderLandscapeLayout() {
    return (
      <div
        ref={landscapeContainerRef}
        className={buildClassName(styles.landscapeContainer, isAccountPending && styles.isAccountPending)}
        dir={lang.isRtl ? 'rtl' : 'ltr'}
      >
        <div ref={sidebarRef} className={buildClassName(styles.sidebar, 'custom-scroll')}>
          <TestnetWarning />

          <div ref={accountHeaderRef} className={styles.accountRegion} inert={isAccountPending}>
            <Header key={accountId} />
          </div>

          <Card onYieldClick={handleEarnClick} />

          {renderNoticesAndBanners()}

          <div ref={navBarAndWalletListRef} inert={isAccountPending}>
            <div ref={accountNavRef} className={styles.accountRegion}>
              <LandscapeNavBar />
            </div>
            <div ref={accountListRef} className={styles.accountRegion}>
              <LandscapeWalletList />
            </div>
          </div>
          {IS_EXPLORER && <PromoteWallet />}
        </div>
        <div ref={accountContentRef} className={styles.main} inert={isAccountPending}>
          <LandscapeLayout onStakedTokenClick={handleEarnClick} />
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

      <StakeModal key={accountId} />
      <StakingInfoModal key={accountId} isOpen={isStakingInfoModalOpen} onClose={closeStakingInfo} />
      <ReceiveModal key={accountId} />
      <InvoiceModal key={accountId} />
      <UnstakeModal key={accountId} />
      <StakingClaimModal key={accountId} />
      <VestingModal key={accountId} />
      <VestingPasswordModal key={accountId} />
      <RenewDomainModal key={accountId} />
      <LinkingDomainModal key={accountId} />
      <PromotionModal key={accountId} />
      <AccountSelectorModal key={accountId} />
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const currentAccountId = selectCurrentAccountId(global);
      const accountState = selectCurrentAccountState(global);
      const { isAppReady } = accountState ?? {};

      const stakingState = currentAccountId
        ? selectAccountStakingState(global, currentAccountId)
        : undefined;

      return {
        stakingState,
        isTestnet: global.settings.isTestnet,
        isViewMode: selectIsCurrentAccountViewMode(global),
        isAccountPending: selectIsCardAccountPending(global),
        isStakingInfoModalOpen: global.isStakingInfoModalOpen,
        isMediaViewerOpen: Boolean(global.mediaViewer?.mediaId),
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
        // Both labels stand for the ramps reachable from this account, so they read the very chain each would open
        isOnRampDisabled: !selectDefaultOnRampChain(global),
        isOffRampAllowed: selectIsOffRampAllowed(global, selectDefaultOffRampChain(global)),
        isAppReady,
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    getIsMainActive,
  )(Main),
);
