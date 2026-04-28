import React, { memo } from '../../../../lib/teact/teact';

import type { ApiNftCollection } from '../../../../api/types';
import { ContentTab } from '../../../../global/types';

import Transition from '../../../ui/Transition';
import Activities from './Activities';
import Assets from './Assets';
import Nfts from './Nfts';

import styles from './Content.module.scss';

interface OwnProps {
  isActive: boolean;
  isPortrait: boolean;
  activeTabIndex: number;
  activeTabId?: ContentTab | number;
  currentCollection?: ApiNftCollection;
  shouldShowSeparateAssetsPanel: boolean;
  totalTokensAmount: number;
  activeNftKey: number;
  onClickAsset: (slug: string) => void;
  onStakedTokenClick: NoneToVoidFunction;
  onScroll?: (e: React.UIEvent<HTMLElement>) => void;
}

function ContentSlide({
  isActive,
  isPortrait,
  activeTabIndex,
  activeTabId,
  currentCollection,
  shouldShowSeparateAssetsPanel,
  totalTokensAmount,
  activeNftKey,
  onClickAsset,
  onStakedTokenClick,
  onScroll,
}: OwnProps) {
  if (currentCollection && activeTabId !== ContentTab.Nft) {
    return (
      <div onScroll={onScroll}>
        <Nfts
          key={`custom:${currentCollection.address}`}
          isActive={isActive}
        />
      </div>
    );
  }

  // When assets are shown separately (in portrait mode), tab slot 0 is empty - fall back to Activity
  // to keep parent's component logic intact
  const effectiveTabId = activeTabIndex === 0 && shouldShowSeparateAssetsPanel && !currentCollection
    ? ContentTab.Activity
    : activeTabId;

  switch (effectiveTabId) {
    case ContentTab.Assets:
      return (
        <Assets
          isActive={isActive}
          onTokenClick={onClickAsset}
          onStakedTokenClick={onStakedTokenClick}
          onScroll={onScroll}
        />
      );
    case ContentTab.Activity:
      return (
        <Activities
          isActive={isActive}
          totalTokensAmount={totalTokensAmount}
          onScroll={onScroll}
        />
      );
    case ContentTab.Nft:
      return (
        <Transition
          activeKey={activeNftKey}
          name={isPortrait ? 'slide' : 'slideFade'}
          className={styles.nftsContainer}
          onScroll={onScroll}
        >
          <Nfts key={currentCollection?.address || 'all'} isActive={isActive} />
        </Transition>
      );
    default:
      return undefined;
  }
}

export default memo(ContentSlide);
