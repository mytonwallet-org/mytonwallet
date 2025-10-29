import { useEffect, useMemo, useState } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { Account } from '../../../../../global/types';

import { areSortedArraysEqual } from '../../../../../util/iteratees';

import useLastCallback from '../../../../../hooks/useLastCallback';

import { ACCOUNT_HEIGHT_PX } from '../AccountsListView';

interface SortState {
  orderedAccountIds: string[];
  dragOrderAccountIds: string[];
  draggedIndex?: number;
}

export function useSortableAccounts(orderedAccounts?: [string, Account][]) {
  const { updateOrderedAccountIds } = getActions();

  const orderedAccountIds = useMemo(() => {
    return (orderedAccounts ?? []).map(([accountId]) => accountId);
  }, [orderedAccounts]);

  const [sortState, setSortState] = useState<SortState>({
    orderedAccountIds,
    dragOrderAccountIds: orderedAccountIds,
    draggedIndex: undefined,
  });

  useEffect(() => {
    if (!areSortedArraysEqual(orderedAccountIds, sortState.orderedAccountIds)) {
      setSortState({
        orderedAccountIds,
        dragOrderAccountIds: orderedAccountIds,
        draggedIndex: undefined,
      });
    }
  }, [orderedAccountIds, sortState.orderedAccountIds]);

  const handleDrag = useLastCallback((translation: { x: number; y: number }, id: string | number) => {
    const base = sortState.orderedAccountIds;
    if (!base?.length) return;
    const index = base.indexOf(id as string);
    if (index < 0) return;

    const delta = Math.round(translation.y / ACCOUNT_HEIGHT_PX);
    const dragOrderAccountIds = base.filter((accountId) => accountId !== id);
    const maxIndex = (base.length || 1) - 1;
    const targetIndex = Math.max(0, Math.min(index + delta, maxIndex));

    dragOrderAccountIds.splice(targetIndex, 0, id as string);
    setSortState((current) => ({
      ...current,
      draggedIndex: index,
      dragOrderAccountIds,
    }));
  });

  const handleDragEnd = useLastCallback(() => {
    const nextOrder = sortState.dragOrderAccountIds;
    if (nextOrder) {
      updateOrderedAccountIds({ orderedAccountIds: nextOrder });
      setSortState((current) => ({
        ...current,
        orderedAccountIds: nextOrder,
        draggedIndex: undefined,
      }));
    }
  });

  return { sortState, handleDrag, handleDragEnd };
}
