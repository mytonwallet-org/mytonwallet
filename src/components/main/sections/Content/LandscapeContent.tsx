import React, { memo, useRef } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection, ApiStakingState } from '../../../../api/types';
import type { UserToken } from '../../../../global/types';
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
  selectUserTokenMemoized,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { calcVestingAmountByStatus } from '../../helpers/calcVestingAmountByStatus';

import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import useContentSwipe from './hooks/useContentSwipe';
import useContentTabs from './hooks/useContentTabs';

import BackHeader from '../../../common/BackHeader';
import TokenHeader from '../../../tokenInfo/Header';
import TokenSummary from '../../../tokenInfo/Summary';
import Transition from '../../../ui/Transition';
import HideNftModal from '../../modals/HideNftModal';
import TopActions from '../Actions/TopActions';
import ContentSlide from './ContentSlide';
import LandscapeWalletOverview from './LandscapeWalletOverview';
import NftCollectionHeader from './NftCollectionHeader';
import NftSelectionHeader from './NftSelectionHeader';

import styles from './Content.module.scss';

const LANDSCAPE_OVERVIEW_KEY = 0;

const SCROLL_CONTAINER_CLASS = 'landscape-content-scroll';
const SCROLL_CONTAINER_SELECTOR = `.${SCROLL_CONTAINER_CLASS}`;

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
  currentTokenSlug?: string;
  currentToken?: UserToken;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  areUnverifiedNftsHidden?: boolean;
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
  areUnverifiedNftsHidden,
  selectedNftsToHide,
  states,
  hasVesting,
  alwaysHiddenSlugs,
  activeContentTab,
  activityReturnContentTab,
  currentSiteCategoryId,
  collectionTabs,
  currentTokenSlug,
  currentToken,
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
    areUnverifiedNftsHidden,
    collectionTabs,
    activeContentTab,
    activityReturnContentTab,
    currentCollection,
    currentTokenSlug,
    states,
    hasVesting,
    alwaysHiddenSlugs,
    tokensCount,
    isPortrait: false,
    isLandscape: true,
  });

  const { handleScroll: handleContentScroll, isScrolled, update: updateScrolledState } = useScrolledState();

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
    || activeContentTab === ContentTab.Explore
    || activeContentTab === ContentTab.Portfolio;

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
      // Every slide keeps its own scroll position, so the shown one is addressed by its key
      const scrollContainer = transitionRef.current?.querySelector<HTMLElement>(
        `[data-slide-key="${landscapeActiveKey}"]`,
      );
      if (scrollContainer) {
        updateScrolledState(scrollContainer);
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
    const isNftSelectionVisible = hasNftSelection
      && (activeContentTab === ContentTab.Nft || Boolean(currentCollection));
    if (isNftSelectionVisible) return <NftSelectionHeader />;
    if (currentCollection) {
      return <NftCollectionHeader collection={currentCollection} key={currentCollection.address} />;
    }

    if (currentToken) {
      return <TokenHeader token={currentToken} isScrolled={isScrolled} onBackClick={handleHeaderBackClick} />;
    }

    return (
      <BackHeader
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

    const isActivitySlide = tabs[currentKey - 1]?.id === ContentTab.Activity;

    const slide = (
      <ContentSlide
        isActive={isSlideActive}
        isPortrait={false}
        activeTabIndex={activeTabIndex}
        activeTabId={activeTabId}
        currentCollection={currentCollection}
        shouldShowSeparateAssetsPanel={false}
        totalTokensAmount={totalTokensAmount}
        activeNftKey={activeNftKey}
        scrollContainerSelector={SCROLL_CONTAINER_SELECTOR}
        onClickAsset={handleClickAsset}
        onStakedTokenClick={onStakedTokenClick}
        onScroll={handleContentScroll}
      />
    );

    return (
      <div className={styles.landscapeContentPanel}>
        <div
          className={buildClassName(styles.landscapeSlide, 'custom-scroll', SCROLL_CONTAINER_CLASS)}
          data-slide-key={currentKey}
          onScroll={handleContentScroll}
        >
          {isActivitySlide && !currentToken && <TopActions className={styles.topActions} />}
          <div className={buildClassName(styles.landscapeHeader, isScrolled && styles.landscapeHeaderScrolled)}>
            {renderHeader()}
          </div>
          <div className={buildClassName(styles.slides, currentToken && styles.slidesOnTokenScreen)}>
            {currentToken ? (
              <>
                <TokenSummary token={currentToken} />
                <div className={styles.tokenActivity}>{slide}</div>
              </>
            ) : slide}
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
        currentTokenSlug,
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
        currentTokenSlug,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        areUnverifiedNftsHidden: global.settings.areUnverifiedNftsHidden,
        selectedNftsToHide,
        states,
        hasVesting,
        alwaysHiddenSlugs,
        currentSiteCategoryId,
        collectionTabs,
        currentToken: currentTokenSlug ? selectUserTokenMemoized(global, currentTokenSlug) : undefined,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(LandscapeContent),
);
