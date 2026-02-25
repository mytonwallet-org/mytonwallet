import { useRef } from '../lib/teact/teact';

import { LoadMoreDirection } from '../global/types';

import { areSortedArraysEqual } from '../util/iteratees';
import useForceUpdate from './useForceUpdate';
import useLastCallback from './useLastCallback';
import usePrevious from './usePrevious';
import usePrevious2 from './usePrevious2';
import useSyncEffect from './useSyncEffect';

type GetMore = (args: { direction: LoadMoreDirection }) => void;
type ResetScroll = () => void;
type LoadMoreBackwards = (args: { offsetId?: string | number }) => void;

const DEFAULT_LIST_SLICE = 30;

const useInfiniteScroll = <ListId extends string | number>({
  loadMoreBackwards,
  listIds,
  isDisabled = false,
  listSlice = DEFAULT_LIST_SLICE,
  slug,
  isActive,
  withResetOnInactive = false,
}: {
  loadMoreBackwards?: LoadMoreBackwards;
  listIds?: ListId[];
  isDisabled?: boolean;
  listSlice?: number;
  slug?: string;
  isActive?: boolean;
  withResetOnInactive?: boolean;
}): [ListId[]?, GetMore?, ResetScroll?] => {
  const currentStateRef = useRef<{ viewportIds: ListId[]; isOnTop: boolean } | undefined>();
  if (!currentStateRef.current && listIds && !isDisabled) {
    const {
      newViewportIds,
      newIsOnTop,
    } = getViewportSlice(listIds, LoadMoreDirection.Forwards, listSlice, listIds[0]);
    currentStateRef.current = { viewportIds: newViewportIds, isOnTop: newIsOnTop };
  }

  const forceUpdate = useForceUpdate();

  const prevSlug = usePrevious2(slug);

  const resetScroll: ResetScroll = useLastCallback(() => {
    if (!listIds?.length) return;

    const {
      newViewportIds,
      newIsOnTop,
    } = getViewportSlice(listIds, LoadMoreDirection.Forwards, listSlice, listIds[0]);

    currentStateRef.current = { viewportIds: newViewportIds, isOnTop: newIsOnTop };
  });

  useSyncEffect(() => {
    if (slug !== prevSlug || (withResetOnInactive && !isActive)) {
      resetScroll();
    }
  }, [isActive, prevSlug, slug, withResetOnInactive]);

  const prevListIds = usePrevious(listIds);
  const prevIsDisabled = usePrevious(isDisabled);
  if (listIds && !isDisabled && (listIds !== prevListIds || isDisabled !== prevIsDisabled)) {
    const { viewportIds: oldViewportIds, isOnTop: oldIsOnTop } = currentStateRef.current ?? {};
    const { newViewportIds, newIsOnTop } = getViewportSliceAfterListChange(
      listIds,
      oldViewportIds,
      oldIsOnTop,
      listSlice,
    );

    if (!oldViewportIds || !areSortedArraysEqual(oldViewportIds, newViewportIds)) {
      currentStateRef.current = { viewportIds: newViewportIds, isOnTop: newIsOnTop };
    }
  } else if (!listIds) {
    currentStateRef.current = undefined;
  }

  const getMore: GetMore = useLastCallback(({
    direction,
  }: { direction: LoadMoreDirection; noScroll?: boolean }) => {
    if (!isActive) return;

    const { viewportIds } = currentStateRef.current || {};

    const offsetId = viewportIds
      ? direction === LoadMoreDirection.Backwards ? viewportIds[viewportIds.length - 1] : viewportIds[0]
      : undefined;

    if (!listIds) {
      if (loadMoreBackwards) {
        loadMoreBackwards({ offsetId });
      }

      return;
    }

    const {
      newViewportIds, areSomeLocal, areAllLocal, newIsOnTop,
    } = getViewportSlice(listIds, direction, listSlice, offsetId);

    if (areSomeLocal && !(viewportIds && areSortedArraysEqual(viewportIds, newViewportIds))) {
      currentStateRef.current = { viewportIds: newViewportIds, isOnTop: newIsOnTop };
      forceUpdate();
    }

    if (!areAllLocal && loadMoreBackwards) {
      loadMoreBackwards({ offsetId });
    }
  });

  return isDisabled ? [listIds] : [currentStateRef.current?.viewportIds, getMore, resetScroll];
};

function getViewportSlice<ListId extends string | number>(
  sourceIds: ListId[],
  direction: LoadMoreDirection,
  listSlice: number,
  offsetId?: ListId,
) {
  const { length } = sourceIds;
  const index = (offsetId !== undefined) ? sourceIds.indexOf(offsetId) : 0;
  const isForwards = direction === LoadMoreDirection.Forwards;
  const indexForDirection = isForwards ? index : (index + 1) || length;
  const from = Math.max(0, indexForDirection - listSlice);
  const to = indexForDirection + listSlice - 1;
  const newViewportIds = sourceIds.slice(Math.max(0, from), to + 1);

  let areSomeLocal;
  let areAllLocal;
  switch (direction) {
    case LoadMoreDirection.Forwards:
      areSomeLocal = indexForDirection >= 0;
      areAllLocal = from >= 0;
      break;
    case LoadMoreDirection.Backwards:
      areSomeLocal = indexForDirection < length;
      areAllLocal = to <= length - 1;
      break;
  }

  return {
    newViewportIds,
    areSomeLocal,
    areAllLocal,
    newIsOnTop: newViewportIds[0] === sourceIds[0],
  };
}

function getViewportSliceAfterListChange<ListId extends string | number>(
  newListIds: ListId[],
  oldViewportIds: ListId[] | undefined,
  oldIsOnTop: boolean | undefined,
  sliceLength: number,
) {
  if (oldIsOnTop) {
    // When the offsetId is on the top, the viewport slice must include at least as many items as it already has.
    // Otherwise, the ids, that the user is seeing, can disappear (that causes the list to scroll higher instantly).
    // Subtracting 1 prevents getViewportSlice from expanding the viewport slice 1 item with each newListIds change.
    sliceLength = Math.max(sliceLength, (oldViewportIds?.length ?? 0) - 1);
    return getViewportSlice(newListIds, LoadMoreDirection.Backwards, sliceLength, newListIds[0]);
  }

  let offsetId = oldViewportIds?.[Math.round(oldViewportIds.length / 2)];
  if (offsetId !== undefined && !newListIds.includes(offsetId)) offsetId = newListIds[0];
  // The direction must be Forwards for getViewportSlice to keep the offsetId at the newViewportIds middle. Otherwise,
  // the viewport slice will "walk" 1 item backward with each newListIds change.
  return getViewportSlice(newListIds, LoadMoreDirection.Forwards, sliceLength, offsetId);
}

export default useInfiniteScroll;
