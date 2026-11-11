import type { NavigationTab } from '../global/types';

import { clamp } from './math';

export const DEFAULT_NAVIGATION_TAB_ORDER: NavigationTab[] = ['wallet', 'market', 'agent', 'explore', 'settings'];

/** Drops unknown and repeated tabs from a stored order and adds the missing ones in the default order */
export function resolveNavigationTabOrder(order?: NavigationTab[]): NavigationTab[] {
  if (!order) return DEFAULT_NAVIGATION_TAB_ORDER;

  const tabs = new Set(order.filter((tab) => DEFAULT_NAVIGATION_TAB_ORDER.includes(tab)));
  DEFAULT_NAVIGATION_TAB_ORDER.forEach((tab) => tabs.add(tab));

  return Array.from(tabs);
}

export function moveNavigationTab(order: NavigationTab[], fromIndex: number, toIndex: number): NavigationTab[] {
  const result = order.slice();
  const [tab] = result.splice(fromIndex, 1);
  result.splice(toIndex, 0, tab);

  return result;
}

/**
 * A tab dragged along a bar. `offset` is how far the pointer took it from its place, and `step` is the distance from
 * one place to the next, both in pixels along the bar
 */
export interface NavigationTabDrag {
  fromIndex: number;
  toIndex: number;
  offset: number;
  step: number;
}

/** Takes the dragged tab `delta` pixels from its place, keeping it on the bar, and finds the place it would take */
export function dragNavigationTab(drag: NavigationTabDrag, delta: number, tabCount: number): NavigationTabDrag {
  const { fromIndex, step } = drag;
  const places = clamp(delta / step, -fromIndex, tabCount - 1 - fromIndex);

  return { ...drag, offset: places * step, toIndex: Math.round(fromIndex + places) };
}

/** How far a tab moves while another one is dragged: the dragged one follows the pointer, the ones it passes make room */
export function getNavigationTabShift(index: number, drag?: NavigationTabDrag) {
  if (!drag) return 0;

  const { fromIndex, toIndex, offset, step } = drag;
  if (index === fromIndex) return offset;
  if (fromIndex < toIndex && index > fromIndex && index <= toIndex) return -step;
  if (toIndex < fromIndex && index >= toIndex && index < fromIndex) return step;

  return 0;
}
