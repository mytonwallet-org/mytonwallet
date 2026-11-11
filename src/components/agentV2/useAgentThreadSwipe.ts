import { type ElementRef, useEffect } from '../../lib/teact/teact';

import { requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate, timingFunctions } from '../../util/animation';
import { vibrate } from '../../util/haptics';
import { clamp } from '../../util/math';
import { IS_TOUCH_ENV, REM } from '../../util/windowEnvironment';
import getCanAnimate from '../agent/helpers/getCanAnimate';

import useLastCallback from '../../hooks/useLastCallback';

interface Options {
  /** The row: it takes the gesture, and its CSS variables lay the actions out */
  rowRef: ElementRef<HTMLDivElement>;
  classNames: {
    /** On the row while its actions show */
    swiped: string;
    /** On the row while letting go deletes the chat */
    armed: string;
    /** On each action the row has uncovered; the actions carry `data-swipe-action-index`, 0 at the trailing edge */
    actionShown: string;
  };
  isRtl: boolean;
  onFullSwipe: NoneToVoidFunction;
}

// The geometry of the actions under the row, as on mobile: three 3.125rem (50 px) circles 0.625rem apart and from the
// edge. It follows the root font size, as the actions' styles do.
const ACTION_SIZE = 3.125 * REM;
const ACTION_SPACING = 0.625 * REM;
const ACTION_COUNT = 3;
const OPEN_DISTANCE = 2 * ACTION_SPACING + ACTION_COUNT * ACTION_SIZE + (ACTION_COUNT - 1) * ACTION_SPACING;
// A swipe this close to the row's width deletes the chat
const FULL_SWIPE_MARGIN = 1.8125 * REM;
// Past the full swipe the row resists the finger
const RESISTANCE_POWER = 0.7;
// The gesture is a swipe once it moves this far, mostly sideways; vertically it is a scroll
const START_THRESHOLD = 8;
const DIRECTION_RATIO = 1.2;
// A finger near the opposite edge arms the full swipe earlier
const EDGE_ZONE = 60;
const EDGE_FRACTION = 0.6;
// Faster than this the release follows the finger's direction, in pixels per millisecond
const RELEASE_VELOCITY = 0.05;
// The share of the finger's speed so far kept at each move
const VELOCITY_SMOOTHING = 0.4;
const SETTLE_DURATION_MS = 450;
// The faded actions under a stretched Delete
const FADED_ACTIONS_OPACITY = 0.3;

// The one row whose actions show; another row's swipe or a scroll of the list closes it
let closeOpenRow: NoneToVoidFunction | undefined;

export function closeAgentThreadSwipe() {
  closeOpenRow?.();
}

/**
 * Telegram's chat list swipe on touch screens: the row slides toward the leading edge over Rename, Pin and Delete,
 * and a full swipe deletes the chat
 */
export default function useAgentThreadSwipe({
  rowRef, classNames, isRtl, onFullSwipe,
}: Options) {
  const handleFullSwipe = useLastCallback(onFullSwipe);

  useEffect(() => {
    if (!IS_TOUCH_ENV || !rowRef.current) return undefined;

    const row: HTMLDivElement = rowRef.current;
    const direction = isRtl ? 1 : -1;
    let offset = 0;
    let width = 0;
    let left = 0;
    // A settle that a newer one or a touch replaces stops
    let settleGeneration = 0;
    let pointerId: number | undefined;
    let startX = 0;
    let startY = 0;
    let startOffset = 0;
    let lastX = 0;
    let lastTime = 0;
    let velocity = 0;
    let isSwiping = false;
    let isArmed = false;
    let shouldSkipClick = false;

    // Runs in the mutation phase
    function applyStyles() {
      const confirmation = getConfirmationDistance(width);
      const stretch = clamp((offset - OPEN_DISTANCE) / Math.max(1, confirmation - OPEN_DISTANCE), 0, 1);

      row.classList.toggle(classNames.swiped, offset > 0);
      row.classList.toggle(classNames.armed, isArmed);
      row.style.setProperty('--swipe-offset', `${offset}px`);
      row.style.setProperty('--swipe-pill-width', `${Math.max(ACTION_SIZE, offset - 2 * ACTION_SPACING)}px`);
      row.style.setProperty('--swipe-faded-opacity', String(1 - (1 - FADED_ACTIONS_OPACITY) * stretch));
      row.querySelectorAll<HTMLElement>('[data-swipe-action-index]').forEach((action) => {
        const index = Number(action.dataset.swipeActionIndex);
        const slotStart = ACTION_SPACING + index * (ACTION_SIZE + ACTION_SPACING);
        // Each action pops in as the row uncovers its slot
        action.classList.toggle(classNames.actionShown, offset > slotStart + ACTION_SIZE / 2);
      });
    }

    function render() {
      requestMutation(applyStyles);
    }

    function settle(target: number) {
      const from = offset;
      const startedAt = Date.now();
      const generation = ++settleGeneration;
      isArmed = false;
      if (target > 0) {
        closeOpenRow = close;
      } else if (closeOpenRow === close) {
        closeOpenRow = undefined;
      }

      if (!getCanAnimate()) {
        offset = target;
        render();
        return;
      }

      animate(() => {
        if (generation !== settleGeneration) return false;

        const progress = Math.min(1, (Date.now() - startedAt) / SETTLE_DURATION_MS);
        offset = from + (target - from) * timingFunctions.easeOutCubic(progress);
        applyStyles();
        return progress < 1;
      }, requestMutation);
    }

    function close() {
      if (offset > 0) settle(0);
    }

    function handlePointerDown(e: PointerEvent) {
      if (e.pointerType !== 'touch' || pointerId !== undefined) return;

      settleGeneration++;
      pointerId = e.pointerId;
      startX = e.clientX;
      startY = e.clientY;
      lastX = e.clientX;
      lastTime = e.timeStamp;
      velocity = 0;
      startOffset = offset;
      ({ left, width } = row.getBoundingClientRect());
      const pillMaxWidth = width - 2 * ACTION_SPACING;
      requestMutation(() => {
        row.style.setProperty('--swipe-pill-max-width', `${pillMaxWidth}px`);
      });
      // A tap on a row with its actions shown closes them instead of opening the chat
      shouldSkipClick = offset > 0 && !(e.target as HTMLElement).closest('[data-swipe-action-index]');
    }

    function handlePointerMove(e: PointerEvent) {
      if (e.pointerId !== pointerId) return;

      const distanceX = (e.clientX - startX) * direction;
      const distanceY = e.clientY - startY;
      if (!isSwiping) {
        const horizontalTravel = Math.abs(distanceX);
        const verticalTravel = Math.abs(distanceY);
        if (verticalTravel > START_THRESHOLD && verticalTravel >= horizontalTravel) {
          pointerId = undefined;
          return;
        }
        if (horizontalTravel < START_THRESHOLD || horizontalTravel < DIRECTION_RATIO * verticalTravel) return;
        // A closed row only opens toward the leading edge
        if (distanceX < 0 && startOffset === 0) {
          pointerId = undefined;
          return;
        }

        isSwiping = true;
        shouldSkipClick = true;
        row.setPointerCapture(e.pointerId);
        if (closeOpenRow !== close) closeOpenRow?.();
        closeOpenRow = close;
      }

      const elapsed = Math.max(1, e.timeStamp - lastTime);
      velocity = VELOCITY_SMOOTHING * velocity
        + (1 - VELOCITY_SMOOTHING) * (((e.clientX - lastX) * direction) / elapsed);
      lastX = e.clientX;
      lastTime = e.timeStamp;

      const confirmation = getConfirmationDistance(width);
      const leadingEdgeDistance = isRtl ? left + width - e.clientX : e.clientX - left;
      const raw = startOffset + distanceX;
      const wasArmed = isArmed;
      isArmed = raw >= confirmation || (leadingEdgeDistance < EDGE_ZONE && raw >= confirmation * EDGE_FRACTION);
      if (isArmed !== wasArmed) vibrate(true);

      offset = isArmed ? Math.max(confirmation, resist(raw, confirmation)) : resist(raw, confirmation);
      render();
    }

    function handlePointerUp(e: PointerEvent) {
      if (e.pointerId !== pointerId) return;

      pointerId = undefined;
      if (!isSwiping) return;

      isSwiping = false;
      if (isArmed && e.type === 'pointerup') {
        settle(0);
        handleFullSwipe();
        return;
      }

      const shouldOpen = Math.abs(velocity) > RELEASE_VELOCITY ? velocity > 0 : offset > OPEN_DISTANCE / 2;
      settle(shouldOpen ? OPEN_DISTANCE : 0);
    }

    function handleClick(e: MouseEvent) {
      if (!shouldSkipClick) return;

      shouldSkipClick = false;
      e.stopPropagation();
      e.preventDefault();
      close();
    }

    row.addEventListener('pointerdown', handlePointerDown);
    row.addEventListener('pointermove', handlePointerMove);
    row.addEventListener('pointerup', handlePointerUp);
    row.addEventListener('pointercancel', handlePointerUp);
    row.addEventListener('click', handleClick, true);

    return () => {
      row.removeEventListener('pointerdown', handlePointerDown);
      row.removeEventListener('pointermove', handlePointerMove);
      row.removeEventListener('pointerup', handlePointerUp);
      row.removeEventListener('pointercancel', handlePointerUp);
      row.removeEventListener('click', handleClick, true);
      settleGeneration++;
      if (closeOpenRow === close) closeOpenRow = undefined;
      if (offset > 0) {
        offset = 0;
        isArmed = false;
        render();
      }
    };
  }, [classNames, handleFullSwipe, isRtl, rowRef]);
}

function getConfirmationDistance(width: number) {
  return Math.max(OPEN_DISTANCE, Math.round(width - FULL_SWIPE_MARGIN));
}

// Up to the full swipe the row follows the finger; beyond it the row moves less and less
function resist(distance: number, confirmation: number) {
  if (distance <= 0) return 0;
  if (distance > confirmation) return confirmation + (distance - confirmation) ** RESISTANCE_POWER;

  return distance;
}
