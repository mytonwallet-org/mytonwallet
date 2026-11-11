import type React from '../lib/teact/teact';
import { type ElementRef, useEffect, useRef, useState } from '../lib/teact/teact';

import type { NavigationTab } from '../global/types';
import type { NavigationTabDrag } from '../util/navigationTabOrder';

import { vibrate } from '../util/haptics';
import { dragNavigationTab, moveNavigationTab } from '../util/navigationTabOrder';
import useFlag from './useFlag';
import useLastCallback from './useLastCallback';

// The long press of both navigation bars
export const NAVIGATION_TAB_HOLD_DURATION_MS = 400;
const HOLD_MOVE_TOLERANCE_PX = 6;

interface Hold {
  index: number;
  pointerId: number;
  startX: number;
  startY: number;
  timeoutId: number;
}

interface Drag extends NavigationTabDrag {
  pointerId: number;
  start: number;
}

/**
 * Lets a navigation tab be reordered on its bar: a pointer held still on a tab for the long-press time lifts it, and
 * dragging it along the bar moves it, the tabs it passes making room. A pointer that moves before the hold ends never
 * lifts a tab. The drop reports the new order; the click that ends a drag doesn't open the tab
 */
export default function useNavigationTabDrag({
  rootRef,
  tabClassName,
  axis,
  order,
  isLiftBlocked,
  onLift,
  onReorder,
}: {
  rootRef: ElementRef<HTMLDivElement>;
  tabClassName: string;
  axis: 'x' | 'y';
  order: NavigationTab[];
  isLiftBlocked?: boolean;
  onLift?: NoneToVoidFunction;
  onReorder: (order: NavigationTab[]) => void;
}) {
  const holdRef = useRef<Hold>();
  const wasDraggedRef = useRef(false);
  // Pointer events come faster than renders: a move right after the drop must not see the drag as the last render
  // left it, or it lifts the tab that has taken the dropped one's place
  const dragRef = useRef<Drag>();
  const [drag, setDrag] = useState<Drag | undefined>();
  const [isSettling, markSettling, unmarkSettling] = useFlag();

  function updateDrag(nextDrag?: Drag) {
    dragRef.current = nextDrag;
    setDrag(nextDrag);
  }

  function getTabElements() {
    return Array.from(rootRef.current?.children ?? []).filter((element) => {
      return element.classList.contains(tabClassName);
    }) as HTMLElement[];
  }

  function getPosition(e: { clientX: number; clientY: number }) {
    return axis === 'x' ? e.clientX : e.clientY;
  }

  const cancelHold = useLastCallback(() => {
    if (!holdRef.current) return;

    window.clearTimeout(holdRef.current.timeoutId);
    holdRef.current = undefined;
  });

  const liftHeldTab = useLastCallback(() => {
    const hold = holdRef.current;
    holdRef.current = undefined;
    const [first, second] = getTabElements();
    if (!hold || !second || isLiftBlocked) return;

    // The distance between neighbors, negative where the bar runs right to left
    const step = axis === 'x' ? second.offsetLeft - first.offsetLeft : second.offsetTop - first.offsetTop;
    if (!step) return;

    try {
      rootRef.current!.setPointerCapture(hold.pointerId);
    } catch {
      // The pointer was let go where the bar didn't see it
      return;
    }
    vibrate();
    onLift?.();
    updateDrag({
      fromIndex: hold.index,
      toIndex: hold.index,
      offset: 0,
      step,
      pointerId: hold.pointerId,
      start: getPosition({ clientX: hold.startX, clientY: hold.startY }),
    });
  });

  const handlePointerDown = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    wasDraggedRef.current = false;
    if (dragRef.current || e.button !== 0) return;

    const tab = (e.target as HTMLElement).closest(`.${tabClassName}`);
    const index = tab ? getTabElements().indexOf(tab as HTMLElement) : -1;
    if (index < 0) return;

    cancelHold();
    holdRef.current = {
      index,
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      timeoutId: window.setTimeout(liftHeldTab, NAVIGATION_TAB_HOLD_DURATION_MS),
    };
  });

  const handlePointerMove = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    const hold = holdRef.current;
    if (hold?.pointerId === e.pointerId) {
      const distance = Math.hypot(e.clientX - hold.startX, e.clientY - hold.startY);
      if (distance > HOLD_MOVE_TOLERANCE_PX || !e.buttons) cancelHold();
      return;
    }

    const currentDrag = dragRef.current;
    if (currentDrag?.pointerId !== e.pointerId) return;

    // A pointer moving with no button pressed has let go where the drag did not see it
    if (!e.buttons) {
      dropDraggedTab();
      return;
    }

    updateDrag({
      ...currentDrag,
      ...dragNavigationTab(currentDrag, getPosition(e) - currentDrag.start, order.length),
    });
  });

  const handlePointerEnd = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    cancelHold();
    if (dragRef.current?.pointerId !== e.pointerId) return;

    dropDraggedTab();
  });

  function dropDraggedTab() {
    const { fromIndex, toIndex } = dragRef.current!;
    wasDraggedRef.current = true;
    updateDrag(undefined);
    if (toIndex === fromIndex) return;

    // The tabs take their new places in the markup without moving again on screen
    markSettling();
    onReorder(moveNavigationTab(order, fromIndex, toIndex));
    requestAnimationFrame(() => requestAnimationFrame(unmarkSettling));
  }

  // Outside the bar its moves and its release go unseen until the drag captures the pointer
  const handleMouseLeave = useLastCallback(() => {
    cancelHold();
  });

  const handleContextMenu = useLastCallback((e: React.MouseEvent) => {
    if (holdRef.current || dragRef.current) e.preventDefault();
  });

  /** Tells whether a click ends a drag, which must not open the tab, and forgets the drag */
  const consumeDragEndClick = useLastCallback(() => {
    const wasDragged = wasDraggedRef.current;
    wasDraggedRef.current = false;

    return wasDragged;
  });

  const isDragging = Boolean(drag);

  useEffect(() => {
    const root = rootRef.current;
    if (!root || !isDragging) return undefined;

    // Touch scrolling would cancel the drag
    const preventScroll = (e: TouchEvent) => e.preventDefault();
    root.addEventListener('touchmove', preventScroll, { passive: false });

    return () => root.removeEventListener('touchmove', preventScroll);
  }, [isDragging, rootRef]);

  useEffect(() => cancelHold, [cancelHold]);

  return {
    drag,
    isSettling,
    consumeDragEndClick,
    pointerHandlers: {
      onPointerDown: handlePointerDown,
      onPointerMove: handlePointerMove,
      onPointerUp: handlePointerEnd,
      onPointerCancel: handlePointerEnd,
      onMouseLeave: handleMouseLeave,
      onContextMenu: handleContextMenu,
    },
  };
}
