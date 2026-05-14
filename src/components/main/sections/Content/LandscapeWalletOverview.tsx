import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection } from '../../../../api/types';
import type { OverviewCellSize } from '../../../../global/types';
import type { AssetsMenuHandler } from './hooks/useAssetsOverviewMenu';
import type { CollectiblesMenuHandler } from './hooks/useCollectiblesOverviewMenu';
import type { CollectionMenuHandler } from './hooks/useCollectionOverviewMenu';
import { ContentTab } from '../../../../global/types';

import { ANIMATION_LEVEL_MIN, TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../../config';
import { getCollectionKey } from '../../../../global/helpers/nfts';
import {
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useAssetsOverviewMenu from './hooks/useAssetsOverviewMenu';
import useCollectiblesOverviewMenu from './hooks/useCollectiblesOverviewMenu';
import useCollectionOverviewMenu from './hooks/useCollectionOverviewMenu';
import useNftCollectionMenuItems from './hooks/useNftCollectionMenuItems';
import useScrollButtonsVisibility from './hooks/useScrollButtonsVisibility';

import LandscapeTopActions from '../Actions/LandscapeTopActions';
import Activities from './Activities';
import Assets from './Assets';
import Nfts from './Nfts';
import OverviewCell from './OverviewCell';
import OverviewScrollButton from './OverviewScrollButton';

import styles from './LandscapeWalletOverview.module.scss';

const SCROLL_CONTAINER_CLASS = 'landscape-overview-scroll';
const SCROLL_CONTAINER_SELECTOR = `.${SCROLL_CONTAINER_CLASS}`;

const MIN_VISIBLE_CELLS = 1;

interface OwnProps {
  totalTokensAmount: number;
  onStakedTokenClick: (stakingId?: string) => void;
}

interface StateProps {
  collectionTabs?: ApiNftCollection[];
  nftsByAddress?: Record<string, ApiNft>;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  overviewCellSize: OverviewCellSize;
  isAssetCellVisible: boolean;
  isCollectibleCellVisible: boolean;
  noAnimation: boolean;
}

function LandscapeWalletOverview({
  totalTokensAmount,
  collectionTabs,
  nftsByAddress,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  overviewCellSize,
  isAssetCellVisible,
  isCollectibleCellVisible,
  noAnimation,
  onStakedTokenClick,
}: OwnProps & StateProps) {
  const { setActiveContentTab, showTokenActivity, openNftCollection } = getActions();

  const lang = useLang();
  const rowRef = useRef<HTMLDivElement>();

  const {
    items: nftCollectionItems,
    byKey: collectionByKey,
    totalVisibleCount: totalNftsAmount,
    shouldRenderHiddenNftsSection,
  } = useNftCollectionMenuItems({
    nfts: nftsByAddress,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
  });

  const visibleCollectionTabs = useMemo(() => (
    collectionTabs?.filter((tab) => collectionByKey.has(getCollectionKey(tab.chain, tab.address))) ?? []
  ), [collectionTabs, collectionByKey]);

  const totalVisibleCells = (isAssetCellVisible ? 1 : 0)
    + (isCollectibleCellVisible ? 1 : 0)
    + visibleCollectionTabs.length;
  const canHideCurrentCell = totalVisibleCells > MIN_VISIBLE_CELLS;
  const hasMoreAssets = totalTokensAmount > 0;
  const isNftsDataReady = nftsByAddress !== undefined;
  const potentialMaxCells = (isAssetCellVisible ? 1 : 0)
    + (isCollectibleCellVisible ? 1 : 0)
    + (collectionTabs?.length ?? 0);
  const shouldStretchCell = potentialMaxCells === MIN_VISIBLE_CELLS
    || (isNftsDataReady && totalVisibleCells === MIN_VISIBLE_CELLS);
  const stretchedCellClass = shouldStretchCell ? styles.stretchedCell : undefined;

  const getCollectionCaption = useLastCallback((collection: ApiNftCollection) => {
    if (collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION) return lang('Telegram Gifts');

    return collectionByKey.get(getCollectionKey(collection.chain, collection.address))?.name ?? '';
  });

  const handleTokenClick = useLastCallback((slug: string) => {
    showTokenActivity({ slug, returnTab: ContentTab.Overview });
  });

  const handleShowAllAssets = useLastCallback(() => {
    setActiveContentTab({ tab: ContentTab.Assets });
  });

  const handleShowAllNfts = useLastCallback(() => {
    setActiveContentTab({ tab: ContentTab.Nft });
  });

  const handleShowCollection = useLastCallback((collection: ApiNftCollection) => {
    openNftCollection({ address: collection.address, chain: collection.chain });
  });
  const {
    menuItems: assetsMenuItems,
    handleMenuItemSelect: handleAssetsMenuSelect,
  } = useAssetsOverviewMenu({
    overviewCellSize,
    isCollectibleCellVisible,
    canHide: canHideCurrentCell,
    hiddenCheckClassName: styles.hiddenCheck,
  });

  const {
    menuItems: collectiblesMenuItems,
    handleMenuItemSelect: handleCollectiblesMenuSelect,
  } = useCollectiblesOverviewMenu({
    overviewCellSize,
    canHide: canHideCurrentCell,
    isAssetCellVisible,
    hiddenCheckClassName: styles.hiddenCheck,
    nftCollectionItems,
    shouldRenderHiddenNftsSection,
  });

  const {
    menuItems: collectionMenuItems,
    handleMenuItemSelect: handleCollectionMenuSelect,
  } = useCollectionOverviewMenu({
    overviewCellSize,
    canHide: canHideCurrentCell,
    isAssetCellVisible,
    isCollectibleCellVisible,
    hiddenCheckClassName: styles.hiddenCheck,
  });

  const { canScrollLeft, canScrollRight, scrollByOneCell } = useScrollButtonsVisibility({
    containerRef: rowRef,
    isDisabled: shouldStretchCell,
    noAnimation,
  });

  return (
    <div className={buildClassName(styles.wrapper, 'custom-scroll', SCROLL_CONTAINER_CLASS)}>
      <LandscapeTopActions />
      <div className={styles.rowContainer}>
        <div
          ref={rowRef}
          className={buildClassName(styles.row, shouldStretchCell && styles.rowStretched, 'no-swipe')}
        >
          {isAssetCellVisible && (
            <OverviewCell<undefined, AssetsMenuHandler>
              caption={lang('Assets')}
              showAllLabel={lang('Show All Assets')}
              showAllIcon="icon-show-all"
              showAllAmount={totalTokensAmount}
              menuItems={assetsMenuItems}
              size={overviewCellSize}
              className={stretchedCellClass}
              onShowAllClick={hasMoreAssets ? handleShowAllAssets : undefined}
              onMenuItemClick={handleAssetsMenuSelect}
            >
              <Assets
                isActive
                isWidget
                onTokenClick={handleTokenClick}
                onStakedTokenClick={onStakedTokenClick}
              />
            </OverviewCell>
          )}
          {isCollectibleCellVisible && (
            <OverviewCell<undefined, CollectiblesMenuHandler>
              caption={lang('Collectibles')}
              showAllLabel={lang('Show All Collectibles')}
              showAllIcon="icon-show-all-collectibles"
              showAllAmount={totalNftsAmount}
              menuItems={collectiblesMenuItems}
              size={overviewCellSize}
              className={stretchedCellClass}
              bodyClassName={styles.nftsCell}
              onShowAllClick={totalNftsAmount ? handleShowAllNfts : undefined}
              onMenuItemClick={handleCollectiblesMenuSelect}
            >
              <Nfts
                isActive
                isWidget
                isStretched={shouldStretchCell}
              />
            </OverviewCell>
          )}
          {visibleCollectionTabs.map((collection) => {
            const collectionCaption = getCollectionCaption(collection);
            const collectionKey = getCollectionKey(collection.chain, collection.address);
            const isTelegramGifts = collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION;
            return (
              <OverviewCell<ApiNftCollection, CollectionMenuHandler>
                key={`${collection.chain}_${collection.address}`}
                caption={collectionCaption}
                showAllLabel={lang(
                  'Show All %collection_name%',
                  { collection_name: collectionCaption },
                ) as string}
                showAllIcon={isTelegramGifts
                  ? buildClassName(styles.gifIconFix, 'icon-gift')
                  : 'icon-show-all-collectibles'}
                showAllAmount={collectionByKey.get(collectionKey)?.count}
                clickArg={collection}
                menuItems={collectionMenuItems}
                size={overviewCellSize}
                className={stretchedCellClass}
                bodyClassName={styles.nftsCell}
                onShowAllClick={handleShowCollection}
                onMenuItemClick={handleCollectionMenuSelect}
              >
                <Nfts
                  isActive
                  isWidget
                  isStretched={shouldStretchCell}
                  collection={collection}
                />
              </OverviewCell>
            );
          })}
        </div>
        <OverviewScrollButton
          direction="left"
          isVisible={canScrollLeft}
          onClick={scrollByOneCell}
        />
        <OverviewScrollButton
          direction="right"
          isVisible={canScrollRight}
          onClick={scrollByOneCell}
        />
      </div>
      <div className={styles.activitiesWrapper}>
        <Activities
          isActive
          isWidget
          totalTokensAmount={totalTokensAmount}
          scrollContainerSelector={SCROLL_CONTAINER_SELECTOR}
        />
      </div>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountState = selectCurrentAccountState(global);
      const accountSettings = selectCurrentAccountSettings(global);
      return {
        collectionTabs: accountState?.nfts?.collectionTabs,
        nftsByAddress: accountState?.nfts?.byAddress,
        blacklistedNftAddresses: accountState?.blacklistedNftAddresses,
        whitelistedNftAddresses: accountState?.whitelistedNftAddresses,
        overviewCellSize: accountSettings?.overviewCellSize ?? 'small',
        isAssetCellVisible: !accountSettings?.areAssetsHidden,
        isCollectibleCellVisible: !accountSettings?.areCollectiblesHidden,
        noAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(LandscapeWalletOverview),
);
