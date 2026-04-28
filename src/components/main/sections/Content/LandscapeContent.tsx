import React, { memo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection, ApiStakingState } from '../../../../api/types';
import { type Account, ContentTab } from '../../../../global/types';

import { requestMeasure } from '../../../../lib/fasterdom/fasterdom';
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
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { calcVestingAmountByStatus } from '../../helpers/calcVestingAmountByStatus';
import { getScrollableContainer } from '../../helpers/scrollableContainer';

import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import useContentSwipe from './hooks/useContentSwipe';
import useContentTabs from './hooks/useContentTabs';

import Transition from '../../../ui/Transition';
import HideNftModal from '../../modals/HideNftModal';
import ContentSlide from './ContentSlide';
import LandscapeWalletOverview from './LandscapeWalletOverview';
import NftCollectionHeader from './NftCollectionHeader';
import NftSelectionHeader from './NftSelectionHeader';
import OverviewBackHeader from './OverviewBackHeader';

import styles from './Content.module.scss';

const LANDSCAPE_OVERVIEW_KEY = 0;

interface OwnProps {
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

function LandscapeContent({
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
}: OwnProps & StateProps) {
  const lang = useLang();
  const transitionRef = useRef<HTMLDivElement>();

  const hasNftSelection = Boolean(selectedNfts?.length);

  const {
    tabs,
    mainContentTabsCount,
    activeTabIndex,
    contentTransitionKey,
    visibleCollectionTabs,
    totalTokensAmount,
    activeNftKey,
    handleSwitchTab,
    handleHeaderBackClick,
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
    isPortrait: false,
    isLandscape: true,
  });

  const { handleScroll: handleContentScroll, update: updateScrolledState } = useScrolledState();

  useContentSwipe({
    transitionRef,
    tabs,
    activeTabIndex,
    currentCollection,
    currentSiteCategoryId,
    onSwitchTab: handleSwitchTab,
  });

  useHistoryBack({
    isActive: activeContentTab !== undefined && activeContentTab !== ContentTab.Overview,
    onBack: () => {
      const returnTab = activeContentTab === ContentTab.Activity && activityReturnContentTab !== undefined
        ? activityReturnContentTab
        : ContentTab.Overview;
      handleSwitchTab(returnTab);
    },
  });

  // Settings/Agent/Explore render on top of the landscape main area as full-screen overlay slides
  // in `LandscapeLayout`'s outer `Transition`. While such an overlay is active we keep the inner
  // `Transition`'s key frozen (see `landscapeActiveKey` below) so the slide underneath does not
  // change during the open/close animation; once the overlay is gone the inner key updates normally.
  const isCoveredByLandscapeOverlay = activeContentTab === ContentTab.Settings
    || activeContentTab === ContentTab.Agent
    || activeContentTab === ContentTab.Explore;

  const shouldShowLandscapeOverview = !currentCollection
    && !hasNftSelection
    && (
      activeContentTab === ContentTab.Overview
      || activeContentTab === undefined // newly created wallets
    );

  const naturalLandscapeKey = shouldShowLandscapeOverview ? LANDSCAPE_OVERVIEW_KEY : contentTransitionKey + 1;
  const frozenLandscapeKeyRef = useRef(LANDSCAPE_OVERVIEW_KEY);
  if (!isCoveredByLandscapeOverlay) {
    frozenLandscapeKeyRef.current = naturalLandscapeKey;
  }
  const landscapeActiveKey = isCoveredByLandscapeOverlay
    ? frozenLandscapeKeyRef.current
    : naturalLandscapeKey;

  const landscapeRenderCount = mainContentTabsCount + visibleCollectionTabs.length + 1;

  // Agent manages its own scroll container, so we skip it here
  const handleContentTransitionStop = useLastCallback(() => {
    if (activeContentTab === ContentTab.Agent) return;

    requestMeasure(() => {
      const scrollContainer = getScrollableContainer(transitionRef.current, false);
      if (scrollContainer) {
        updateScrolledState(scrollContainer as HTMLElement);
      }
    });
  });

  const containerClassName = buildClassName(
    styles.container,
    IS_TOUCH_ENV && 'swipe-container',
    styles.landscapeContainer,
  );

  const activeTabId = tabs[activeTabIndex]?.id;

  function renderHeader() {
    if (hasNftSelection) return <NftSelectionHeader />;
    if (currentCollection) return <NftCollectionHeader key="collection" />;

    return (
      <OverviewBackHeader
        title={lang(getOverviewBackHeaderTitle(activeContentTab))}
        onBackClick={handleHeaderBackClick}
      />
    );
  }

  function renderSlide(isSlideActive: boolean, _isFrom: boolean, currentKey: number) {
    if (currentKey === LANDSCAPE_OVERVIEW_KEY) {
      return (
        <LandscapeWalletOverview
          totalTokensAmount={totalTokensAmount}
          onStakedTokenClick={onStakedTokenClick}
        />
      );
    }

    return (
      <div className={styles.landscapeContentPanel}>
        {renderHeader()}
        <div className={styles.slides}>
          <div className={buildClassName(styles.landscapeSlide, 'custom-scroll')}>
            <ContentSlide
              isActive={isSlideActive}
              isPortrait={false}
              activeTabIndex={activeTabIndex}
              activeTabId={activeTabId}
              currentCollection={currentCollection}
              shouldShowSeparateAssetsPanel={false}
              totalTokensAmount={totalTokensAmount}
              activeNftKey={activeNftKey}
              onClickAsset={handleClickAsset}
              onStakedTokenClick={onStakedTokenClick}
              onScroll={handleContentScroll}
            />
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className={containerClassName}>
        <Transition
          ref={transitionRef}
          name="slideFade"
          activeKey={landscapeActiveKey}
          renderCount={landscapeRenderCount}
          className={styles.landscapeRoot}
          onStop={handleContentTransitionStop}
          onScroll={handleContentScroll}
        >
          {renderSlide}
        </Transition>
      </div>
      <HideNftModal
        isOpen={Boolean(selectedNftsToHide?.addresses.length)}
        selectedNftsToHide={selectedNftsToHide}
      />
    </>
  );
}

function getOverviewBackHeaderTitle(tab?: ContentTab) {
  switch (tab) {
    case ContentTab.Activity:
      return 'Activity';
    case ContentTab.Nft:
      return 'Collectibles';
    default:
      return 'Assets';
  }
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
  )(LandscapeContent),
);
