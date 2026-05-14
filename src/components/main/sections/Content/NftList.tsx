import React, { memo, useEffect, useLayoutEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { setExtraStyles } from '../../../../lib/teact/teact-dom';

import type { ApiNft } from '../../../../api/types';
import type { AppTheme } from '../../../../global/types';
import type { LoadMoreDirection } from '../../../../global/types';

import { requestMeasure, requestMutation } from '../../../../lib/fasterdom/fasterdom';
import { forceMeasure } from '../../../../lib/fasterdom/stricterdom';
import buildClassName from '../../../../util/buildClassName';
import { getDnsExpirationDate } from '../../../../util/dns';
import { REM } from '../../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useInfiniteScroll from '../../../../hooks/useInfiniteScroll';
import useLastCallback from '../../../../hooks/useLastCallback';
import usePrevious from '../../../../hooks/usePrevious';
import useUniqueId from '../../../../hooks/useUniqueId';
import useWindowSize from '../../../../hooks/useWindowSize';

import InfiniteScroll from '../../../ui/InfiniteScroll';
import Spinner from '../../../ui/Spinner';
import Nft from './Nft';
import { OVERVIEW_CELL_BODY_CLASS } from './OverviewCell';

import styles from './Nft.module.scss';

interface OwnProps {
  addresses: string[];
  isActive?: boolean;
  isLoading?: boolean;
  isWidget?: boolean;
  isWidgetStretched?: boolean;
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
  isWidgetStretched,
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
    isActive,
    listSlice: LIST_SLICE,
    withResetOnInactive: isPortrait || isWidget,
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

  // Stretched widget cell spans the full content width — mirror the non-widget landscape grid
  // so the layout matches the full-size NFTs view (4 cols on wide screens, otherwise 3)
  const widgetColumns = isWidgetStretched
    ? (width >= LANDSCAPE_WIDE_BREAKPOINT_PX ? 4 : 3)
    : (addresses.length <= COMPACT_TWO_COLUMNS_MAX ? 2 : 3);
  const nftsPerRow = isWidget
    ? widgetColumns
    : isLandscape
      ? (width >= LANDSCAPE_WIDE_BREAKPOINT_PX ? 4 : 3)
      : 2;

  const scrollContainerSelector = isWidget
    ? `.${OVERVIEW_CELL_BODY_CLASS}`
    : (isLandscape ? '.nfts-container' : '.app-slide-content');

  // Re-center the viewport slice around the current scroll position in a single hop instead
  // of shifting by `LIST_SLICE` per cycle. Equivalent to default `getMore` on slow scroll
  // (target row barely changes) and strictly better on rapid jumps.
  const handleGetMore = useLastCallback((args: { direction: LoadMoreDirection }) => {
    if (!getMore || !addresses.length) return;

    const scrollContainer = containerRef.current?.closest<HTMLDivElement>(scrollContainerSelector);
    if (!scrollContainer) {
      getMore(args);
      return;
    }

    const computedStyle = getComputedStyle(containerRef.current!);
    const cellHeight = parseFloat(computedStyle.getPropertyValue('--cell-height')) || 0;
    const rowGap = parseFloat(computedStyle.getPropertyValue('--row-gap-size')) || 0;
    const rowStride = cellHeight + rowGap;
    if (rowStride <= 0) {
      getMore(args);
      return;
    }

    const containerRect = containerRef.current!.getBoundingClientRect();
    const scrollRect = scrollContainer.getBoundingClientRect();
    const listTopOffset = (containerRect.top - scrollRect.top) + scrollContainer.scrollTop;
    const visibleCenterPx = scrollContainer.scrollTop + scrollContainer.offsetHeight / 2 - listTopOffset;
    const targetRow = Math.max(0, Math.floor(visibleCenterPx / rowStride));
    const targetIndex = Math.max(0, Math.min(addresses.length - 1, targetRow * nftsPerRow));
    getMore({ direction: args.direction, offsetId: addresses[targetIndex] });
  });

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;

    const computeStyles = (el: HTMLElement) => {
      const containerWidth = el.offsetWidth;
      // Cell may be inside a hidden ancestor (e.g., a freshly added collection tab while the user
      // is still viewing another collection) - `width=0` produces invalid styles. Skip until the
      // `ResizeObserver` fires when the cell becomes visible.
      if (containerWidth === 0) return undefined;

      const nftWidth = Math.floor((containerWidth - INNER_PADDING - (nftsPerRow - 1) * COLUMNS_GAP_SIZE) / nftsPerRow);
      const rowHeight = nftWidth + TEXT_DATA_HEIGHT;
      const safeViewportIndex = Math.max(0, viewportIndex);
      const visibleCount = Math.max(0, viewportNftAddresses?.length ?? 0);
      // Size to the rendered window, not the full collection. For wallets with thousands of NFTs,
      // sizing to `addresses.length` produced a multi-thousand-rem scroll-host that wrecked
      // scrollbar precision and Safari smoothness. The height grows as `useInfiniteScroll` loads.
      const rowCount = Math.ceil((safeViewportIndex + visibleCount) / nftsPerRow);
      const gapCount = Math.max(0, rowCount - 1);

      const loadingExtra = !isWidget && isLoading && addresses.length > 0
        ? LOADING_ROW_HEIGHT + ROWS_GAP_SIZE
        : 0;

      return {
        height: `${rowCount * rowHeight + gapCount * ROWS_GAP_SIZE + loadingExtra}px`,
        '--row-gap-size': `${ROWS_GAP_SIZE}px`,
        '--cell-width': `${nftWidth}px`,
        '--cell-height': `${rowHeight}px`,
      };
    };

    // Initial pass: stay synchronous so `InfiniteScroll`'s preload effect (which runs immediately
    // after) sees the final `scrollHeight` and doesn't fire a spurious `loadMoreBackwards` -
    // that would shift viewport off index 0 and leave an empty placeholder for the first NFT
    forceMeasure(() => {
      const el = containerRef.current;
      if (!el) return;

      const styles = computeStyles(el);
      if (styles) setExtraStyles(el, styles);
    });

    // Subsequent passes via `ResizeObserver` run outside fasterdom phases - split measure/mutate
    const observer = new ResizeObserver(() => {
      requestMeasure(() => {
        const el = containerRef.current;
        if (!el) return;

        const styles = computeStyles(el);
        if (!styles) return;

        requestMutation(() => {
          if (!containerRef.current) return;
          setExtraStyles(containerRef.current, styles);
        });
      });
    });

    observer.observe(container);

    return () => observer.disconnect();
  }, [
    addresses.length, isActive, isWidget, isLoading, nftsPerRow,
    viewportIndex, viewportNftAddresses?.length, width,
  ]);

  return (
    <InfiniteScroll
      ref={containerRef}
      withAbsolutePositioning
      className={buildClassName(styles.list, isWidget && styles.listWidget, `nft-list-${uniqueId}`)}
      scrollContainerClosest={scrollContainerSelector}
      items={viewportNftAddresses}
      itemSelector={`.nft-list-${uniqueId} .${styles.item}`}
      preloadBackwards={LIST_SLICE}
      sensitiveArea={SENSITIVE_AREA}
      cacheBuster={width}
      onLoadMore={handleGetMore}
    >
      {viewportNftAddresses?.map((address, index) => {
        const overallIndex = viewportIndex + index;
        const row = Math.floor(overallIndex / nftsPerRow);
        const col = overallIndex % nftsPerRow;

        return (
          <Nft
            key={address}
            nft={nftsByAddresses[address]}
            appTheme={appTheme}
            tonDnsExpiration={getDnsExpirationDate(nftsByAddresses[address], dnsExpiration)}
            isViewAccount={isViewAccount}
            withChainIcon={isMultichainAccount}
            selectedNfts={selectedNfts}
            isWidget={isWidget}
            style={`--row: ${row}; --col: ${col};`}
          />
        );
      })}
      {!isWidget && isLoading && addresses.length > 0 && (
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
