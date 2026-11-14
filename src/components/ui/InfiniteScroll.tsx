import type { UIEvent } from 'react';
import type { ElementRef, FC, TeactNode } from '../../lib/teact/teact';
import React, {
  useEffect, useLayoutEffect, useMemo, useRef,
} from '../../lib/teact/teact';

import { LoadMoreDirection } from '../../global/types';

import { requestForcedReflow } from '../../lib/fasterdom/fasterdom';
import buildStyle from '../../util/buildStyle';
import { SECOND } from '../../util/dateFormat';
import resetScroll from '../../util/resetScroll';
import { debounce } from '../../util/schedulers';

import useLastCallback from '../../hooks/useLastCallback';
import useLayoutEffectWithPrevDeps from '../../hooks/useLayoutEffectWithPrevDeps';

type OwnProps = {
  ref?: ElementRef<HTMLDivElement>;
  style?: string;
  className?: string;
  items?: any[];
  itemSelector?: string;
  loadMoreStrategy?: 'anchorMovement' | 'scrollDirection';
  preloadBackwards?: number;
  sensitiveArea?: number;
  /** Tells whether the list is close enough to the top of its items to load more there, in place of `sensitiveArea` */
  getIsNearTop?: (scrollContainer: HTMLDivElement) => boolean;
  withAbsolutePositioning?: boolean;
  /* A CSS value */
  maxHeight?: string;
  noScrollRestore?: boolean;
  noScrollRestoreOnTop?: boolean;
  /**
   * The scroll restore keeps the first item in sight where it stood, so that items changing below it move nothing on
   * screen, rather than the item at the edge the list last scrolled to
   */
  shouldRestoreByShownItem?: boolean;
  noFastList?: boolean;
  cacheBuster?: any;
  beforeChildren?: TeactNode;
  scrollContainerClosest?: string;
  children: TeactNode;
  onLoadMore?: ({ direction }: { direction: LoadMoreDirection }) => void;
  onScroll?: (e: UIEvent<HTMLDivElement>) => void;
  onWheel?: (e: React.WheelEvent<HTMLDivElement>) => void;
  onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
  onKeyDown?: (e: React.KeyboardEvent<any>) => void;
  onDragOver?: (e: React.DragEvent<HTMLDivElement>) => void;
  onDragLeave?: (e: React.DragEvent<HTMLDivElement>) => void;
};

const DEFAULT_LIST_SELECTOR = '.ListItem';
const DEFAULT_PRELOAD_BACKWARDS = 20;
const DEFAULT_SENSITIVE_AREA = 800;
const SCROLL_GESTURE_END_DELAY = 150;

type ScrollDirection = 'up' | 'down';

const InfiniteScroll: FC<OwnProps> = ({
  ref,
  style,
  className,
  items,
  itemSelector = DEFAULT_LIST_SELECTOR,
  loadMoreStrategy = 'anchorMovement',
  preloadBackwards = DEFAULT_PRELOAD_BACKWARDS,
  sensitiveArea = DEFAULT_SENSITIVE_AREA,
  getIsNearTop,
  withAbsolutePositioning,
  maxHeight,
  // Used to turn off restoring scroll position (e.g. for frequently re-ordered chat or user lists)
  noScrollRestore = false,
  noScrollRestoreOnTop = false,
  shouldRestoreByShownItem = false,
  noFastList,
  // Used to re-query `listItemElements` if rendering is delayed by transition
  cacheBuster,
  beforeChildren,
  scrollContainerClosest,
  children,
  onLoadMore,
  onScroll,
  onWheel,
  onClick,
  onKeyDown,
  onDragOver,
  onDragLeave,
}: OwnProps) => {
  let containerRef = useRef<HTMLDivElement>();
  if (ref) {
    containerRef = ref;
  }

  const stateRef = useRef<{
    listItemElements?: NodeListOf<HTMLDivElement>;
    isScrollTopJustUpdated?: boolean;
    currentAnchor?: HTMLDivElement | undefined;
    currentAnchorTop?: number;
    /** The scroll `currentAnchorTop` was measured at */
    currentAnchorScrollTop?: number;
    /** The first item in sight, with `shouldRestoreByShownItem` */
    shownItem?: HTMLDivElement;
    /** Where `shownItem` stands in the scrolled content, which a scroll leaves as it is */
    shownItemOffset?: number;
    lastScrollTop?: number;
    wheelDirection?: ScrollDirection;
    wheelDirectionResetTimer?: ReturnType<typeof setTimeout>;
  }>({});
  const shouldTrackScrollDirection = loadMoreStrategy === 'scrollDirection';

  const [loadMoreBackwards, loadMoreForwards] = useMemo(() => {
    if (!onLoadMore) {
      return [];
    }

    const debounceMs = withAbsolutePositioning ? 100 : SECOND;

    return [
      debounce(() => {
        onLoadMore({ direction: LoadMoreDirection.Backwards });
      }, debounceMs, true, false),
      debounce(() => {
        onLoadMore({ direction: LoadMoreDirection.Forwards });
      }, debounceMs, true, false),
    ];
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [onLoadMore, items]);

  // Initial preload
  useEffect(() => {
    if (!loadMoreBackwards) {
      return;
    }

    if (preloadBackwards > 0 && (!items || items.length < preloadBackwards)) {
      loadMoreBackwards();
      return;
    }

    const scrollContainer = scrollContainerClosest
      ? containerRef.current!.closest<HTMLDivElement>(scrollContainerClosest)!
      : containerRef.current!;

    const { scrollHeight, clientHeight } = scrollContainer;
    if (clientHeight && scrollHeight <= clientHeight) {
      loadMoreBackwards();
    }
  }, [items, loadMoreBackwards, preloadBackwards, scrollContainerClosest]);

  // When using absolute positioning, after items change check if the scroll viewport doesn't overlap with
  // the rendered area. This happens when the user fast-scrolls — the viewport shifts once via the scroll handler
  // but no more scroll events fire because `scrollTop` doesn't change, leaving the screen blank.
  // We call `onLoadMore` directly (bypassing `debounce`) so the viewport catches up within a few render cycles.
  useEffect(() => {
    if (!withAbsolutePositioning || !onLoadMore) return;

    const scrollContainer = scrollContainerClosest
      ? containerRef.current?.closest<HTMLDivElement>(scrollContainerClosest)
      : containerRef.current;
    if (!scrollContainer) return;

    const listItemElements = scrollContainer.querySelectorAll<HTMLDivElement>(itemSelector);
    if (!listItemElements.length) return;

    const firstItemTop = getScrollSpaceTop(listItemElements[0], scrollContainer);
    const lastItem = listItemElements[listItemElements.length - 1];
    const lastItemBottom = getScrollSpaceTop(lastItem, scrollContainer) + lastItem.offsetHeight;
    const { scrollTop, offsetHeight } = scrollContainer;
    const scrollBottom = scrollTop + offsetHeight;

    if (scrollBottom < firstItemTop) {
      onLoadMore({ direction: LoadMoreDirection.Forwards });
    } else if (scrollTop > lastItemBottom) {
      onLoadMore({ direction: LoadMoreDirection.Backwards });
    }
  }, [items, withAbsolutePositioning, onLoadMore, scrollContainerClosest, itemSelector, cacheBuster]);

  // Restore `scrollTop` after adding items
  useLayoutEffectWithPrevDeps(([prevItems]) => {
    const scrollContainer = scrollContainerClosest
      ? containerRef.current!.closest<HTMLDivElement>(scrollContainerClosest)!
      : containerRef.current!;
    const state = stateRef.current;

    const listItemElements = scrollContainer.querySelectorAll<HTMLDivElement>(itemSelector);
    state.listItemElements = listItemElements;

    if (!prevItems?.length) return;

    requestForcedReflow(() => {
      let newScrollTop: number | undefined;
      let newAnchorTop: number | undefined;
      const items = Array.from(listItemElements);

      if (state.currentAnchor && items.includes(state.currentAnchor)) {
        const { scrollTop } = scrollContainer;
        newAnchorTop = state.currentAnchor.getBoundingClientRect().top;
        // A scroll since the anchor was measured, one whose event has not come yet or one a shorter list forced,
        // moves the anchor on screen by the distance scrolled. The rest of its shift comes from the change, which the
        // restore undoes.
        const scrolledDistance = scrollTop - state.currentAnchorScrollTop!;
        newScrollTop = scrollTop + (newAnchorTop - (state.currentAnchorTop! - scrolledDistance));
      } else {
        const nextAnchor = listItemElements[0];
        if (nextAnchor) {
          state.currentAnchor = nextAnchor;
          state.currentAnchorTop = nextAnchor.getBoundingClientRect().top;
          state.currentAnchorScrollTop = scrollContainer.scrollTop;
        }
      }

      const { shownItem } = state;
      if (shouldRestoreByShownItem && shownItem && items.includes(shownItem)) {
        const shownItemOffset = getScrollSpaceTop(shownItem, scrollContainer);
        newScrollTop = scrollContainer.scrollTop + (shownItemOffset - state.shownItemOffset!);
        state.shownItemOffset = shownItemOffset;
      }

      if (withAbsolutePositioning || noScrollRestore) {
        // The next restore keeps in place the item in sight now, wherever the items changed meanwhile have moved it
        if (shouldRestoreByShownItem) rememberShownItem(scrollContainer);
        return undefined;
      }

      const { scrollTop } = scrollContainer;
      if (noScrollRestoreOnTop && scrollTop === 0) {
        return undefined;
      }

      return () => {
        resetScroll(scrollContainer, newScrollTop, shouldTrackScrollDirection);

        if (newScrollTop !== undefined && newAnchorTop !== undefined) {
          // The scroll event of this restore is skipped, so the anchor is placed here
          state.currentAnchorTop = newAnchorTop - (newScrollTop - scrollTop);
          state.currentAnchorScrollTop = newScrollTop;
        }
        if (shouldTrackScrollDirection && newScrollTop !== undefined) state.lastScrollTop = newScrollTop;
        state.isScrollTopJustUpdated = true;
      };
    });
  }, [
    items, itemSelector, noScrollRestore, noScrollRestoreOnTop, cacheBuster, withAbsolutePositioning,
    scrollContainerClosest, shouldTrackScrollDirection, shouldRestoreByShownItem,
  ]);

  const rememberShownItem = useLastCallback((scrollContainer: HTMLDivElement) => {
    const state = stateRef.current;
    const shownItem = state.listItemElements && findFirstShownItem(state.listItemElements, scrollContainer);
    state.shownItem = shownItem;
    state.shownItemOffset = shownItem && getScrollSpaceTop(shownItem, scrollContainer);
  });

  const handleScroll = useLastCallback((e: UIEvent<HTMLDivElement>) => {
    if (shouldRestoreByShownItem) {
      rememberShownItem(scrollContainerClosest
        ? containerRef.current!.closest<HTMLDivElement>(scrollContainerClosest)!
        : containerRef.current!);
    }

    if (loadMoreForwards && loadMoreBackwards) {
      const state = stateRef.current;
      const {
        isScrollTopJustUpdated, currentAnchor, currentAnchorTop,
      } = state;
      const listItemElements = state.listItemElements!;
      const listLength = listItemElements.length;
      const scrollContainer = scrollContainerClosest
        ? containerRef.current!.closest<HTMLDivElement>(scrollContainerClosest)!
        : containerRef.current!;
      const { scrollTop, scrollHeight, offsetHeight } = scrollContainer;
      const previousScrollTop = state.lastScrollTop;
      if (shouldTrackScrollDirection) state.lastScrollTop = scrollTop;

      if (isScrollTopJustUpdated) {
        state.isScrollTopJustUpdated = false;
        if (shouldTrackScrollDirection) onScroll?.(e);
        return;
      }

      const wheelDirection = shouldTrackScrollDirection ? state.wheelDirection : undefined;
      if (wheelDirection) {
        clearTimeout(state.wheelDirectionResetTimer);
        state.wheelDirectionResetTimer = setTimeout(() => {
          state.wheelDirection = undefined;
          state.wheelDirectionResetTimer = undefined;
        }, SCROLL_GESTURE_END_DELAY);
      }

      const isMovingUp = wheelDirection
        ? wheelDirection === 'up'
        : previousScrollTop !== undefined && scrollTop < previousScrollTop;
      const isMovingDown = wheelDirection
        ? wheelDirection === 'down'
        : previousScrollTop !== undefined && scrollTop > previousScrollTop;

      let top = 0;
      let bottom = scrollHeight;

      if (listLength) {
        const lastItemEl = listItemElements[listLength - 1];

        if (scrollContainerClosest) {
          // `offsetTop` is relative to the nearest positioned ancestor, not the scroll container,
          // so we fall back to `getBoundingClientRect` when the scroll container is an outer element
          const scrollContainerTop = scrollContainer.getBoundingClientRect().top;
          top = listItemElements[0].getBoundingClientRect().top - scrollContainerTop + scrollTop;
          bottom = lastItemEl.getBoundingClientRect().top - scrollContainerTop + scrollTop + lastItemEl.offsetHeight;
        } else {
          top = listItemElements[0].offsetTop;
          bottom = lastItemEl.offsetTop + lastItemEl.offsetHeight;
        }
      }

      const isNearTop = getIsNearTop ? getIsNearTop(scrollContainer) : scrollTop <= top + sensitiveArea;
      const isNearBottom = bottom - (scrollTop + offsetHeight) <= sensitiveArea;
      let isUpdated = false;

      if (isNearTop) {
        const nextAnchor = listItemElements[0];
        if (nextAnchor) {
          const nextAnchorTop = nextAnchor.getBoundingClientRect().top;
          const observedAnchorTop = currentAnchor?.offsetParent && currentAnchor !== nextAnchor
            ? currentAnchor.getBoundingClientRect().top
            : nextAnchorTop;
          const shouldLoadMore = shouldTrackScrollDirection
            ? isMovingUp
            : Boolean(currentAnchor && currentAnchorTop !== undefined && observedAnchorTop > currentAnchorTop);
          if (shouldLoadMore) {
            state.currentAnchor = nextAnchor;
            state.currentAnchorTop = nextAnchorTop;
            state.currentAnchorScrollTop = scrollTop;
            isUpdated = true;
            loadMoreForwards();
          }
        }
      }

      if (isNearBottom) {
        const nextAnchor = listItemElements[listLength - 1];
        if (nextAnchor) {
          const nextAnchorTop = nextAnchor.getBoundingClientRect().top;
          const observedAnchorTop = currentAnchor?.offsetParent && currentAnchor !== nextAnchor
            ? currentAnchor.getBoundingClientRect().top
            : nextAnchorTop;
          const shouldLoadMore = shouldTrackScrollDirection
            ? isMovingDown
            : Boolean(currentAnchor && currentAnchorTop !== undefined && observedAnchorTop < currentAnchorTop);
          if (shouldLoadMore) {
            state.currentAnchor = nextAnchor;
            state.currentAnchorTop = nextAnchorTop;
            state.currentAnchorScrollTop = scrollTop;
            isUpdated = true;
            loadMoreBackwards();
          }
        }
      }

      if (!isUpdated) {
        if (currentAnchor?.offsetParent) {
          state.currentAnchorTop = currentAnchor.getBoundingClientRect().top;
          state.currentAnchorScrollTop = scrollTop;
        } else {
          const nextAnchor = listItemElements[0];

          if (nextAnchor) {
            state.currentAnchor = nextAnchor;
            state.currentAnchorTop = nextAnchor.getBoundingClientRect().top;
            state.currentAnchorScrollTop = scrollTop;
          }
        }
      }
    }

    if (onScroll) {
      onScroll(e);
    }
  });

  const handleWheel = useLastCallback((e: React.WheelEvent<HTMLDivElement>) => {
    if (shouldTrackScrollDirection && e.deltaY) {
      const state = stateRef.current;
      state.wheelDirection = e.deltaY < 0 ? 'up' : 'down';
      clearTimeout(state.wheelDirectionResetTimer);
      state.wheelDirectionResetTimer = setTimeout(() => {
        state.wheelDirection = undefined;
        state.wheelDirectionResetTimer = undefined;
      }, SCROLL_GESTURE_END_DELAY);
    }

    onWheel?.(e);
  });

  useEffect(() => () => {
    clearTimeout(stateRef.current.wheelDirectionResetTimer);
  }, []);

  useLayoutEffect(() => {
    if (!scrollContainerClosest) return undefined;

    const closestScrollContainer = containerRef.current!.closest<HTMLDivElement>(scrollContainerClosest);
    if (!closestScrollContainer) return undefined;

    const handleNativeScroll = (e: Event) => handleScroll(e as unknown as UIEvent<HTMLDivElement>);

    closestScrollContainer.addEventListener('scroll', handleNativeScroll);

    return () => {
      closestScrollContainer.removeEventListener('scroll', handleNativeScroll);
    };
  }, [handleScroll, scrollContainerClosest]);

  return (
    <div
      ref={containerRef}
      className={className}
      onScroll={handleScroll}
      onWheel={handleWheel}
      teactFastList={!noFastList && !withAbsolutePositioning}
      onKeyDown={onKeyDown}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onClick={onClick}
      style={style}
    >
      {beforeChildren}
      {withAbsolutePositioning && items?.length ? (
        <div
          teactFastList={!noFastList}
          style={buildStyle('position: relative', maxHeight !== undefined && `height: ${maxHeight}`)}
        >
          {children}
        </div>
      ) : children}
    </div>
  );
};

export default InfiniteScroll;

/**
 * Returns the element's top position in the scroll container's scroll space, in pixels.
 *
 * `HTMLElement.offsetTop` is measured from the nearest positioned ancestor, which is not always the scroll container
 * (for example, when using `scrollContainerClosest` with a wrapper that contains the InfiniteScroll as a descendant).
 * Using `getBoundingClientRect` makes the math coordinate-system-independent and matches `scrollContainer.scrollTop`.
 */
function getScrollSpaceTop(element: HTMLElement, scrollContainer: HTMLElement) {
  return element.getBoundingClientRect().top - scrollContainer.getBoundingClientRect().top + scrollContainer.scrollTop;
}

/** The first of the items, which stand in order down the list, that reaches below the container's top, or the last */
function findFirstShownItem(items: NodeListOf<HTMLDivElement>, scrollContainer: HTMLElement) {
  if (!items.length) return undefined;

  const { top } = scrollContainer.getBoundingClientRect();
  let low = 0;
  let high = items.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (items[middle].getBoundingClientRect().bottom > top) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }

  return items[low];
}
