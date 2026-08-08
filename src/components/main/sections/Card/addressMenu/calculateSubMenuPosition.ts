import { clamp } from '../../../../../util/math';
import windowSize from '../../../../../util/windowSize';

export interface SubMenuPosition {
  x: number;
  y: number;
  positionX: 'left' | 'right';
  originY: number;
  height: number;
}

const SUB_MENU_OVERLAP_PX = 8;
// Matches `VISUAL_COMFORT_SPACE` in `useMenuPosition`
const SUB_MENU_COMFORT_SPACE_PX = 16;

export default function calculateSubMenuPosition(
  rowEl: HTMLElement,
  menuWidth: number,
  menuHeight: number,
  isRtl?: boolean,
): SubMenuPosition {
  const bubbleRect = rowEl.closest('.menu-bubble')!.getBoundingClientRect();
  const rowRect = rowEl.getBoundingClientRect();
  const { width: windowWidth, height, safeAreaBottom } = windowSize.get();
  const windowHeight = height - safeAreaBottom;

  const rightX = bubbleRect.right - SUB_MENU_OVERLAP_PX;
  const leftX = bubbleRect.left + SUB_MENU_OVERLAP_PX;
  const doesFitRight = rightX + menuWidth <= windowWidth - SUB_MENU_COMFORT_SPACE_PX;
  const doesFitLeft = leftX - menuWidth >= SUB_MENU_COMFORT_SPACE_PX;

  // `positionX: 'left'` grows the menu rightward from `x`, `'right'` grows it leftward
  let x: number;
  let positionX: 'left' | 'right';

  if (isRtl ? doesFitLeft : doesFitRight) {
    x = isRtl ? leftX : rightX;
    positionX = isRtl ? 'right' : 'left';
  } else if (isRtl ? doesFitRight : doesFitLeft) {
    x = isRtl ? rightX : leftX;
    positionX = isRtl ? 'left' : 'right';
  } else {
    // No side has enough space - the menu sticks to the far screen edge, covering the parent menu
    x = isRtl ? SUB_MENU_COMFORT_SPACE_PX + menuWidth : windowWidth - menuWidth - SUB_MENU_COMFORT_SPACE_PX;
    positionX = isRtl ? 'right' : 'left';
  }

  // The sub-menu top aligns with the anchor row, so its first row sits at the anchor's level.
  // When there is not enough space below, the sub-menu bottom aligns with the viewport bottom
  // minus the safe area instead.
  const rowCenterY = rowRect.top + rowRect.height / 2;
  const y = clamp(
    rowRect.top,
    SUB_MENU_COMFORT_SPACE_PX,
    windowHeight - menuHeight,
  );

  return {
    x, y, positionX, originY: rowCenterY - y, height: menuHeight,
  };
}
