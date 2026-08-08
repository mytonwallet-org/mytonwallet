import { useEffect, useState } from '../lib/teact/teact';

import { areSortedArraysEqual } from '../util/iteratees';
import { clamp } from '../util/math';
import useLastCallback from './useLastCallback';

export interface SortState<T extends string> {
  orderedIds: T[];
  dragOrderIds: T[];
  draggedIndex?: number;
}

/**
 * Tracks the drag order of a vertical list of equally tall rows dragged with `Draggable`.
 *
 * The order is kept in local state while the user drags. When the parent passes an `orderedIds` with different
 * contents - a new order was committed elsewhere - the local state resets to it. The contents are compared, not
 * the array reference, so re-passing the same ids in a new array is safe.
 */
export default function useSortableList<T extends string>(
  orderedIds: T[],
  itemHeightPx: number,
  onOrderChange: (orderedIds: T[]) => void,
) {
  const [sortState, setSortState] = useState<SortState<T>>({ orderedIds, dragOrderIds: orderedIds });

  useEffect(() => {
    if (!areSortedArraysEqual(orderedIds, sortState.orderedIds)) {
      setSortState({ orderedIds, dragOrderIds: orderedIds, draggedIndex: undefined });
    }
  }, [orderedIds, sortState.orderedIds]);

  const handleDrag = useLastCallback((translation: { x: number; y: number }, id: string | number) => {
    const baseOrder = sortState.orderedIds;
    const index = baseOrder.indexOf(id as T);
    if (index < 0) return;

    const targetIndex = clamp(index + Math.round(translation.y / itemHeightPx), 0, baseOrder.length - 1);
    const dragOrderIds = baseOrder.filter((itemId) => itemId !== id);
    dragOrderIds.splice(targetIndex, 0, id as T);

    setSortState((current) => ({ ...current, draggedIndex: index, dragOrderIds }));
  });

  const handleDragEnd = useLastCallback(() => {
    const nextOrder = sortState.dragOrderIds;

    onOrderChange(nextOrder);
    setSortState((current) => ({ ...current, orderedIds: nextOrder, draggedIndex: undefined }));
  });

  return { sortState, handleDrag, handleDragEnd };
}
