import type { IAnchorPosition } from '../../../global/types';
import type { Layout } from '../../../hooks/useMenuPosition';

import windowSize from '../../../util/windowSize';

/**
 * A message's menu, as on mobile: under the bubble and whatever hangs from it down to `bottom`, or over them near the
 * end of the screen, lined up with the bubble's side wherever the press was. It keeps clear of the bubble's band
 * across the screen and is placed along it from the bubble's side.
 */
export function getAgentBubbleMenuLayout(
  bubbleRect: DOMRect | undefined,
  anchor: IAnchorPosition | undefined,
  isTrailingSide: boolean,
  bottom = bubbleRect?.bottom,
): Layout {
  if (!bubbleRect || !anchor || bottom === undefined) return { withPortal: true };

  const { width } = windowSize.get();
  return {
    withPortal: true,
    doNotCoverTrigger: true,
    isCenteredHorizontally: false,
    preferredPositionX: isTrailingSide ? 'right' : 'left',
    deltaX: (isTrailingSide ? bubbleRect.right : bubbleRect.left) - anchor.x,
    triggerRect: {
      left: 0, right: width, width, top: bubbleRect.top, bottom, height: bottom - bubbleRect.top,
    },
  };
}

// The shift keeps the pointer off the first item, as on a token
const POINTER_MENU_VERTICAL_SHIFT_PX = 4;

/**
 * A menu opened with a right click, as a token's: at the pointer, opening rightward and down where it fits and turned
 * the other way where it does not, inside the window. Only the pointer's line counts as what it keeps clear of, so a
 * tall message or card does not push it away.
 */
export function getAgentPointerMenuLayout(anchor: IAnchorPosition | undefined): Layout {
  if (!anchor) return { withPortal: true };

  const { width } = windowSize.get();
  return {
    withPortal: true,
    doNotCoverTrigger: false,
    isCenteredHorizontally: false,
    topShiftY: POINTER_MENU_VERTICAL_SHIFT_PX,
    preferredPositionX: 'left',
    triggerRect: {
      left: 0, right: width, width, top: anchor.y, bottom: anchor.y, height: 0,
    },
  };
}
