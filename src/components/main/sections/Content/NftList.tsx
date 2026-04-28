import React, { memo, useEffect, useLayoutEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { setExtraStyles } from '../../../../lib/teact/teact-dom';

import type { ApiNft } from '../../../../api/types';
import type { AppTheme } from '../../../../global/types';

import { forceMeasure } from '../../../../lib/fasterdom/stricterdom';
import buildClassName from '../../../../util/buildClassName';
import { getDnsExpirationDate } from '../../../../util/dns';
import { REM } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useInfiniteScroll from '../../../../hooks/useInfiniteScroll';
import usePrevious from '../../../../hooks/usePrevious';
import useUniqueId from '../../../../hooks/useUniqueId';
import useWindowSize from '../../../../hooks/useWindowSize';

import InfiniteScroll from '../../../ui/InfiniteScroll';
import Spinner from '../../../ui/Spinner';
import Nft from './Nft';

import styles from './Nft.module.scss';

interface OwnProps {
  addresses: string[];
  isActive?: boolean;
  isLoading?: boolean;
  isWidget?: boolean;
  appTheme: AppTheme;
  dnsExpiration?: Record<string, number>;
  isViewAccount?: boolean;
  isMultichainAccount?: boolean;
  selectedNfts?: ApiNft[];
  nftsByAddresses: Record<string, ApiNft>;
}

const LIST_SLICE = 60;
const SENSITIVE_AREA = 1200;

const INNER_PADDING = 0.5 * REM;
const COLUMNS_GAP_SIZE = 0.5 * REM;
const ROWS_GAP_SIZE = 0.75 * REM;
const TEXT_DATA_HEIGHT = 2.5 * REM;
const LOADING_ROW_HEIGHT = 3 * REM;
const COMPACT_TWO_COLUMNS_MAX = 4;
// Must match `md` in `src/styles/mixins/_responsive.scss` - keeps `nftsPerRow` in sync
// with the `respond-above(md)` CSS rules
const LANDSCAPE_WIDE_BREAKPOINT_PX = 992;

function NftList({
  addresses,
  isActive,
  isLoading,
  isWidget,
  appTheme,
  dnsExpiration,
  isViewAccount,
  isMultichainAccount,
  selectedNfts,
  nftsByAddresses,
}: OwnProps) {
  const containerRef = useRef<HTMLDivElement>();
  const { isPortrait, isLandscape } = useDeviceScreen();
  const { width } = useWindowSize(); // Handle window resize to fix cell size

  const uniqueId = useUniqueId();

  const [viewportNftAddresses, getMore] = useInfiniteScroll({
    listIds: addresses,
    isActive: isActive && !isWidget,
    listSlice: LIST_SLICE,
    withResetOnInactive: isPortrait,
  });

  // Reset scroll position when tab becomes active after viewport was reset (portrait only)
  const prevIsActive = usePrevious(isActive);
  useEffect(() => {
    if (isWidget) return;
    if (isPortrait && isActive && prevIsActive === false && containerRef.current) {
      const scrollContainer = containerRef.current.closest<HTMLElement>('.app-slide-content');
      if (scrollContainer) {
        scrollContainer.scrollTop = 0;
      }
    }
  }, [isActive, isWidget, isPortrait, prevIsActive]);

  // Map address→index to avoid O(n) indexOf on every viewport update; lookup is O(1).
  const addressToIndexMap = useMemo(() => {
    const map = new Map<string, number>();
    addresses.forEach((address, index) => map.set(address, index));
    return map;
  }, [addresses]);

  const viewportIndex = useMemo(() => {
    if (!viewportNftAddresses?.length) return 0;
    return addressToIndexMap.get(viewportNftAddresses[0]) ?? 0;
  }, [addressToIndexMap, viewportNftAddresses]);

  const nftsPerRow = isLandscape
    ? (width >= LANDSCAPE_WIDE_BREAKPOINT_PX ? 4 : 3)
    : 2;
  const emptyCellsCount = viewportIndex % nftsPerRow;

  useLayoutEffect(() => {
    if (isWidget) return;

    forceMeasure(() => {
      const container = containerRef.current;
      if (!container || container.closest('.Transition_slide-inactive')) return;

      const containerWidth = container.offsetWidth;
      const nftWidth = Math.floor((containerWidth - INNER_PADDING - (nftsPerRow - 1) * COLUMNS_GAP_SIZE) / nftsPerRow);
      const rowHeight = nftWidth + TEXT_DATA_HEIGHT;
      const safeViewportIndex = Math.max(0, viewportIndex);
      const visibleCount = Math.max(0, viewportNftAddresses?.length ?? 0);
      const rowCount = Math.ceil((safeViewportIndex + visibleCount) / nftsPerRow);
      const gapCount = Math.max(0, rowCount - 1);

      if (!containerRef.current) return;

      const loadingExtra = isLoading && addresses.length > 0 ? LOADING_ROW_HEIGHT + ROWS_GAP_SIZE : 0;

      setExtraStyles(containerRef.current, {
        height: `${rowCount * rowHeight + gapCount * ROWS_GAP_SIZE + loadingExtra}px`,
        '--row-gap-size': `${ROWS_GAP_SIZE}px`,
        '--cell-width': `${nftWidth}px`,
        '--cell-height': `${rowHeight}px`,
      });
    });
  }, [
    addresses.length, isActive, isWidget, isLoading, nftsPerRow,
    viewportIndex, viewportNftAddresses?.length, width,
  ]);

  if (isWidget) {
    const columns = addresses.length <= COMPACT_TWO_COLUMNS_MAX ? 2 : 3;

    return (
      <div className={styles.listCompact} style={`--columns: ${columns}`}>
        {addresses.map((address) => (
          <Nft
            key={address}
            nft={nftsByAddresses[address]}
            appTheme={appTheme}
            tonDnsExpiration={getDnsExpirationDate(nftsByAddresses[address], dnsExpiration)}
            isViewAccount={isViewAccount}
            withChainIcon={isMultichainAccount}
            selectedNfts={selectedNfts}
            isWidget
          />
        ))}
      </div>
    );
  }

  // Empty cells for grid alignment via CSS `nth-child()`
  const emptyCells = Array.from({ length: emptyCellsCount });

  return (
    <InfiniteScroll
      ref={containerRef}
      withAbsolutePositioning
      className={buildClassName(styles.list, `nft-list-${uniqueId}`)}
      scrollContainerClosest={isLandscape ? '.nfts-container' : '.app-slide-content'}
      items={viewportNftAddresses}
      // For correct scrolling, the first element in the row must be selected via this prop
      itemSelector={`.nft-list-${uniqueId} .${styles.item}:nth-child(${nftsPerRow}n + 1)`}
      preloadBackwards={LIST_SLICE}
      sensitiveArea={SENSITIVE_AREA}
      cacheBuster={width}
      onLoadMore={getMore}
    >
      {emptyCells.map((_, index) => (
        <div
          key={`empty-${index}`}
          className={styles.item}
          style={`--row: ${Math.floor((viewportIndex - emptyCellsCount + index) / nftsPerRow)};`}
        />
      ))}
      {viewportNftAddresses?.map((address, index) => (
        <Nft
          key={address}
          nft={nftsByAddresses[address]}
          appTheme={appTheme}
          tonDnsExpiration={getDnsExpirationDate(nftsByAddresses[address], dnsExpiration)}
          isViewAccount={isViewAccount}
          withChainIcon={isMultichainAccount}
          selectedNfts={selectedNfts}
          style={`--row: ${Math.floor((viewportIndex + index) / nftsPerRow)};`}
        />
      ))}
      {isLoading && addresses.length > 0 && (
        <div
          key="nft-loading"
          className={styles.loadingWrapper}
          style={`--row: ${Math.ceil(
            (viewportIndex + (viewportNftAddresses?.length ?? 0)) / nftsPerRow,
          )};`}
        >
          <Spinner />
        </div>
      )}
    </InfiniteScroll>
  );
}

export default memo(NftList);
