import React, { memo, useMemo, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNftCollection } from '../../../../api/types';
import type { DropdownItem } from '../../../ui/Dropdown';
import type { TabWithProperties } from '../../../ui/TabList';
import type { NftCollections } from './hooks/useNftCollectionMenuItems';
import { ContentTab } from '../../../../global/types';

import { TELEGRAM_GIFTS_SUPER_COLLECTION } from '../../../../config';
import { getCollectionKey } from '../../../../global/helpers/nfts';
import { selectActivityHistoryIds, selectCurrentAccountId } from '../../../../global/selectors';
import getTestId from '../../../../util/getTestId';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useWalletOverview from './hooks/useWalletOverview';

import WalletPositions from '../../../futures/positions/WalletPositions';
import TabList from '../../../ui/TabList';
import Activities from './Activities';
import Assets from './Assets';
import HomeExploreSection from './HomeExploreSection';
import Nfts from './Nfts';
import OverviewCell from './OverviewCell';

import styles from './PortraitWalletOverview.module.scss';

const TOKENS_LIMIT = 4;
const NFTS_LIMIT = 6;
const ACTIVITIES_LIMIT = 5;

const ALL_COLLECTIBLES_TAB_INDEX = 0;

interface OwnProps {
  totalTokensAmount: number;
  collections: NftCollections;
  visibleCollectionTabs: ApiNftCollection[];
  collectiblesMenuItems?: DropdownItem[];
  onCollectiblesMenuItemClick?: (value: string) => void;
  onStakedTokenClick: (stakingId?: string) => void;
}

interface StateProps {
  hasActivity: boolean;
}

function PortraitWalletOverview({
  totalTokensAmount,
  collections,
  visibleCollectionTabs,
  collectiblesMenuItems,
  hasActivity,
  onCollectiblesMenuItemClick,
  onStakedTokenClick,
}: OwnProps & StateProps) {
  const { setActiveContentTab } = getActions();

  const lang = useLang();
  const [selectedCollectionKey, setSelectedCollectionKey] = useState<string>();

  const { byKey: collectionByKey, nameByKey: collectionNameByKey, totalVisibleCount: totalNftsAmount } = collections;
  const {
    handleTokenClick,
    handleShowAllAssets,
    handleShowAllNfts,
    handleShowCollection,
  } = useWalletOverview();

  const collectiblesTabs = useMemo<TabWithProperties[]>(() => [
    { id: ALL_COLLECTIBLES_TAB_INDEX, title: lang('All'), className: styles.collectiblesTab },
    ...visibleCollectionTabs.map((collection, index) => ({
      id: index + 1,
      title: collectionNameByKey.get(getCollectionKey(collection.chain, collection.address)) ?? '',
      className: styles.collectiblesTab,
    })),
  ], [lang, visibleCollectionTabs, collectionNameByKey]);

  // A pinned collection disappears once its last NFT leaves the wallet, which returns the selection to `All`
  const activeCollectiblesTabIndex = selectedCollectionKey
    ? visibleCollectionTabs.findIndex((c) => getCollectionKey(c.chain, c.address) === selectedCollectionKey) + 1
    : ALL_COLLECTIBLES_TAB_INDEX;
  const activeCollection = visibleCollectionTabs[activeCollectiblesTabIndex - 1] as ApiNftCollection | undefined;
  const activeCollectionKey = activeCollection && selectedCollectionKey;
  const activeCollectiblesCount = activeCollectionKey
    ? collectionByKey.get(activeCollectionKey)?.count ?? 0
    : totalNftsAmount;

  const assetsLimit = totalTokensAmount > TOKENS_LIMIT + 1 ? TOKENS_LIMIT : undefined;

  const handleShowAllCollectibles = useLastCallback(() => {
    if (activeCollection) {
      handleShowCollection(activeCollection);
    } else {
      handleShowAllNfts();
    }
  });

  const handleSwitchCollectiblesTab = useLastCallback((index: number) => {
    const collection = visibleCollectionTabs[index - 1] as ApiNftCollection | undefined;

    setSelectedCollectionKey(collection && getCollectionKey(collection.chain, collection.address));
  });

  const handleShowAllActivity = useLastCallback(() => {
    setActiveContentTab({ tab: ContentTab.Activity });
  });

  return (
    <div className={styles.root}>
      <OverviewCell
        showAllIcon="showAll"
        showAllLabel={lang('Show All Assets')}
        showAllAmount={totalTokensAmount}
        showAllTestId={getTestId('home_show_all')}
        onShowAllClick={assetsLimit !== undefined ? handleShowAllAssets : undefined}
      >
        <Assets
          isActive
          isWidget
          limit={assetsLimit}
          onTokenClick={handleTokenClick}
          onStakedTokenClick={onStakedTokenClick}
        />
      </OverviewCell>

      <WalletPositions />

      {totalNftsAmount > 0 && (
        <OverviewCell
          caption={lang('Collectibles')}
          showAllIcon={activeCollection?.address === TELEGRAM_GIFTS_SUPER_COLLECTION ? 'gift' : 'collectibles'}
          showAllLabel={(activeCollectionKey
            ? lang('Show All %collection_name%', {
              collection_name: collectionNameByKey.get(activeCollectionKey),
            })
            : lang('Show All Collectibles')) as string}
          showAllAmount={activeCollectiblesCount}
          menuItems={collectiblesMenuItems}
          bodyClassName={styles.nftsCell}
          onShowAllClick={activeCollectiblesCount > NFTS_LIMIT ? handleShowAllCollectibles : undefined}
          onMenuItemClick={onCollectiblesMenuItemClick}
        >
          {collectiblesTabs.length > 1 && (
            <TabList
              isActive
              tabs={collectiblesTabs}
              activeTab={activeCollectiblesTabIndex}
              className={styles.collectiblesTabs}
              overlayClassName={styles.collectiblesTabsOverlay}
              onSwitchTab={handleSwitchCollectiblesTab}
            />
          )}
          <Nfts
            key={activeCollectionKey ?? 'all'}
            isActive
            isWidget
            collection={activeCollection}
            limit={NFTS_LIMIT}
          />
        </OverviewCell>
      )}

      <OverviewCell
        caption={lang('Activity')}
        showAllIcon="showAll"
        showAllLabel={lang('Show All Actions')}
        showAllTestId={getTestId('home_activity_show_all')}
        onShowAllClick={hasActivity ? handleShowAllActivity : undefined}
      >
        <Activities isActive isWidget limit={ACTIVITIES_LIMIT} />
      </OverviewCell>

      <OverviewCell caption={lang('Explore')}>
        <HomeExploreSection />
      </OverviewCell>
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountId = selectCurrentAccountId(global);

      return {
        hasActivity: Boolean(accountId && selectActivityHistoryIds(global, accountId)?.length),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(PortraitWalletOverview),
);
