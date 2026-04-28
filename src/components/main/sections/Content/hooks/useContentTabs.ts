import { useEffect, useMemo, useRef } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { ApiChain, ApiNft, ApiNftCollection, ApiStakingState } from '../../../../../api/types';
import type { DropdownItem } from '../../../../ui/Dropdown';
import type { TabWithProperties } from '../../../../ui/TabList';
import { type Account, ContentTab, SettingsState } from '../../../../../global/types';

import {
  DEFAULT_CHAIN,
  IS_CORE_WALLET,
  PORTRAIT_MIN_ASSETS_TAB_VIEW,
  STAKING_SLUG_PREFIX,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../../config';
import { buildNftCollectionIndex, getCollectionKey } from '../../../../../global/helpers/nfts';
import { getChainsSupportingNft, getOrderedAccountChains } from '../../../../../util/chain';
import { compact } from '../../../../../util/iteratees';
import { getIsActiveStakingState } from '../../../../../util/staking';

import useEffectOnce from '../../../../../hooks/useEffectOnce';
import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';
import useSyncEffect from '../../../../../hooks/useSyncEffect';

import styles from '../Content.module.scss';

const MAIN_CONTENT_TABS_LENGTH = Object.values(ContentTab).length / 2;

interface OwnProps {
  byChain?: Account['byChain'];
  nfts?: Record<string, ApiNft>;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  collectionTabs?: ApiNftCollection[];
  activeContentTab?: ContentTab;
  activityReturnContentTab?: ContentTab;
  currentCollection?: ApiNftCollection;
  states?: ApiStakingState[];
  hasVesting: boolean;
  alwaysHiddenSlugs?: string[];
  tokensCount: number;
  isPortrait: boolean;
  isLandscape: boolean;
}

export default function useContentTabs({
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
  isPortrait,
  isLandscape,
}: OwnProps) {
  const {
    selectToken,
    showTokenActivity,
    setActiveContentTab,
    openNftCollection,
    closeNftCollection,
    openSettingsWithState,
  } = getActions();

  const lang = useLang();
  const activeNftKeyRef = useRef(0);

  const numberOfStaking = useMemo(() => {
    if (!states) return 0;

    const hiddenSlugs = new Set(alwaysHiddenSlugs);
    return states
      .filter(getIsActiveStakingState)
      .filter((state) => !hiddenSlugs.has(`${STAKING_SLUG_PREFIX}${state.tokenSlug}`))
      .length;
  }, [states, alwaysHiddenSlugs]);

  // Forces the NFT subtree to remount on every collection switch so that
  // virtualization/scroll state from the previous collection is discarded.
  // Incrementing (rather than toggling) keeps the key unique across rapid
  // switches between three or more collections within a single `Transition` cycle.
  useSyncEffect(() => {
    if (currentCollection) {
      activeNftKeyRef.current += 1;
    } else {
      activeNftKeyRef.current = 0;
    }
  }, [currentCollection]);

  const handleNftsMenuButtonClick = useLastCallback((value: string) => {
    if (value === 'hidden_nfts') {
      openSettingsWithState({ state: SettingsState.HiddenNfts });
    } else {
      const [address, chain] = parseCollectionId(value);
      openNftCollection({ chain: chain || DEFAULT_CHAIN, address }, { forceOnHeavyAnimation: true });
    }
  });

  const [nftCollections, nftCollectionNameByKey] = useMemo(() => {
    const { byKey } = buildNftCollectionIndex(nfts, blacklistedNftAddresses, whitelistedNftAddresses);

    const telegramGiftsKey = getCollectionKey('ton', TELEGRAM_GIFTS_SUPER_COLLECTION);
    const hasTelegramGifts = byKey.has(telegramGiftsKey);
    const unnamedLabel = lang('Unnamed collection');
    const telegramGiftsName = lang('Telegram Gifts');

    const nameByKey = new Map<string, string>();
    const items: DropdownItem[] = [];

    for (const [key, { chain, address, name }] of byKey) {
      if (key === telegramGiftsKey) {
        nameByKey.set(key, telegramGiftsName);
        continue;
      }
      const resolvedName = name ?? unnamedLabel;
      nameByKey.set(key, resolvedName);
      items.push({ value: `${address}@${chain}`, name: resolvedName });
    }

    items.sort((a, b) => a.name.localeCompare(b.name));

    if (hasTelegramGifts) {
      items.unshift({
        value: `${TELEGRAM_GIFTS_SUPER_COLLECTION}@ton`,
        name: telegramGiftsName,
        fontIcon: 'gift',
        withDelimiterAfter: true,
      });
    }

    return [items, nameByKey];
  }, [lang, nfts, blacklistedNftAddresses, whitelistedNftAddresses]);

  const visibleCollectionTabs = useMemo(() => (
    collectionTabs?.filter((tab) => nftCollectionNameByKey.has(`${tab.chain}_${tab.address}`)) ?? []
  ), [collectionTabs, nftCollectionNameByKey]);

  // Auto close collection when all nfts of this collection have left the wallet
  useEffect(() => {
    if (!currentCollection) return;
    const key = `${currentCollection.chain}_${currentCollection.address}`;
    if (!nftCollectionNameByKey.has(key)) {
      closeNftCollection();
    }
  }, [currentCollection, nftCollectionNameByKey, closeNftCollection]);

  const shouldRenderHiddenNftsSection = useMemo(() => {
    if (IS_CORE_WALLET) return false;

    const blacklistedAddressesSet = new Set(blacklistedNftAddresses);
    return Object.values(nfts ?? {}).some(
      (nft) => blacklistedAddressesSet.has(nft.address) || nft.isHidden,
    );
  }, [blacklistedNftAddresses, nfts]);

  const totalTokensAmount = tokensCount + (hasVesting ? 1 : 0) + numberOfStaking;
  const shouldShowSeparateAssetsPanel = isPortrait && totalTokensAmount <= PORTRAIT_MIN_ASSETS_TAB_VIEW;

  const [mainContentTabsCount, tabs] = useMemo(() => {
    const nftChains = getChainsSupportingNft();
    const doesSupportNft = byChain && getOrderedAccountChains(byChain).some((chain) => nftChains.has(chain));

    const mainContentTabs = compact([
      !shouldShowSeparateAssetsPanel && { id: ContentTab.Assets, title: lang('Assets'), className: styles.tab },
      { id: ContentTab.Activity, title: lang('Activity'), className: styles.tab },
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

    const collectionTabsItems = compact(visibleCollectionTabs.map((tab, index) => {
      const name = nftCollectionNameByKey.get(`${tab.chain}_${tab.address}`);
      if (!name) return undefined;

      return {
        id: MAIN_CONTENT_TABS_LENGTH + index,
        title: name,
        className: styles.tab,
        icon: tab.address === TELEGRAM_GIFTS_SUPER_COLLECTION ? 'icon-gift' : undefined,
      };
    }));

    return [
      mainContentTabs.length,
      [...mainContentTabs, ...collectionTabsItems] as TabWithProperties<ContentTab>[],
    ] as const;
  }, [
    visibleCollectionTabs, byChain, lang, nftCollections, nftCollectionNameByKey,
    shouldRenderHiddenNftsSection, shouldShowSeparateAssetsPanel,
  ]);

  const activeTabIndex = useMemo(
    () => {
      const tabIndex = tabs.findIndex((tab) => tab.id === activeContentTab);

      if (tabIndex === -1) {
        return isLandscape ? ContentTab.Overview : ContentTab.Assets;
      }

      return tabIndex;
    },
    [tabs, activeContentTab, isLandscape],
  );

  const contentTransitionKey = useMemo(() => {
    if (!currentCollection || tabs[activeTabIndex].id === ContentTab.Nft) return activeTabIndex;

    const nftCollectionIndex = visibleCollectionTabs.findIndex((e) => e.address === currentCollection.address);

    return nftCollectionIndex === -1 ? activeTabIndex : mainContentTabsCount + nftCollectionIndex;
  }, [activeTabIndex, visibleCollectionTabs, currentCollection, mainContentTabsCount, tabs]);

  useEffectOnce(() => {
    if (isLandscape) {
      setActiveContentTab({ tab: ContentTab.Overview });
    } else if (activeContentTab === undefined) {
      setActiveContentTab({ tab: ContentTab.Assets });
    }
  });

  const handleHeaderBackClick = useLastCallback(() => {
    const returnTab = activeContentTab === ContentTab.Activity && activityReturnContentTab !== undefined
      ? activityReturnContentTab
      : ContentTab.Overview;
    selectToken({ slug: undefined }, { forceOnHeavyAnimation: true });
    setActiveContentTab({ tab: returnTab });
  });

  const handleSwitchTab = useLastCallback((tab: ContentTab) => {
    const tabIndex = tabs.findIndex(({ id }) => id === tab);
    if (tabIndex >= mainContentTabsCount) {
      const collection = visibleCollectionTabs[tabIndex - mainContentTabsCount];
      openNftCollection(collection, { forceOnHeavyAnimation: true });
      return;
    }

    selectToken({ slug: undefined }, { forceOnHeavyAnimation: true });
    setActiveContentTab({ tab });
  });

  const handleClickAsset = useLastCallback((slug: string) => {
    showTokenActivity({ slug, returnTab: ContentTab.Assets });
  });

  return {
    tabs,
    mainContentTabsCount,
    activeTabIndex,
    contentTransitionKey,
    visibleCollectionTabs,
    totalTokensAmount,
    shouldShowSeparateAssetsPanel,
    activeNftKey: activeNftKeyRef.current,
    handleSwitchTab,
    handleHeaderBackClick,
    handleClickAsset,
  };
}

function parseCollectionId(id: string) {
  return id.split('@') as [address: string, chain: ApiChain];
}
