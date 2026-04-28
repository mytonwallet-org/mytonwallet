import React, { memo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection, ApiStakingState } from '../../../../api/types';
import { type Account, ContentTab } from '../../../../global/types';

import { requestMutation } from '../../../../lib/fasterdom/fasterdom';
import {
  selectAccountStakingStates,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectEnabledTokensCountMemoizedFor,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { IS_TOUCH_ENV, REM, STICKY_CARD_INTERSECTION_THRESHOLD } from '../../../../util/windowEnvironment';
import windowSize from '../../../../util/windowSize';
import { calcSafeAreaTop } from '../../helpers/calcSafeAreaTop';
import { calcVestingAmountByStatus } from '../../helpers/calcVestingAmountByStatus';
import { getScrollableContainer } from '../../helpers/scrollableContainer';

import useElementVisibility from '../../../../hooks/useElementVisibility';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import useContentSwipe from './hooks/useContentSwipe';
import useContentTabs from './hooks/useContentTabs';

import TabList from '../../../ui/TabList';
import Transition from '../../../ui/Transition';
import HideNftModal from '../../modals/HideNftModal';
import Assets from './Assets';
import ContentSlide from './ContentSlide';
import NftCollectionHeader from './NftCollectionHeader';
import NftSelectionHeader from './NftSelectionHeader';

import styles from './Content.module.scss';

const INTERSECTION_APPROXIMATION_VALUE_PX = 3 * REM;

interface OwnProps {
  isActive?: boolean;
  onTabsStuck?: (isStuck: boolean) => void;
  onStakedTokenClick: NoneToVoidFunction;
}

interface StateProps {
  byChain?: Account['byChain'];
  tokensCount: number;
  nfts?: Record<string, ApiNft>;
  currentCollection?: ApiNftCollection;
  selectedNfts?: ApiNft[];
  activeContentTab?: ContentTab;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  states?: ApiStakingState[];
  hasVesting: boolean;
  alwaysHiddenSlugs?: string[];
  activityReturnContentTab?: ContentTab;
  selectedNftsToHide?: {
    addresses: string[];
    isCollection: boolean;
  };
  currentSiteCategoryId?: number;
  collectionTabs?: ApiNftCollection[];
}

function PortraitContent({
  isActive,
  byChain,
  tokensCount,
  nfts,
  currentCollection,
  selectedNfts,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  selectedNftsToHide,
  states,
  hasVesting,
  alwaysHiddenSlugs,
  activeContentTab,
  activityReturnContentTab,
  currentSiteCategoryId,
  collectionTabs,
  onStakedTokenClick,
  onTabsStuck,
}: OwnProps & StateProps) {
  const containerRef = useRef<HTMLDivElement>();
  const tabsRef = useRef<HTMLDivElement>();
  const transitionRef = useRef<HTMLDivElement>();

  const hasNftSelection = Boolean(selectedNfts?.length);

  const {
    tabs,
    mainContentTabsCount,
    activeTabIndex,
    contentTransitionKey,
    visibleCollectionTabs,
    totalTokensAmount,
    shouldShowSeparateAssetsPanel,
    activeNftKey,
    handleSwitchTab,
    handleClickAsset,
  } = useContentTabs({
    byChain,
    nfts,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    collectionTabs,
    activeContentTab,
    activityReturnContentTab,
    currentCollection,
    states,
    hasVesting,
    alwaysHiddenSlugs,
    tokensCount,
    isPortrait: true,
    isLandscape: false,
  });

  const { isScrolled } = useScrolledState();

  useContentSwipe({
    transitionRef,
    tabs,
    activeTabIndex,
    currentCollection,
    currentSiteCategoryId,
    onSwitchTab: handleSwitchTab,
  });

  useHistoryBack({
    isActive: activeTabIndex !== 0,
    onBack: () => {
      const returnTab = activeContentTab === ContentTab.Activity && activityReturnContentTab !== undefined
        ? activityReturnContentTab
        : ContentTab.Assets;
      handleSwitchTab(returnTab);
    },
  });

  const safeAreaTop = calcSafeAreaTop();
  const intersectionRootMarginTop = STICKY_CARD_INTERSECTION_THRESHOLD - safeAreaTop - 1;

  const handleTabIntersection = useLastCallback((e: IntersectionObserverEntry) => {
    const { intersectionRect: { bottom }, intersectionRatio } = e;
    const isStuck = intersectionRatio < 1
      // During fast scrolling with rubber effect, the values in `intersectionRect` are `0`
      && bottom > 0
      // Due to the overscroll effect in iOS, it is necessary to check the bottom position of the element.
      // If the `bottom` value and `height` of the screen are approximately equal, this is overscroll, not sticking.
      && Math.abs(bottom - windowSize.get().height) > INTERSECTION_APPROXIMATION_VALUE_PX;

    onTabsStuck?.(isStuck);
    requestMutation(() => {
      containerRef.current?.classList.toggle(styles.portraitContainerIsStuck, isStuck);
    });
  });

  useElementVisibility({
    targetRef: tabsRef,
    rootMargin: `${intersectionRootMarginTop}px 0px 0px 0px`,
    threshold: [1],
    cb: handleTabIntersection,
  });

  const handleScrollToTop = useLastCallback(() => {
    const scrollContainer = getScrollableContainer(transitionRef.current, true);
    scrollContainer?.scrollTo(0, 0);
  });

  const containerClassName = buildClassName(
    styles.container,
    IS_TOUCH_ENV && 'swipe-container',
    styles.portraitContainer,
  );

  const activeTabId = tabs[activeTabIndex]?.id;

  function renderHeader() {
    const headerTransitionKey = hasNftSelection ? 2 : (currentCollection ? 1 : 0);

    let header;
    if (hasNftSelection) {
      header = <NftSelectionHeader />;
    } else if (currentCollection) {
      header = <NftCollectionHeader key="collection" />;
    } else {
      header = (
        <TabList
          isActive={isActive}
          tabs={tabs}
          activeTab={activeTabIndex}
          onSwitchTab={handleSwitchTab}
          onActiveTabClick={handleScrollToTop}
          className={buildClassName(styles.tabs, 'content-tabslist')}
          overlayClassName={styles.tabsOverlay}
        />
      );
    }

    return (
      <div
        ref={tabsRef}
        className={buildClassName(
          styles.tabsContainer,
          currentCollection && styles.tabsContainerForNftCollection,
          'with-notch-on-scroll',
          isScrolled && 'is-scrolled',
        )}
      >
        <Transition
          name="slideFade"
          className={styles.tabsContent}
          activeKey={headerTransitionKey}
          slideClassName={styles.tabsSlide}
          shouldCleanup
          cleanupExceptionKey={0}
        >
          {header}
        </Transition>
      </div>
    );
  }

  function renderSlide(isSlideActive: boolean) {
    return (
      <ContentSlide
        isActive={isSlideActive}
        isPortrait
        activeTabIndex={activeTabIndex}
        activeTabId={activeTabId}
        currentCollection={currentCollection}
        shouldShowSeparateAssetsPanel={shouldShowSeparateAssetsPanel}
        totalTokensAmount={totalTokensAmount}
        activeNftKey={activeNftKey}
        onClickAsset={handleClickAsset}
        onStakedTokenClick={onStakedTokenClick}
      />
    );
  }

  return (
    <>
      <div ref={containerRef} className={containerClassName}>
        {shouldShowSeparateAssetsPanel && (
          <div className={styles.assetsPanel}>
            <Assets
              isActive
              isSeparatePanel
              onStakedTokenClick={onStakedTokenClick}
              onTokenClick={handleClickAsset}
            />
          </div>
        )}
        <div className={styles.contentPanel}>
          {renderHeader()}
          <Transition
            ref={transitionRef}
            name="slide"
            activeKey={contentTransitionKey}
            renderCount={mainContentTabsCount + visibleCollectionTabs.length}
            className={buildClassName(styles.slides, 'content-transition')}
            slideClassName={buildClassName(styles.slide, 'custom-scroll')}
          >
            {renderSlide}
          </Transition>
        </div>
      </div>
      <HideNftModal
        isOpen={Boolean(selectedNftsToHide?.addresses.length)}
        selectedNftsToHide={selectedNftsToHide}
      />
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountId = selectCurrentAccountId(global);
      const {
        activeContentTab,
        activityReturnContentTab,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        selectedNftsToHide,
        vesting,
        nfts: {
          byAddress: nfts,
          currentCollection,
          selectedNfts,
          collectionTabs,
        } = {},
        currentSiteCategoryId,
      } = selectCurrentAccountState(global) ?? {};

      const tokens = selectCurrentAccountTokens(global);
      const tokensCount = accountId ? selectEnabledTokensCountMemoizedFor(accountId)(tokens) : 0;
      const vestingInfo = vesting?.info;
      const hasVesting = Boolean(
        vestingInfo?.length && calcVestingAmountByStatus(vestingInfo, ['frozen', 'ready']) !== '0',
      );
      const states = accountId ? selectAccountStakingStates(global, accountId) : undefined;
      const alwaysHiddenSlugs = selectCurrentAccountSettings(global)?.alwaysHiddenSlugs;

      return {
        byChain: selectCurrentAccount(global)?.byChain,
        nfts,
        currentCollection,
        selectedNfts,
        tokensCount,
        activeContentTab,
        activityReturnContentTab,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        selectedNftsToHide,
        states,
        hasVesting,
        alwaysHiddenSlugs,
        currentSiteCategoryId,
        collectionTabs,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(PortraitContent),
);
