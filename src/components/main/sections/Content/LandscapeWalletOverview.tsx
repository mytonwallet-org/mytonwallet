import React, { memo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNftCollection, ApiPerpsAccountPosition, ApiPerpsMarketAsset } from '../../../../api/types';
import type { OverviewCellSize } from '../../../../global/types';
import type { AssetsMenuHandler } from './hooks/useAssetsOverviewMenu';
import type { CollectiblesMenuHandler } from './hooks/useCollectiblesOverviewMenu';
import type { CollectionMenuHandler } from './hooks/useCollectionOverviewMenu';
import type { NftCollections } from './hooks/useNftCollectionMenuItems';

import { ANIMATION_LEVEL_MIN, TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../../config';
import { getCollectionKey } from '../../../../global/helpers/nfts';
import {
  selectCanReadPerps,
  selectCurrentAccountId,
  selectCurrentAccountPerps,
  selectCurrentAccountSettings,
  selectIsPerpsWalletBlockVisible,
  selectPerpsMarketAssetsById,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import getTestId from '../../../../util/getTestId';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { POSITIONS_PREVIEW_LIMIT, POSITIONS_SECTION_ID } from '../../../futures/helpers/buildPerpsSections';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useScrollButtonsVisibility from '../../../../hooks/useScrollButtonsVisibility';
import useCataloguePositions from '../../../futures/hooks/useCataloguePositions';
import usePerpsSnapshotPolling from '../../../futures/hooks/usePerpsSnapshotPolling';
import useAssetsOverviewMenu from './hooks/useAssetsOverviewMenu';
import useCollectiblesOverviewMenu from './hooks/useCollectiblesOverviewMenu';
import useCollectionOverviewMenu from './hooks/useCollectionOverviewMenu';
import useWalletOverview from './hooks/useWalletOverview';

import EdgeScrollButton from '../../../common/EdgeScrollButton';
import PositionList from '../../../futures/positions/PositionList';
import TopActions from '../Actions/TopActions';
import Activities from './Activities';
import Assets from './Assets';
import Nfts from './Nfts';
import OverviewCell from './OverviewCell';

import styles from './LandscapeWalletOverview.module.scss';

const SCROLL_CONTAINER_CLASS = 'landscape-overview-scroll';
const SCROLL_CONTAINER_SELECTOR = `.${SCROLL_CONTAINER_CLASS}`;

const MIN_VISIBLE_CELLS = 1;

interface OwnProps {
  totalTokensAmount: number;
  collections: NftCollections;
  collectionTabs?: ApiNftCollection[];
  visibleCollectionTabs: ApiNftCollection[];
  isNftsDataReady: boolean;
  isActive: boolean;
  onStakedTokenClick: (stakingId?: string) => void;
}

interface StateProps {
  overviewCellSize: OverviewCellSize;
  isAssetCellVisible: boolean;
  isCollectibleCellVisible: boolean;
  /** Absent until the first snapshot loads */
  perpsPositions?: ApiPerpsAccountPosition[];
  perpsAssetsById?: Record<string, ApiPerpsMarketAsset>;
  isPerpsBlockVisible: boolean;
  isPerpsSnapshotLoadFailed?: true;
  noAnimation: boolean;
}

function LandscapeWalletOverview({
  totalTokensAmount,
  collections,
  collectionTabs,
  visibleCollectionTabs,
  isNftsDataReady,
  isActive,
  overviewCellSize,
  isAssetCellVisible,
  isCollectibleCellVisible,
  perpsPositions,
  perpsAssetsById,
  isPerpsBlockVisible,
  isPerpsSnapshotLoadFailed,
  noAnimation,
  onStakedTokenClick,
}: OwnProps & StateProps) {
  const { openFuturesSection } = getActions();

  const lang = useLang();
  const rowRef = useRef<HTMLDivElement>();
  const rowContainerRef = useRef<HTMLDivElement>();
  const perpsPositionsCount = useCataloguePositions(perpsPositions, perpsAssetsById)?.length;
  const hasMorePositions = (perpsPositionsCount ?? 0) > POSITIONS_PREVIEW_LIMIT;

  // A failed load keeps polling, so a position opened on another device still shows up
  usePerpsSnapshotPolling(isPerpsBlockVisible, !perpsPositionsCount && !isPerpsSnapshotLoadFailed);

  const {
    items: nftCollectionItems,
    byKey: collectionByKey,
    totalVisibleCount: totalNftsAmount,
    shouldRenderHiddenNftsSection,
  } = collections;
  const {
    handleTokenClick,
    handleShowAllAssets,
    handleShowAllNfts,
    handleShowCollection,
  } = useWalletOverview();

  // The cell shows only with positions, as on iOS, so the overview does not jump when the first snapshot arrives empty
  const isPositionsCellVisible = Boolean(perpsPositionsCount);
  const positionsCellCount = isPositionsCellVisible ? 1 : 0;
  const totalVisibleCells = (isAssetCellVisible ? 1 : 0)
    + (isCollectibleCellVisible ? 1 : 0)
    + visibleCollectionTabs.length;
  // The positions cell has no hide option and disappears with the last position, so `canHideCurrentCell` does not count it
  const canHideCurrentCell = totalVisibleCells > MIN_VISIBLE_CELLS;
  const hasMoreAssets = totalTokensAmount > 0;
  const potentialMaxCells = (isAssetCellVisible ? 1 : 0)
    + (isCollectibleCellVisible ? 1 : 0)
    + (collectionTabs?.length ?? 0)
    + positionsCellCount;
  const shouldStretchCell = potentialMaxCells === MIN_VISIBLE_CELLS
    || (isNftsDataReady && totalVisibleCells + positionsCellCount === MIN_VISIBLE_CELLS);

  const getCollectionCaption = useLastCallback((collection: ApiNftCollection) => {
    if (collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION) return lang('Telegram Gifts');

    return collectionByKey.get(getCollectionKey(collection.chain, collection.address))?.name ?? '';
  });

  const handleShowAllPositions = useLastCallback(() => {
    openFuturesSection({ sectionId: POSITIONS_SECTION_ID });
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

  const { isLeftButtonVisible, isRightButtonVisible, scrollByOneCell } = useScrollButtonsVisibility({
    containerRef: rowRef,
    viewportRef: rowContainerRef,
    isDisabled: IS_TOUCH_ENV || shouldStretchCell,
    noAnimation,
  });

  return (
    <div className={buildClassName(styles.wrapper, 'custom-scroll', SCROLL_CONTAINER_CLASS)}>
      <TopActions isActive={isActive} />
      <div ref={rowContainerRef} className={styles.rowContainer}>
        <div
          ref={rowRef}
          className={buildClassName(styles.row, shouldStretchCell && styles.rowStretched, 'no-swipe')}
        >
          {isAssetCellVisible && (
            <OverviewCell<undefined, AssetsMenuHandler>
              caption={lang('Assets')}
              showAllLabel={lang('Show All Assets')}
              showAllIcon="showAll"
              showAllAmount={totalTokensAmount}
              showAllTestId={isActive ? getTestId('home_show_all') : undefined}
              menuItems={assetsMenuItems}
              size={overviewCellSize}
              isStretched={shouldStretchCell}
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
          {isPositionsCellVisible && (
            <OverviewCell
              caption={lang('Open Positions')}
              showAllLabel={lang('Show All Positions')}
              showAllIcon="positions"
              showAllAmount={perpsPositionsCount}
              size={overviewCellSize}
              isStretched={shouldStretchCell}
              onShowAllClick={hasMorePositions ? handleShowAllPositions : undefined}
            >
              <PositionList limit={POSITIONS_PREVIEW_LIMIT} />
            </OverviewCell>
          )}
          {isCollectibleCellVisible && (
            <OverviewCell<undefined, CollectiblesMenuHandler>
              caption={lang('Collectibles')}
              showAllLabel={lang('Show All Collectibles')}
              showAllIcon="collectibles"
              showAllAmount={totalNftsAmount}
              menuItems={collectiblesMenuItems}
              size={overviewCellSize}
              isStretched={shouldStretchCell}
              bodyClassName={styles.nftsCell}
              onShowAllClick={totalNftsAmount ? handleShowAllNfts : undefined}
              onMenuItemClick={handleCollectiblesMenuSelect}
            >
              <Nfts
                isActive
                isWidget
                isStretched={shouldStretchCell}
                scrollContainerSelector={SCROLL_CONTAINER_SELECTOR}
              />
            </OverviewCell>
          )}
          {visibleCollectionTabs.map((collection) => {
            const collectionCaption = getCollectionCaption(collection);
            const collectionKey = getCollectionKey(collection.chain, collection.address);
            return (
              <OverviewCell<ApiNftCollection, CollectionMenuHandler>
                key={`${collection.chain}_${collection.address}`}
                caption={collectionCaption}
                showAllLabel={lang(
                  'Show All %collection_name%',
                  { collection_name: collectionCaption },
                ) as string}
                showAllIcon={collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION ? 'gift' : 'collectibles'}
                showAllAmount={collectionByKey.get(collectionKey)?.count}
                clickArg={collection}
                menuItems={collectionMenuItems}
                size={overviewCellSize}
                isStretched={shouldStretchCell}
                bodyClassName={styles.nftsCell}
                onShowAllClick={handleShowCollection}
                onMenuItemClick={handleCollectionMenuSelect}
              >
                <Nfts
                  isActive
                  isWidget
                  isStretched={shouldStretchCell}
                  scrollContainerSelector={SCROLL_CONTAINER_SELECTOR}
                  collection={collection}
                />
              </OverviewCell>
            );
          })}
        </div>
        <EdgeScrollButton
          direction="left"
          isVisible={isLeftButtonVisible}
          onClick={scrollByOneCell}
        />
        <EdgeScrollButton
          direction="right"
          isVisible={isRightButtonVisible}
          onClick={scrollByOneCell}
        />
      </div>
      <div className={styles.activitiesWrapper}>
        <Activities
          isActive
          isWidget
          scrollContainerSelector={SCROLL_CONTAINER_SELECTOR}
        />
      </div>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountSettings = selectCurrentAccountSettings(global);
      return {
        overviewCellSize: accountSettings?.overviewCellSize ?? 'small',
        isAssetCellVisible: !accountSettings?.areAssetsHidden,
        isCollectibleCellVisible: !accountSettings?.areCollectiblesHidden,
        perpsPositions: selectCanReadPerps(global) ? selectCurrentAccountPerps(global)?.snapshot?.positions : undefined,
        perpsAssetsById: selectPerpsMarketAssetsById(global),
        isPerpsBlockVisible: selectIsPerpsWalletBlockVisible(global),
        isPerpsSnapshotLoadFailed: selectCurrentAccountPerps(global)?.isSnapshotLoadFailed,
        noAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(LandscapeWalletOverview),
);
