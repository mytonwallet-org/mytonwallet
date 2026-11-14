import { LoadMoreDirection } from '../../../../global/types';

import { getViewportSlice } from '../../../../hooks/useInfiniteScroll';

import { findListItemIdAtOffset } from './Activities';

const ROW_HEIGHT = 4; // rem
const LIST_SLICE = 30;

describe('findListItemIdAtOffset', () => {
  const listItemIds = Array.from({ length: 200 }, (_, index) => String(index));
  const itemPositionById = Object.fromEntries(listItemIds.map((itemId, index) => (
    [itemId, { top: index * ROW_HEIGHT, height: ROW_HEIGHT }]
  )));

  it('keeps a tall screen far down the list inside the next slice', () => {
    const screenTop = 100 * ROW_HEIGHT;
    const screenHeight = 70; // rem
    const anchorId = findListItemIdAtOffset(listItemIds, itemPositionById, screenTop + screenHeight / 2);

    const { newViewportIds } = getViewportSlice(listItemIds, LoadMoreDirection.Backwards, LIST_SLICE, anchorId);

    expect(newViewportIds).toContain(findListItemIdAtOffset(listItemIds, itemPositionById, screenTop));
    expect(newViewportIds).toContain(findListItemIdAtOffset(listItemIds, itemPositionById, screenTop + screenHeight));
  });

  it('returns the row that covers the offset', () => {
    expect(findListItemIdAtOffset(listItemIds, itemPositionById, 5 * ROW_HEIGHT)).toBe('5');
    expect(findListItemIdAtOffset(listItemIds, itemPositionById, 5 * ROW_HEIGHT + 1)).toBe('5');
  });

  it('clamps offsets outside the list to its first and last rows', () => {
    expect(findListItemIdAtOffset(listItemIds, itemPositionById, -10)).toBe('0');
    expect(findListItemIdAtOffset(listItemIds, itemPositionById, 1000 * ROW_HEIGHT)).toBe('199');
  });
});
