import React, { memo, useEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiStakingState } from '../../../../api/types';
import type { DropdownItem } from '../../../ui/Dropdown';
import { ContentTab, SettingsState } from '../../../../global/types';

import {
  IS_CORE_WALLET,
  LANDSCAPE_MIN_ASSETS_TAB_VIEW,
  PORTRAIT_MIN_ASSETS_TAB_VIEW,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../config';
import { requestMeasure, requestMutation } from '../../../../lib/fasterdom/fasterdom';
import {
  selectAccountStakingStates,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectDoesAccountSupportNft,
  selectEnabledTokensCountMemoizedFor,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { captureEvents, SwipeDirection } from '../../../../util/captureEvents';
import { compact } from '../../../../util/iteratees';
import { getIsActiveStakingState } from '../../../../util/staking';
import { IS_TOUCH_ENV, REM, STICKY_CARD_INTERSECTION_THRESHOLD } from '../../../../util/windowEnvironment';
import windowSize from '../../../../util/windowSize';
import { calcSafeAreaTop } from '../../helpers/calcSafeAreaTop';
import { getScrollableContainer } from '../../helpers/scrollableContainer';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useEffectOnce from '../../../../hooks/useEffectOnce';
import useElementVisibility from '../../../../hooks/useElementVisibility';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrolledState from '../../../../hooks/useScrolledState';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import CategoryHeader from '../../../explore/CategoryHeader';
import Explore from '../../../explore/Explore';
import TabList from '../../../ui/TabList';
import Transition from '../../../ui/Transition';
import HideNftModal from '../../modals/HideNftModal';
import Activity from './Activities';
import Assets from './Assets';
import NftCollectionHeader from './NftCollectionHeader';
import Nfts from './Nfts';
import NftSelectionHeader from './NftSelectionHeader';
import { OPEN_CONTEXT_MENU_CLASS_NAME } from './Token';

import styles from './Content.module.scss';

interface OwnProps {
  isActive?: boolean;
  onTabsStuck?: (isStuck: boolean) => void;
  onStakedTokenClick: NoneToVoidFunction;
}

interface StateProps {
  tokensCount: number;
  nfts?: Record<string, ApiNft>;
  currentCollectionAddress?: string;
  selectedAddresses?: string[];
  activeContentTab?: ContentTab;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  states?: ApiStakingState[];
  hasVesting: boolean;
  selectedNftsToHide?: {
    addresses: string[];
    isCollection: boolean;
  };
  currentSiteCategoryId?: number;
  doesSupportNft: boolean;
  collectionTabs?: string[];
}

const MAIN_CONTENT_TABS_LENGTH = Object.values(ContentTab).length / 2;
const INTERSECTION_APPROXIMATION_VALUE_PX = 3 * REM;

let activeNftKey = 0;

function Content({
  isActive,
  activeContentTab,
  tokensCount,
  nfts,
  currentCollectionAddress,
  selectedAddresses,
  onStakedTokenClick,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  selectedNftsToHide,
  states,
  hasVesting,
  currentSiteCategoryId,
  doesSupportNft,
  collectionTabs,
  onTabsStuck,
}: OwnProps & StateProps) {
  const {
    selectToken,
    showTokenActivity,
    setActiveContentTab,
    openNftCollection,
    closeNftCollection,
    openSettingsWithState,
  } = getActions();

  const lang = useLang();
  const { isPortrait, isLandscape } = useDeviceScreen();
  const tabsRef = useRef<HTMLDivElement>();
  const hasNftSelection = Boolean(selectedAddresses?.length);

  const numberOfStaking = useMemo(() => {
    return states?.filter(getIsActiveStakingState).length ?? 0;
  }, [states]);

  useSyncEffect(() => {
    if (currentCollectionAddress) {
      activeNftKey += 1;
    } else {
      activeNftKey = 0;
    }
  }, [currentCollectionAddress]);

  const handleNftsMenuButtonClick = useLastCallback((value: string) => {
    if (value === 'hidden_nfts') {
      openSettingsWithState({ state: SettingsState.HiddenNfts });
    } else {
      openNftCollection({ address: value }, { forceOnHeavyAnimation: true });
    }
  });

  const nftCollections = useMemo(() => {
    const blacklistedNftAddressesSet = new Set(blacklistedNftAddresses);
    const whitelistedNftAddressesSet = new Set(whitelistedNftAddresses);

    let hasTelegramGifts = false;

    const itemsByAddress = Object.values(nfts ?? {})
      .reduce((acc, nft) => {
        if (nft.collectionAddress && (
          !nft.isHidden || whitelistedNftAddressesSet.has(nft.address)
        ) && (
          !blacklistedNftAddressesSet.has(nft.address)
        )) {
          if (!acc[nft.collectionAddress]) {
            acc[nft.collectionAddress] = {
              value: nft.collectionAddress,
              name: nft.collectionName || lang('Unnamed collection'),
            };
          }

          if (!hasTelegramGifts && nft.isTelegramGift) {
            hasTelegramGifts = true;
          }
        }

        return acc;
      }, {} as Record<string, DropdownItem>);

    const items = Object.values(itemsByAddress);

    items.sort((a, b) => a.name.localeCompare(b.name));

    if (hasTelegramGifts) {
      items.unshift({
        value: TELEGRAM_GIFTS_SUPER_COLLECTION,
        name: lang('Telegram Gifts'),
        fontIcon: 'gift',
        withDelimiterAfter: true,
      });
    }

    return items;
  }, [lang, nfts, blacklistedNftAddresses, whitelistedNftAddresses]);

  const shouldRenderHiddenNftsSection = useMemo(() => {
    if (IS_CORE_WALLET) return false;

    const blacklistedAddressesSet = new Set(blacklistedNftAddresses);
    return Object.values(nfts ?? {}).some(
      (nft) => blacklistedAddressesSet.has(nft.address) || nft.isHidden,
    );
  }, [blacklistedNftAddresses, nfts]);

  const transitionRef = useRef<HTMLDivElement>();

  const totalTokensAmount = tokensCount + (hasVesting ? 1 : 0) + numberOfStaking;
  const shouldShowSeparateAssetsPanel = totalTokensAmount <= (
    isPortrait ? PORTRAIT_MIN_ASSETS_TAB_VIEW : LANDSCAPE_MIN_ASSETS_TAB_VIEW
  );

  const [mainContentTabsCount, tabs] = useMemo(() => {
    const mainContentTabs = compact([
      !shouldShowSeparateAssetsPanel && { id: ContentTab.Assets, title: lang('Assets'), className: styles.tab },
      { id: ContentTab.Activity, title: lang('Activity'), className: styles.tab },
      !isPortrait && !IS_CORE_WALLET && { id: ContentTab.Explore, title: lang('Explore'), className: styles.tab },
      doesSupportNft && {
        id: ContentTab.Nft,
        title: lang('Collectibles'),
        className: styles.tab,
        menuItems: shouldRenderHiddenNftsSection
          ? [
            ...nftCollections,
            {
              name: lang('Hidden NFTs'),
              value: 'hidden_nfts',
              withDelimiter: true,
            } as DropdownItem,
          ]
          : nftCollections,
        onMenuItemClick: handleNftsMenuButtonClick,
      },
    ]);

    return [
      mainContentTabs.length,
      mainContentTabs.concat(
        collectionTabs?.map((collectionAddress, index) => {
          const collection = nftCollections.find((nc) => nc.value === collectionAddress);
          if (!collection) return undefined;

          return {
            id: MAIN_CONTENT_TABS_LENGTH + index,
            title: collection.name,
            className: styles.tab,
            collectionAddress,
            icon: collectionAddress === TELEGRAM_GIFTS_SUPER_COLLECTION ? 'icon-gift' : undefined,
          };
        }).filter(Boolean) ?? [],
      ),
    ];
  }, [
    collectionTabs, doesSupportNft, isPortrait, lang, nftCollections,
    shouldRenderHiddenNftsSection, shouldShowSeparateAssetsPanel,
  ]);

  const activeTabIndex = useMemo(
    () => {
      const tabIndex = tabs.findIndex((tab) => tab.id === activeContentTab);

      if (tabIndex === -1) {
        return ContentTab.Assets;
      }

      return tabIndex;
    },
    [tabs, activeContentTab],
  );

  const contentTransitionKey = useMemo(() => {
    if (!currentCollectionAddress || tabs[activeTabIndex].id === ContentTab.Nft) return activeTabIndex;

    const nftCollectionIndex = collectionTabs?.indexOf(currentCollectionAddress) ?? -1;

    return nftCollectionIndex === -1 ? activeTabIndex : mainContentTabsCount + nftCollectionIndex;
  }, [activeTabIndex, collectionTabs, currentCollectionAddress, mainContentTabsCount, tabs]);

  useEffectOnce(() => {
    if (activeContentTab === undefined) {
      setActiveContentTab({ tab: ContentTab.Assets });
    }
  });

  const handleSwitchTab = useLastCallback((tab: ContentTab | number) => {
    // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
    const tabIndex = tabs.findIndex(({ id }) => id === tab);
    if (tabIndex >= mainContentTabsCount) {
      const collectionAddress = collectionTabs![tabIndex - mainContentTabsCount];
      openNftCollection({ address: collectionAddress }, { forceOnHeavyAnimation: true });
      return;
    }

    selectToken({ slug: undefined }, { forceOnHeavyAnimation: true });
    setActiveContentTab({ tab });
  });

  const handleScrollToTop = useLastCallback(() => {
    const scrollContainer = getScrollableContainer(transitionRef.current, isPortrait);
    scrollContainer?.scrollTo(0, 0);
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
    update: updateScrolledState,
  } = useScrolledState();

  useHistoryBack({
    isActive: activeTabIndex !== 0,
    onBack: () => handleSwitchTab(ContentTab.Assets),
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
      e.target.classList.toggle(styles.tabsContainerStuck, isStuck);
    });
  });

  useElementVisibility({
    isDisabled: !isPortrait,
    targetRef: tabsRef,
    rootMargin: `${intersectionRootMarginTop}px 0px 0px 0px`,
    threshold: [1],
    cb: handleTabIntersection,
  });

  useEffect(() => {
    if (!IS_TOUCH_ENV) {
      return undefined;
    }

    return captureEvents(transitionRef.current!, {
      includedClosestSelector: '.swipe-container',
      excludedClosestSelector: '.dapps-feed',
      onSwipe: (e, direction) => {
        if (
          direction === SwipeDirection.Up
          || direction === SwipeDirection.Down
          // For preventing swipe in one interaction with a long press event handler
          || (e.target as HTMLElement | null)?.closest(`.${OPEN_CONTEXT_MENU_CLASS_NAME}`)
        ) {
          return false;
        }

        if (direction === SwipeDirection.Left) {
          const tab = tabs[Math.min(tabs.length - 1, activeTabIndex + 1)];
          handleSwitchTab(tab.id);
          return true;
        } else if (direction === SwipeDirection.Right) {
          if (currentSiteCategoryId) return false;

          if (currentCollectionAddress) {
            closeNftCollection();
          } else {
            const tab = tabs[Math.max(0, activeTabIndex - 1)];
            handleSwitchTab(tab.id);
          }
          return true;
        }

        return false;
      },
      selectorToPreventScroll: '.custom-scroll',
    });
  }, [tabs, handleSwitchTab, activeTabIndex, currentCollectionAddress, currentSiteCategoryId]);

  const handleClickAsset = useLastCallback((slug: string) => {
    showTokenActivity({ slug });
  });

  // `isScrolled` state should be updated after tab is switched
  const handleContentTransitionStop = useLastCallback(() => {
    if (isPortrait) return;

    requestMeasure(() => {
      const scrollContainer = getScrollableContainer(transitionRef.current, isPortrait);
      if (scrollContainer) {
        updateScrolledState(scrollContainer as HTMLElement);
      }
    });
  });

  const containerClassName = buildClassName(
    styles.container,
    IS_TOUCH_ENV && 'swipe-container',
    isPortrait ? styles.portraitContainer : styles.landscapeContainer,
  );

  function renderTabsPanel() {
    if (hasNftSelection) {
      return <NftSelectionHeader />;
    }

    if (!isPortrait && currentSiteCategoryId) {
      return <CategoryHeader id={currentSiteCategoryId} />;
    }

    return currentCollectionAddress ? <NftCollectionHeader key="collection" /> : (
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

  function renderCurrentTab(isActive: boolean) {
    // When assets are shown separately, there is effectively no tab with index 0,
    // so we fall back to next tab to not break parent's component logic.
    if (activeTabIndex === 0 && shouldShowSeparateAssetsPanel && !currentCollectionAddress) {
      return (
        <Activity
          isActive={isActive}
          totalTokensAmount={totalTokensAmount}
          onScroll={isLandscape ? handleContentScroll : undefined}
        />
      );
    }

    if (currentCollectionAddress && tabs[activeTabIndex].id !== ContentTab.Nft) {
      return (
        <div
          className="nfts-container"
          onScroll={isLandscape ? handleContentScroll : undefined}
        >
          <Nfts
            key={`custom:${currentCollectionAddress}`}
            isActive={isActive}
          />
        </div>
      );
    }

    switch (tabs[activeTabIndex].id) {
      case ContentTab.Assets:
        return (
          <Assets
            isActive={isActive}
            onTokenClick={handleClickAsset}
            onStakedTokenClick={onStakedTokenClick}
            onScroll={isLandscape ? handleContentScroll : undefined}
          />
        );
      case ContentTab.Activity:
        return (
          <Activity
            isActive={isActive}
            totalTokensAmount={totalTokensAmount}
            onScroll={isLandscape ? handleContentScroll : undefined}
          />
        );
      case ContentTab.Explore:
        return <Explore isActive={isActive} onScroll={isLandscape ? handleContentScroll : undefined} />;
      case ContentTab.Nft:
        return (
          <Transition
            activeKey={activeNftKey}
            name={isPortrait ? 'slide' : 'slideFade'}
            className="nfts-container"
            onScroll={isLandscape ? handleContentScroll : undefined}
          >
            <Nfts key={currentCollectionAddress || 'all'} isActive={isActive} />
          </Transition>
        );
      default:
        return undefined;
    }
  }

  function renderContent() {
    const headerTransitionKey = hasNftSelection || (!isPortrait && currentSiteCategoryId)
      ? 2
      : (currentCollectionAddress ? 1 : 0);

    return (
      <>
        <div
          ref={tabsRef}
          className={buildClassName(
            styles.tabsContainer,
            currentCollectionAddress && styles.tabsContainerForNftCollection,
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
            {renderTabsPanel()}
          </Transition>
        </div>
        <Transition
          ref={transitionRef}
          name={isPortrait ? 'slide' : 'slideFade'}
          activeKey={contentTransitionKey}
          renderCount={mainContentTabsCount + (collectionTabs?.length ?? 0)}
          className={buildClassName(styles.slides, 'content-transition')}
          slideClassName={buildClassName(styles.slide, 'custom-scroll')}
          onStop={handleContentTransitionStop}
          onScroll={isLandscape ? handleContentScroll : undefined}
        >
          {renderCurrentTab}
        </Transition>
      </>
    );
  }

  return (
    <div className={containerClassName}>
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
      <div className={buildClassName(isPortrait ? styles.contentPanel : styles.landscapeContentPanel)}>
        {renderContent()}
      </div>
      <HideNftModal
        isOpen={Boolean(selectedNftsToHide?.addresses.length)}
        selectedNftsToHide={selectedNftsToHide}
      />
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountId = global.currentAccountId;
      const {
        activeContentTab,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        selectedNftsToHide,
        vesting,
        nfts: {
          byAddress: nfts,
          currentCollectionAddress,
          selectedAddresses,
          collectionTabs,
        } = {},
        currentSiteCategoryId,
      } = selectCurrentAccountState(global) ?? {};

      const tokens = selectCurrentAccountTokens(global);
      const tokensCount = selectEnabledTokensCountMemoizedFor(global.currentAccountId!)(tokens);
      const hasVesting = Boolean(vesting?.info?.length);
      const states = accountId ? selectAccountStakingStates(global, accountId) : undefined;
      const doesSupportNft = selectDoesAccountSupportNft(global);

      return {
        nfts,
        currentCollectionAddress,
        selectedAddresses,
        tokensCount,
        activeContentTab,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        selectedNftsToHide,
        states,
        hasVesting,
        currentSiteCategoryId,
        doesSupportNft,
        collectionTabs,
      };
    },
    (global, _, stickToFirst) => stickToFirst(global.currentAccountId),
  )(Content),
);
