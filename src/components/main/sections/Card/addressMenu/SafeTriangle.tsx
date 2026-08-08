import React, { memo, useEffect, useRef } from '../../../../../lib/teact/teact';

import type { IAnchorPosition } from '../../../../../global/types';
import type { SubMenuPosition } from './calculateSubMenuPosition';

import { requestMutation } from '../../../../../lib/fasterdom/fasterdom';

import Portal from '../../../../ui/Portal';

import styles from '../Card.module.scss';

interface OwnProps {
  position: SubMenuPosition;
  initialMouse: IAnchorPosition;
  onMouseEnter: NoneToVoidFunction;
  onMouseLeave: NoneToVoidFunction;
}

// Removes the safe triangle when the pointer stalls mid-path, so the rows beneath become hoverable again
const STALL_TIMEOUT_MS = 300;
// The corner spans this many pixels up and down, so a shaky diagonal path stays inside the triangle
const CORNER_HALF_HEIGHT_PX = 24;
// A small gap between the cursor and the triangle, so the element under the cursor keeps its hover
const CURSOR_GAP_PX = 2;

/**
 * An invisible overlay between the pointer and the near edge of an open sub-menu, shaped as a triangle.
 * The "corner" is its narrow end sitting at the cursor. The "base" is its wide side leaning against
 * the sub-menu edge and covering the full sub-menu height. The overlay swallows hover events, so sibling
 * rows on the pointer's diagonal path into the sub-menu do not react.
 * See https://www.smashingmagazine.com/2023/08/better-context-menus-safe-triangles/
 */
function SafeTriangle({
  position,
  initialMouse,
  onMouseEnter,
  onMouseLeave,
}: OwnProps) {
  const ref = useRef<HTMLDivElement>();

  useEffect(() => {
    const el = ref.current;
    if (!el) return undefined;

    let stallTimerId: number | undefined;
    // Style writes go through `requestMutation`; a pending value also serves as the "already scheduled" flag,
    // coalescing multiple `mousemove` events per frame into one write
    let pendingMouse: IAnchorPosition | undefined;

    // `positionX: 'right'` grows the sub-menu leftward from `x`, so the pointer travels from the right side
    const isFromRight = position.positionX === 'right';

    function applyStyles() {
      if (!pendingMouse) return;

      const { x: mouseX, y: mouseY } = pendingMouse;
      pendingMouse = undefined;

      const width = isFromRight
        ? mouseX - CURSOR_GAP_PX - position.x
        : position.x - mouseX - CURSOR_GAP_PX;

      // The cursor has already reached the sub-menu, so there is no space between them to cover
      if (width <= 0) {
        el!.style.display = 'none';
        return;
      }

      const cornerX = isFromRight ? width : 0;
      const baseX = isFromRight ? 0 : width;
      const cornerY = mouseY - position.y;

      el!.style.display = '';
      el!.style.left = `${isFromRight ? position.x : mouseX + CURSOR_GAP_PX}px`;
      el!.style.top = `${position.y}px`;
      el!.style.width = `${width}px`;
      el!.style.height = `${position.height}px`;
      el!.style.clipPath = `polygon(${cornerX}px ${cornerY - CORNER_HALF_HEIGHT_PX}px, `
        + `${baseX}px 0, ${baseX}px ${position.height}px, `
        + `${cornerX}px ${cornerY + CORNER_HALF_HEIGHT_PX}px)`;
    }

    function update(mouse: IAnchorPosition) {
      const isScheduled = Boolean(pendingMouse);
      pendingMouse = mouse;

      if (!isScheduled) requestMutation(applyStyles);
    }

    function dismiss() {
      pendingMouse = undefined;
      document.removeEventListener('mousemove', handleMouseMove);

      requestMutation(() => {
        el!.style.display = 'none';
      });
    }

    function handleMouseMove(e: MouseEvent) {
      window.clearTimeout(stallTimerId);
      stallTimerId = window.setTimeout(dismiss, STALL_TIMEOUT_MS);
      update({ x: e.clientX, y: e.clientY });
    }

    update(initialMouse);
    stallTimerId = window.setTimeout(dismiss, STALL_TIMEOUT_MS);
    document.addEventListener('mousemove', handleMouseMove);

    return () => {
      window.clearTimeout(stallTimerId);
      document.removeEventListener('mousemove', handleMouseMove);
    };
  }, [position, initialMouse]);

  return (
    <Portal>
      <div
        ref={ref}
        className={styles.safeTriangle}
        onMouseEnter={onMouseEnter}
        onMouseLeave={onMouseLeave}
      />
    </Portal>
  );
}

export default memo(SafeTriangle);
