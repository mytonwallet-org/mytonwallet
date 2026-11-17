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
  activeTabId?: ContentTab | number;
  currentCollection?: ApiNftCollection;
  activeNftKey: number;
  scrollContainerSelector?: string;
  onClickAsset: (slug: string) => void;
  onStakedTokenClick: NoneToVoidFunction;
  onScroll?: (e: React.UIEvent<HTMLElement>) => void;
}

function ContentSlide({
  isActive,
  isPortrait,
  activeTabId,
  currentCollection,
  activeNftKey,
  scrollContainerSelector,
  onClickAsset,
  onStakedTokenClick,
  onScroll,
}: OwnProps) {
  if (currentCollection && activeTabId !== ContentTab.Nft) {
    return (
      <Transition
        activeKey={activeNftKey}
        name={isPortrait ? 'slide' : 'slideFade'}
        className={styles.nftsContainer}
        onScroll={onScroll}
      >
        <Nfts
          key={`custom:${currentCollection.address}`}
          isActive={isActive}
          collection={currentCollection}
          scrollContainerSelector={scrollContainerSelector}
        />
      </Transition>
    );
  }

  switch (activeTabId) {
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
          scrollContainerSelector={scrollContainerSelector}
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
          <Nfts
            key={currentCollection?.address || 'all'}
            isActive={isActive}
            collection={currentCollection}
            scrollContainerSelector={scrollContainerSelector}
          />
        </Transition>
      );
    default:
      return undefined;
  }
}

export default memo(ContentSlide);
