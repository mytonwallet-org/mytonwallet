import type { NavigationTab } from '../global/types';
import type { NavigationTabDrag } from './navigationTabOrder';

import {
  DEFAULT_NAVIGATION_TAB_ORDER,
  dragNavigationTab,
  getNavigationTabShift,
  moveNavigationTab,
  resolveNavigationTabOrder,
} from './navigationTabOrder';

describe('resolveNavigationTabOrder', () => {
  it('keeps the stored order, drops unknown and repeated tabs and appends the missing ones', () => {
    const stored = ['agent', 'portfolio', 'wallet', 'agent'] as NavigationTab[];

    expect(resolveNavigationTabOrder(stored)).toEqual(['agent', 'wallet', 'market', 'explore', 'settings']);
  });

  it('falls back to the default order', () => {
    expect(resolveNavigationTabOrder(undefined)).toEqual(DEFAULT_NAVIGATION_TAB_ORDER);
  });
});

describe('moveNavigationTab', () => {
  it('moves a tab in both directions without changing the source', () => {
    const order = DEFAULT_NAVIGATION_TAB_ORDER;

    expect(moveNavigationTab(order, 0, 3)).toEqual(['market', 'agent', 'explore', 'wallet', 'settings']);
    expect(moveNavigationTab(order, 4, 1)).toEqual(['wallet', 'settings', 'market', 'agent', 'explore']);
    expect(order).toEqual(['wallet', 'market', 'agent', 'explore', 'settings']);
  });
});

describe('dragNavigationTab', () => {
  const lifted: NavigationTabDrag = { fromIndex: 1, toIndex: 1, offset: 0, step: 48 };

  it('takes the place whose middle the tab has passed', () => {
    expect(dragNavigationTab(lifted, 23, 5)).toEqual({ ...lifted, offset: 23, toIndex: 1 });
    expect(dragNavigationTab(lifted, 25, 5)).toEqual({ ...lifted, offset: 25, toIndex: 2 });
    expect(dragNavigationTab(lifted, -30, 5)).toEqual({ ...lifted, offset: -30, toIndex: 0 });
  });

  it('keeps the tab on the bar, so it reaches the first and the last place', () => {
    expect(dragNavigationTab(lifted, -500, 5)).toEqual({ ...lifted, offset: -48, toIndex: 0 });
    expect(dragNavigationTab(lifted, 500, 5)).toEqual({ ...lifted, offset: 144, toIndex: 4 });
  });

  it('follows a bar that runs right to left', () => {
    const rtl = { ...lifted, step: -80 };

    expect(dragNavigationTab(rtl, -170, 5)).toEqual({ ...rtl, offset: -170, toIndex: 3 });
    expect(dragNavigationTab(rtl, 500, 5)).toEqual({ ...rtl, offset: 80, toIndex: 0 });
  });
});

describe('getNavigationTabShift', () => {
  it('moves the dragged tab with the pointer and the passed tabs a place back', () => {
    const drag: NavigationTabDrag = { fromIndex: 1, toIndex: 3, offset: 100, step: 48 };

    expect([0, 1, 2, 3, 4].map((index) => getNavigationTabShift(index, drag))).toEqual([0, 100, -48, -48, 0]);
  });

  it('moves the passed tabs a place forward for a tab dragged back', () => {
    const drag: NavigationTabDrag = { fromIndex: 3, toIndex: 0, offset: -150, step: -80 };

    expect([0, 1, 2, 3, 4].map((index) => getNavigationTabShift(index, drag))).toEqual([-80, -80, -80, -150, 0]);
  });

  it('leaves the tabs in place without a drag', () => {
    expect(getNavigationTabShift(2)).toBe(0);
  });
});
