import React, { memo, useEffect, useLayoutEffect, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection, ApiStakingState } from '../../../../api/types';
import { type Account, ContentTab } from '../../../../global/types';

import { requestForcedReflow } from '../../../../lib/fasterdom/fasterdom';
import {
  selectAccountStakingStates,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectEnabledTokensCountMemoizedFor,
  selectIsContentListOpen,
  selectShownContentTab,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { captureControlledSwipe } from '../../../../util/swipeController';
import { calcVestingAmountByStatus } from '../../../../util/vesting';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { openStaking } from '../../helpers/openStaking';
import { getScrollableContainer } from '../../helpers/scrollableContainer';

import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import usePrevious from '../../../../hooks/usePrevious';
import useScrolledState from '../../../../hooks/useScrolledState';
import useContentTabs from './hooks/useContentTabs';

import BackHeader from '../../../common/BackHeader';
import Transition from '../../../ui/Transition';
import HideNftModal from '../../modals/HideNftModal';
import ContentSlide from './ContentSlide';
import NftCollectionHeader from './NftCollectionHeader';
import NftSelectionHeader from './NftSelectionHeader';
import PortraitWalletOverview from './PortraitWalletOverview';
import { OPEN_CONTEXT_MENU_CLASS_NAME } from './Token';

import styles from './Content.module.scss';

interface OwnProps {
  /** Renders the full list screen instead of the wallet overview */
  isListScreen?: boolean;
}

interface StateProps {
  byChain?: Account['byChain'];
  tokensCount: number;
  nfts?: Record<string, ApiNft>;
  currentCollection?: ApiNftCollection;
  selectedNfts?: ApiNft[];
  shownContentTab?: ContentTab;
  currentTokenSlug?: string;
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
  collectionTabs?: ApiNftCollection[];
  isContentListOpen: boolean;
}

function PortraitContent({
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
  shownContentTab,
  activityReturnContentTab,
  collectionTabs,
  currentTokenSlug,
  isContentListOpen,
  isListScreen,
}: OwnProps & StateProps) {
  const { closeNftCollection } = getActions();

  const containerRef = useRef<HTMLDivElement>();
  const transitionRef = useRef<HTMLDivElement>();

  const hasNftSelection = Boolean(selectedNfts?.length);
  const wasContentListOpen = usePrevious(isContentListOpen);

  // The closing list screen fades out with the title and the list it showed
  const lastList = useCurrentOrPrev(
    isContentListOpen ? { tab: shownContentTab, collection: currentCollection } : undefined,
    true,
  );
  const shownCollection = isListScreen ? lastList?.collection : currentCollection;

  const {
    tabs,
    mainContentTabsCount,
    activeTabIndex,
    contentTransitionKey,
    collections,
    visibleCollectionTabs,
    totalTokensAmount,
    backHeaderTitle,
    activeNftKey,
    handleHeaderBackClick,
    handleClickAsset,
  } = useContentTabs({
    byChain,
    nfts,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    areUnverifiedNftsHidden,
    collectionTabs,
    activeContentTab: isListScreen ? lastList?.tab : shownContentTab,
    activityReturnContentTab,
    currentCollection: shownCollection,
    currentTokenSlug,
    states,
    hasVesting,
    alwaysHiddenSlugs,
    tokensCount,
  });

  const { isScrolled, update: updateScrolledState } = useScrolledState();

  // The list scrolls together with the whole app slide, which is outside of this component
  useEffect(() => {
    if (!isListScreen) return undefined;

    const scrollContainer = getScrollableContainer(containerRef.current, true) as HTMLElement;

    function handleScroll() {
      updateScrolledState(scrollContainer);
    }

    scrollContainer.addEventListener('scroll', handleScroll, { passive: true });

    return () => scrollContainer.removeEventListener('scroll', handleScroll);
  }, [isListScreen, containerRef, updateScrolledState]);

  const isCollectionOpen = Boolean(currentCollection);

  useEffect(() => {
    if (!IS_TOUCH_ENV || !isListScreen || !isContentListOpen || hasNftSelection) return undefined;

    return captureControlledSwipe(transitionRef.current!, {
      onSwipeRightStart: () => {
        // A long press on a row opens its menu, and moving the finger after it must not count as a swipe
        if (transitionRef.current!.querySelector(`.${OPEN_CONTEXT_MENU_CLASS_NAME}`)) return;

        if (isCollectionOpen) {
          closeNftCollection();
        } else {
          handleHeaderBackClick();
        }
      },
      // No `Transition` here follows the finger (`withSwipeControl`), so there is no swipe animation to undo
      onCancel: () => undefined,
      excludedSelector: '.no-swipe',
    });
  }, [closeNftCollection, handleHeaderBackClick, hasNftSelection, isCollectionOpen, isContentListOpen, isListScreen]);

  useHistoryBack({
    // An open collection is closed by the history record of `NftCollectionHeader`
    isActive: Boolean(isListScreen) && isContentListOpen && !currentCollection,
    onBack: handleHeaderBackClick,
  });

  const shownListTab = lastList?.tab;
  const shownCollectionAddress = shownCollection?.address;

  // The app slide scrolls the list and outlives it, and every list opens from its top
  useLayoutEffect(() => {
    if (!isListScreen || !isContentListOpen) return;

    requestForcedReflow(() => () => {
      getScrollableContainer(containerRef.current, true)?.scrollTo({ top: 0, behavior: 'instant' });
    });
  }, [isListScreen, isContentListOpen, shownListTab, shownCollectionAddress, containerRef]);

  const containerClassName = buildClassName(
    styles.container,
    IS_TOUCH_ENV && 'swipe-container',
    styles.portraitContainer,
    isListScreen && styles.listContainer,
  );

  const activeTabId = tabs[activeTabIndex]?.id;
  const nftTab = tabs.find(({ id }) => id === ContentTab.Nft);

  function renderHeader() {
    const isNftSelectionVisible = hasNftSelection
      && (shownContentTab === ContentTab.Nft || Boolean(shownCollection));
    const headerTransitionKey = isNftSelectionVisible ? 2 : (shownCollection ? 1 : 0);

    let header;
    if (isNftSelectionVisible) {
      header = <NftSelectionHeader />;
    } else if (shownCollection) {
      header = (
        <NftCollectionHeader
          collection={shownCollection}
          isHidden={!isContentListOpen}
          key={shownCollection.address}
        />
      );
    } else {
      header = <BackHeader title={backHeaderTitle} onBackClick={handleHeaderBackClick} />;
    }

    return (
      <div
        className={buildClassName(
          styles.tabsContainer,
          shownCollection && styles.tabsContainerForNftCollection,
          'with-notch-on-scroll',
          isScrolled && 'is-scrolled',
        )}
      >
        <Transition
          name={wasContentListOpen ? 'slideFade' : 'none'}
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
        isActive={isSlideActive && isContentListOpen}
        isPortrait
        activeTabId={activeTabId}
        currentCollection={shownCollection}
        activeNftKey={activeNftKey}
        onClickAsset={handleClickAsset}
        onStakedTokenClick={openStaking}
      />
    );
  }

  if (isListScreen) {
    return (
      <div ref={containerRef} className={containerClassName}>
        <div className={styles.contentPanel}>
          {renderHeader()}
          <Transition
            ref={transitionRef}
            // The list behind the opening screen changes at the same moment, and only the screen transition should play
            name={wasContentListOpen ? 'slide' : 'none'}
            activeKey={contentTransitionKey}
            renderCount={mainContentTabsCount + visibleCollectionTabs.length}
            className={buildClassName(styles.slides, 'content-transition')}
            slideClassName={buildClassName(styles.slide, 'custom-scroll')}
          >
            {renderSlide}
          </Transition>
        </div>
      </div>
    );
  }

  return (
    <>
      <div ref={containerRef} className={containerClassName}>
        <PortraitWalletOverview
          totalTokensAmount={totalTokensAmount}
          collections={collections}
          visibleCollectionTabs={visibleCollectionTabs}
          collectiblesMenuItems={nftTab?.menuItems}
          onCollectiblesMenuItemClick={nftTab?.onMenuItemClick}
          onStakedTokenClick={openStaking}
        />
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
        shownContentTab: selectShownContentTab(global),
        activityReturnContentTab,
        currentTokenSlug,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        areUnverifiedNftsHidden: global.settings.areUnverifiedNftsHidden,
        selectedNftsToHide,
        states,
        hasVesting,
        alwaysHiddenSlugs,
        collectionTabs,
        isContentListOpen: selectIsContentListOpen(global),
      };
    },
  )(PortraitContent),
);
