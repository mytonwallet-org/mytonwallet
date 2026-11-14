import { forceMutation, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { SECOND } from '../dateFormat';
import { stopEvent } from '../domEvents';
import { clamp } from '../math';
import { pause } from '../schedulers';
import { REM } from '../windowEnvironment';
import { createCarouselIdle, createCarouselSnap, getCarouselPose } from './carouselMotion';

/** Cards farther than this from the settled card are not mounted */
export const CAROUSEL_WINDOW_RADIUS = 1;

const ITEM_SELECTOR = '[data-card-carousel-item]';
const POSE_SELECTOR = '[data-card-carousel-pose]';
const PORTRAIT_CONTAINER_SELECTOR = '[data-portrait-wallet]';
const CARD_GAP_PX = 0.5 * REM;
const MIN_PORTRAIT_GUTTER_PX = 0.75 * REM;
const MAX_PORTRAIT_GUTTER_PX = 2 * REM;
const CAPPED_EDGE_OPACITY = '1';
const NARROW_EDGE_OPACITY = '0.6';
const SAME_POSITION_DISTANCE_PX = 0.1;
const EDGE_DISTANCE_PX = 0.5;
const SIZE_TOLERANCE_PX = 0.5;
const WHEEL_LINE_HEIGHT_PX = 16;
const MOMENTUM_IDLE_MS = 120;
const WHEEL_GESTURE_IDLE_MS = 120;
const FAR_JUMP_ARTWORK_WAIT_MS = 400;
const MAX_FRAME_SECONDS = 1 / 60;
const MIN_FLICK_VELOCITY_PX_PER_MS = 0.3;
const CENTER_Z_INDEX = 3;
const ORDERED_CARD_RADIUS = CAROUSEL_WINDOW_RADIUS + 1;

/**
 * What is moving the viewport now. A spring and wheel packets have no input of their own.
 * `momentum` means the finger is off the screen and the browser finishes the native scroll.
 */
type CarouselInput = 'none' | 'finger' | 'momentum' | 'mouse';

interface CarouselScrollOptions {
  root: HTMLElement;
  viewport: HTMLElement;
  snapDisabledClassName: string;
  getAccountIds: () => string[];
  getStartAccountId: () => string;
  getIsMotionDisabled: () => boolean;
  onSelectedChange: (accountId: string) => void;
  onMovingChange: (isMoving: boolean) => void;
  onSettle: (accountId: string) => void;
}

export type CarouselScroll = ReturnType<typeof startCarouselScroll>;

export function startCarouselScroll({
  root,
  viewport,
  snapDisabledClassName,
  getAccountIds,
  getStartAccountId,
  getIsMotionDisabled,
  onSelectedChange,
  onMovingChange,
  onSettle,
}: CarouselScrollOptions) {
  const portraitContainer = root.closest<HTMLElement>(PORTRAIT_CONTAINER_SELECTOR);
  const items = Array.from(viewport.querySelectorAll<HTMLElement>(ITEM_SELECTOR)).map((item) => ({
    item,
    pose: item.querySelector<HTMLElement>(POSE_SELECTOR)!,
  }));
  const itemNodes = items.map(({ item }) => item);
  const poseNodes = items.map(({ pose }) => pose);

  let input: CarouselInput = 'none';
  let isMoving = false;
  let selectedId = getStartAccountId();
  let step = 0;
  let lastPosedLeft = NaN;
  let orderedAroundIndex = -1;
  let snap: ReturnType<typeof createCarouselSnap> | undefined;
  let snapFrame = 0;
  let lockedWheelDirection = 0;
  let jumpAccountId: string | undefined;

  // One gesture moves at most one card away from this index, so it never reaches an unmounted card
  let centerIndex = Math.max(0, getAccountIds().indexOf(selectedId));

  const snapAfterIdle = createCarouselIdle(() => {
    if (input === 'none') snapToAccount(selectedId);
  });
  const settleAfterMomentum = createCarouselIdle(() => {
    if (input === 'momentum') settleScroll();
  }, MOMENTUM_IDLE_MS);
  const finishWheelGesture = createCarouselIdle(() => {
    lockedWheelDirection = 0;
  }, WHEEL_GESTURE_IDLE_MS);
  const resizeObserver = new ResizeObserver(handleResize);

  function alignToAccount(accountId: string) {
    // A moving card is reconciled with the account when the movement ends
    if (isMoving) return false;

    jumpAccountId = undefined;

    const index = getAccountIds().indexOf(accountId);
    const artwork = index >= 0 && Math.abs(index - centerIndex) > CAROUSEL_WINDOW_RADIUS
      ? items[index].pose.querySelector('img')
      : undefined;

    if (artwork) {
      void jumpAfterDecoding(accountId, artwork);
    } else {
      snapToAccount(accountId);
    }

    return true;
  }

  // The jump shows the target card at once, so the old card stays until the new artwork can be painted
  async function jumpAfterDecoding(accountId: string, artwork: HTMLImageElement) {
    jumpAccountId = accountId;

    await Promise.race([artwork.decode().catch(() => undefined), pause(FAR_JUMP_ARTWORK_WAIT_MS)]);

    requestMeasure(() => {
      if (jumpAccountId !== accountId || isMoving) return;

      jumpAccountId = undefined;
      snapToAccount(accountId, true);
    });
  }

  function stop() {
    jumpAccountId = undefined;
    snapAfterIdle.cancel();
    settleAfterMomentum.cancel();
    finishWheelGesture.cancel();
    stopSnap();
    resizeObserver.disconnect();
    viewport.removeEventListener('scroll', handleScroll);
    viewport.removeEventListener('scrollend', handleScrollEnd);
    viewport.removeEventListener('touchstart', handleTouchStart);
    viewport.removeEventListener('dragstart', stopEvent);
    viewport.removeEventListener('wheel', handleWheel);
    window.removeEventListener('touchend', handleTouchEnd);
    window.removeEventListener('touchcancel', handleTouchEnd);
    window.removeEventListener('blur', handleWindowBlur);

    // The viewport outlives this instance when the account list changes in the middle of a gesture
    requestMutation(() => {
      viewport.classList.remove(snapDisabledClassName);
    });
  }

  function handleScroll() {
    // The spring has already drawn this position, so its scroll event is only an echo
    if (snapFrame) return;

    trackScrollPosition(viewport.scrollLeft);
  }

  function handleScrollEnd() {
    if (input === 'momentum') settleScroll();
  }

  function handleResize() {
    const width = root.clientWidth;
    const nextStep = width + CARD_GAP_PX;
    const isStepChanged = Math.abs(step - nextStep) >= SIZE_TOLERANCE_PX;
    const portraitGutter = portraitContainer && getPortraitGutter(portraitContainer, width);
    const left = Math.max(0, getAccountIds().indexOf(selectedId)) * nextStep;

    if (portraitGutter) {
      forceMutation(() => {
        root.style.setProperty('--card-carousel-gutter', `${portraitGutter.gutter}px`);
        root.style.setProperty('--card-carousel-edge-opacity', portraitGutter.edgeOpacity);
      }, root);
    }

    if (!isStepChanged) return;

    stopSnap();
    step = nextStep;
    lastPosedLeft = NaN;

    forceMutation(() => {
      viewport.style.setProperty('--carousel-card-width', `${width}px`);
    }, viewport);

    viewport.scrollLeft = left;
    poseCards(left);

    if (isMoving) settleScroll();
  }

  function handleTouchStart() {
    input = 'finger';
    stopSnap();
    snapAfterIdle.cancel();
    settleAfterMomentum.cancel();
    setIsSnapDisabled(false);
  }

  function handleTouchEnd(e: TouchEvent) {
    if (input === 'finger' && !e.touches.length) releaseFinger();
  }

  function handleWindowBlur() {
    if (input === 'finger') releaseFinger();
  }

  function handleWheel(e: WheelEvent) {
    if (e.ctrlKey || e.metaKey || !e.deltaX || Math.abs(e.deltaX) < Math.abs(e.deltaY)) return;

    // Trackpads supply momentum in their wheel packets. Each packet is consumed here,
    // because WebKit can rubber-band a native scroll even from a position within bounds.
    e.preventDefault();
    finishWheelGesture.schedule();

    const delta = getWheelDeltaPixels(e, viewport.clientWidth);
    const direction = Math.sign(delta);

    // Momentum packets keep arriving after the neighbouring card is reached, and they must not move the next one
    if (direction === lockedWheelDirection) return;

    lockedWheelDirection = 0;

    const [minLeft, maxLeft] = getGestureBounds();
    const nextLeft = clamp(viewport.scrollLeft + delta, minLeft, maxLeft);

    if (nextLeft === minLeft || nextLeft === maxLeft) lockedWheelDirection = direction;

    if (Math.abs(nextLeft - viewport.scrollLeft) < SAME_POSITION_DISTANCE_PX) return;

    stopSnap();
    snapAfterIdle.cancel();
    setIsSnapDisabled(true);
    markMoving();
    viewport.scrollLeft = nextLeft;
    poseCards(nextLeft);

    if (!settleAtEdge(nextLeft)) snapAfterIdle.schedule();
  }

  function trackScrollPosition(left: number) {
    // The final programmatic write emits a scroll event after `settleScroll`.
    // The card has just resumed and is already centered, so it must not be suspended again.
    const selectedLeft = getAccountIds().indexOf(selectedId) * step;

    if (!isMoving && Math.abs(left - selectedLeft) < SAME_POSITION_DISTANCE_PX) {
      poseCards(left);
      return;
    }

    markMoving();
    poseCards(left);

    if (settleAtEdge(left)) return;

    if (input === 'momentum') {
      settleAfterMomentum.schedule();
    } else if (input === 'none') {
      snapAfterIdle.schedule();
    }
  }

  function releaseFinger() {
    input = isMoving ? 'momentum' : 'none';

    if (!isMoving) {
      settleScroll();
    } else if (!settleAtEdge(viewport.scrollLeft)) {
      settleAfterMomentum.schedule();
    }
  }

  function startMouseDrag() {
    input = 'mouse';
    stopSnap();
    snapAfterIdle.cancel();
  }

  function finishMouseDrag(pointerVelocity: number) {
    input = 'none';

    // The content moves against the pointer
    const velocity = -pointerVelocity;
    const position = viewport.scrollLeft / step;
    let index = Math.round(position);

    // A fast release turns the card in its direction, as a touch fling does
    if (velocity > MIN_FLICK_VELOCITY_PX_PER_MS) index = Math.ceil(position);
    if (velocity < -MIN_FLICK_VELOCITY_PX_PER_MS) index = Math.floor(position);

    snapToAccount(getAccountIds()[index], false, velocity * SECOND);
  }

  function snapToAccount(accountId: string, isInstant = false, releaseVelocity = snap?.velocity ?? 0) {
    const index = getAccountIds().indexOf(accountId);
    if (index < 0 || !step) return;

    const left = index * step;

    stopSnap();
    snapAfterIdle.cancel();
    settleAfterMomentum.cancel();

    if (input === 'momentum') input = 'none';

    if (
      isInstant
      || getIsMotionDisabled()
      || Math.abs(index - centerIndex) > CAROUSEL_WINDOW_RADIUS
      || Math.abs(viewport.scrollLeft - left) < SAME_POSITION_DISTANCE_PX
    ) {
      viewport.scrollLeft = left;
      centerIndex = index;
      poseCards(left);
      settleScroll();
      return;
    }

    startSnap(left, releaseVelocity);
  }

  function startSnap(targetLeft: number, releaseVelocity: number) {
    markMoving();
    setIsSnapDisabled(true);

    // The spring drives both the position and the pose. Browser smooth scrolling has its own short
    // acceleration, which differs between platforms and jerks the incoming card.
    const currentSnap = createCarouselSnap(viewport.scrollLeft, targetLeft, releaseVelocity);
    let previousAt = performance.now();

    function advanceSnap(now: number) {
      // A missed frame must not turn into a catch-up jump on the next one
      const position = currentSnap.advance(Math.min(MAX_FRAME_SECONDS, (now - previousAt) / SECOND));
      const left = currentSnap.isSettled ? targetLeft : position;

      previousAt = now;
      viewport.scrollLeft = left;
      poseCards(left);

      if (currentSnap.isSettled) {
        stopSnap();
        settleScroll();
      } else {
        snapFrame = requestAnimationFrame(advanceSnap);
      }
    }

    snap = currentSnap;
    snapFrame = requestAnimationFrame(advanceSnap);
  }

  function stopSnap() {
    cancelAnimationFrame(snapFrame);
    snapFrame = 0;
    snap = undefined;
  }

  function settleAtEdge(left: number) {
    if (input === 'finger' || input === 'mouse' || !isMoving) return false;

    const lastLeft = (getAccountIds().length - 1) * step;

    // An overscrolled frame can still be reported, so the position is compared with both ends of the list by distance
    if (Math.abs(left) > EDGE_DISTANCE_PX && Math.abs(left - lastLeft) > EDGE_DISTANCE_PX) return false;

    snapAfterIdle.cancel();
    settleScroll();

    return true;
  }

  function settleScroll() {
    if (input === 'finger' || input === 'mouse') return;

    input = 'none';
    settleAfterMomentum.cancel();
    setIsSnapDisabled(false);
    poseCards();

    if (isMoving) {
      isMoving = false;
      onMovingChange(false);
    }

    centerIndex = Math.max(0, getAccountIds().indexOf(selectedId));
    onSettle(selectedId);
  }

  function markMoving() {
    if (isMoving) return;

    isMoving = true;
    onMovingChange(true);
  }

  function poseCards(left = viewport.scrollLeft) {
    if (!step || left === lastPosedLeft) return;

    lastPosedLeft = left;

    const position = left / step;
    const accountIds = getAccountIds();
    const nearestIndex = clamp(Math.round(position), 0, accountIds.length - 1);
    const nearestId = accountIds[nearestIndex];

    writeCardPoses(position);

    if (nearestIndex !== orderedAroundIndex) writeCardOrder(nearestIndex);

    if (nearestId !== selectedId) {
      selectedId = nearestId;
      onSelectedChange(nearestId);
    }
  }

  function writeCardPoses(position: number) {
    const cardWidth = step - CARD_GAP_PX;
    const isMotionDisabled = getIsMotionDisabled();
    const firstIndex = Math.max(0, Math.floor(position) - CAROUSEL_WINDOW_RADIUS);
    const lastIndex = Math.min(items.length - 1, Math.ceil(position) + CAROUSEL_WINDOW_RADIUS);

    forceMutation(() => {
      for (let index = firstIndex; index <= lastIndex; index++) {
        const { edgeCorrection, matrix } = getCarouselPose(index - position, cardWidth);

        items[index].pose.style.transform = isMotionDisabled
          ? 'none'
          : `translateX(${edgeCorrection}px) matrix3d(${matrix.join(',')})`;
      }
    }, poseNodes);
  }

  // Only the relative order of the cards matters, and it changes only when another card becomes the nearest
  function writeCardOrder(nearestIndex: number) {
    const firstIndex = Math.max(0, nearestIndex - ORDERED_CARD_RADIUS);
    const lastIndex = Math.min(items.length - 1, nearestIndex + ORDERED_CARD_RADIUS);

    orderedAroundIndex = nearestIndex;

    forceMutation(() => {
      for (let index = firstIndex; index <= lastIndex; index++) {
        items[index].item.style.zIndex = String(CENTER_Z_INDEX - Math.abs(index - nearestIndex));
      }
    }, itemNodes);
  }

  function getGestureBounds(): [number, number] {
    const lastIndex = getAccountIds().length - 1;

    return [
      Math.max(0, centerIndex - CAROUSEL_WINDOW_RADIUS) * step,
      Math.min(lastIndex, centerIndex + CAROUSEL_WINDOW_RADIUS) * step,
    ];
  }

  function setIsSnapDisabled(isDisabled: boolean) {
    forceMutation(() => {
      viewport.classList.toggle(snapDisabledClassName, isDisabled);
    }, viewport);
  }

  resizeObserver.observe(viewport);

  if (portraitContainer) {
    resizeObserver.observe(portraitContainer);
  } else {
    // The root keeps the portrait values when the layout turns to landscape, which sets the gutter in its styles
    forceMutation(() => {
      root.style.removeProperty('--card-carousel-gutter');
      root.style.removeProperty('--card-carousel-edge-opacity');
    }, root);
  }

  viewport.addEventListener('scroll', handleScroll, { passive: true });
  viewport.addEventListener('scrollend', handleScrollEnd);
  viewport.addEventListener('touchstart', handleTouchStart, { passive: true });
  viewport.addEventListener('dragstart', stopEvent);
  viewport.addEventListener('wheel', handleWheel, { passive: false });
  window.addEventListener('touchend', handleTouchEnd, { passive: true });
  window.addEventListener('touchcancel', handleTouchEnd, { passive: true });
  window.addEventListener('blur', handleWindowBlur);

  // The previous instance can stop in the middle of a gesture, when the account list changes
  onSelectedChange(selectedId);
  onMovingChange(false);

  handleResize();

  return {
    alignToAccount,
    getGestureBounds,
    startMouseDrag,
    finishMouseDrag,
    stop,
  };
}

// The space beside the card exceeds the minimum gutter only when the card has reached its maximum width
function getPortraitGutter(portraitContainer: HTMLElement, width: number) {
  const gutter = clamp((portraitContainer.clientWidth - width) / 2, MIN_PORTRAIT_GUTTER_PX, MAX_PORTRAIT_GUTTER_PX);

  return {
    gutter,
    edgeOpacity: gutter - MIN_PORTRAIT_GUTTER_PX > SIZE_TOLERANCE_PX ? CAPPED_EDGE_OPACITY : NARROW_EDGE_OPACITY,
  };
}

function getWheelDeltaPixels(e: WheelEvent, pageWidth: number) {
  if (e.deltaMode === WheelEvent.DOM_DELTA_LINE) return e.deltaX * WHEEL_LINE_HEIGHT_PX;
  if (e.deltaMode === WheelEvent.DOM_DELTA_PAGE) return e.deltaX * pageWidth;

  return e.deltaX;
}
