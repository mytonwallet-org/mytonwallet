import { type ElementRef, useLayoutEffect, useRef } from '../../lib/teact/teact';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';

import { requestForcedReflow } from '../../lib/fasterdom/fasterdom';
import { animateShift } from '../../util/layoutChangeAnimation';
import getCanAnimate from '../agent/helpers/getCanAnimate';

// The list's rows and section titles carry it, so that each is found again after the chats change
const ROW_KEY_ATTRIBUTE = 'data-agent-row-key';

// The rows the user moved or closed up settle in this long, as on mobile
const REORDER_DURATION_MS = 450;
const APPEAR_KEYFRAMES: Keyframe[] = [{ opacity: 0 }, { opacity: 1 }];
const APPEAR_OPTIONS: KeyframeAnimationOptions = { duration: 250, easing: 'ease-out' };
// At the very top the list shows a chat that comes in above the rows, rather than keeping them where they were
const TOP_SCROLL_TOLERANCE = 0.5;

interface RowPosition {
  element: HTMLElement;
  top: number;
  height: number;
}

/**
 * Plays out the changes the user made, such as a pin or a deletion: the rows slide from where they were to where they
 * are. A change that comes with new data, such as a chat that moves up with a new message, keeps the rows on screen
 * where they are, as a messenger's chat list does.
 */
export default function useAgentThreadListMotion(
  bodyRef: ElementRef<HTMLDivElement>,
  items: AgentThreadListItemV2[] | undefined,
  isUserChange: boolean | undefined,
) {
  const positionsRef = useRef<Map<string, RowPosition>>();

  useLayoutEffect(() => {
    if (!items) return;

    requestForcedReflow(() => {
      const body = bodyRef.current;
      // A list out of the layout, as under another tab, has no positions to start from
      if (!body?.offsetHeight) {
        positionsRef.current = undefined;
        return undefined;
      }

      const previous = positionsRef.current;
      const positions = measurePositions(body);
      positionsRef.current = positions;
      if (!previous) return undefined;

      if (isUserChange) {
        return () => playMoves(previous, positions);
      }

      const { scrollTop } = body;
      const shift = getAnchorShift(previous, positions, scrollTop);
      return shift ? () => {
        body.scrollTop = scrollTop + shift;
      } : undefined;
    });
  }, [bodyRef, isUserChange, items]);
}

// Positions within the list's content, which neither scrolling nor a running slide changes
function measurePositions(body: HTMLElement) {
  const positions = new Map<string, RowPosition>();
  body.querySelectorAll<HTMLElement>(`[${ROW_KEY_ATTRIBUTE}]`).forEach((element) => {
    positions.set(element.getAttribute(ROW_KEY_ATTRIBUTE)!, {
      element,
      top: element.offsetTop,
      height: element.offsetHeight,
    });
  });
  return positions;
}

function playMoves(previous: Map<string, RowPosition>, positions: Map<string, RowPosition>) {
  if (!getCanAnimate()) return;

  positions.forEach(({ element, top }, key) => {
    const previousPosition = previous.get(key);
    if (!previousPosition) {
      element.animate(APPEAR_KEYFRAMES, APPEAR_OPTIONS);
      return;
    }

    if (previousPosition.top !== top) animateShift(element, 0, previousPosition.top - top, REORDER_DURATION_MS);
  });
}

/** How far the content moved under the first visible row that stays */
function getAnchorShift(previous: Map<string, RowPosition>, positions: Map<string, RowPosition>, scrollTop: number) {
  if (scrollTop <= TOP_SCROLL_TOLERANCE) return 0;

  let anchorKey: string | undefined;
  let anchorTop = Infinity;
  previous.forEach(({ top, height }, key) => {
    if (top + height > scrollTop && top < anchorTop && positions.has(key)) {
      anchorKey = key;
      anchorTop = top;
    }
  });

  return anchorKey ? positions.get(anchorKey)!.top - anchorTop : 0;
}
