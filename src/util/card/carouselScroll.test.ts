import type { CarouselScroll } from './carouselScroll';

import { startCarouselScroll } from './carouselScroll';

jest.mock('../windowEnvironment', () => ({ REM: 16 }));

const CARD_STEP_PX = 308;
const WHEEL_GESTURE_IDLE_MS = 200;

let root: HTMLDivElement;
let viewport: HTMLDivElement;
let carousel: CarouselScroll;
let isMoving: boolean;
const onSettle = jest.fn();

beforeEach(() => {
  jest.useFakeTimers();
  jest.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(300);
  isMoving = false;
  onSettle.mockClear();
});

afterEach(async () => {
  carousel.stop();
  await jest.advanceTimersByTimeAsync(50);
  root.remove();
  jest.restoreAllMocks();
  jest.useRealTimers();
});

function startCarousel(accountIds: string[], isMotionDisabled = false) {
  root = document.createElement('div');
  viewport = document.createElement('div');

  const track = document.createElement('div');

  accountIds.forEach(() => {
    const item = document.createElement('div');
    const pose = document.createElement('div');

    item.setAttribute('data-card-carousel-item', '');
    pose.setAttribute('data-card-carousel-pose', '');
    item.append(pose);
    track.append(item);
  });

  viewport.append(track);
  root.append(viewport);
  document.body.append(root);

  carousel = startCarouselScroll({
    root,
    viewport,
    snapDisabledClassName: 'snapDisabled',
    getAccountIds: () => accountIds,
    getStartAccountId: () => accountIds[0],
    getIsMotionDisabled: () => isMotionDisabled,
    onSelectedChange: jest.fn(),
    onMovingChange: (value) => {
      isMoving = value;
    },
    onSettle,
  });

  onSettle.mockClear();
}

function dispatchTouch(type: string, touches: unknown[], target: EventTarget = viewport) {
  const event = new Event(type, { bubbles: true });

  Object.assign(event, { touches });
  target.dispatchEvent(event);
}

function addArtwork(itemIndex: number) {
  const image = document.createElement('img');
  let finishDecoding!: NoneToVoidFunction;

  image.decode = () => new Promise<void>((resolve) => {
    finishDecoding = resolve;
  });
  viewport.querySelectorAll('[data-card-carousel-pose]')[itemIndex].append(image);

  return () => finishDecoding();
}

function scrollViewport(left: number) {
  viewport.scrollLeft = left;
  viewport.dispatchEvent(new Event('scroll'));
}

function dispatchWheel(init: WheelEventInit) {
  const event = new WheelEvent('wheel', { cancelable: true, ...init });

  viewport.dispatchEvent(event);

  return event;
}

describe('touch', () => {
  it('keeps native scrolling after pointercancel while the finger is still down', async () => {
    startCarousel(['first', 'second']);
    dispatchTouch('touchstart', [{}]);
    scrollViewport(170);

    const cancel = new Event('pointercancel', { bubbles: true });

    Object.assign(cancel, { pointerId: 1, pointerType: 'touch' });
    viewport.dispatchEvent(cancel);
    await jest.advanceTimersByTimeAsync(300);

    expect(viewport.scrollLeft).toBe(170);
    expect(isMoving).toBe(true);
    expect(onSettle).not.toHaveBeenCalled();
  });

  it('lets native momentum finish and settles on scrollend, without a second snap', async () => {
    startCarousel(['first', 'second']);
    dispatchTouch('touchstart', [{}]);
    scrollViewport(170);
    dispatchTouch('touchend', [], window);
    await jest.advanceTimersByTimeAsync(60);
    scrollViewport(270);
    await jest.advanceTimersByTimeAsync(60);

    expect(viewport.scrollLeft).toBe(270);
    expect(onSettle).not.toHaveBeenCalled();

    scrollViewport(CARD_STEP_PX - 0.2);
    viewport.dispatchEvent(new Event('scrollend'));
    await jest.advanceTimersByTimeAsync(50);

    expect(viewport.scrollLeft).toBe(CARD_STEP_PX - 0.2);
    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledTimes(1);
    expect(onSettle).toHaveBeenCalledWith('second');
  });

  it('settles immediately after the last card returns from native overscroll', async () => {
    startCarousel(['first', 'second']);
    dispatchTouch('touchstart', [{}]);
    scrollViewport(270);
    dispatchTouch('touchend', [], window);
    scrollViewport(330);

    expect(isMoving).toBe(true);
    expect(onSettle).not.toHaveBeenCalled();

    scrollViewport(CARD_STEP_PX);

    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledWith('second');

    dispatchWheel({ deltaX: 5 });

    expect(isMoving).toBe(false);

    await jest.advanceTimersByTimeAsync(150);

    expect(onSettle).toHaveBeenCalledTimes(1);
  });

  it('keeps the edge under the finger until the touch ends', () => {
    startCarousel(['first', 'second']);
    dispatchTouch('touchstart', [{}]);
    scrollViewport(CARD_STEP_PX);

    expect(isMoving).toBe(true);
    expect(onSettle).not.toHaveBeenCalled();

    dispatchTouch('touchend', [], window);

    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledTimes(1);
  });
});

describe('wheel', () => {
  it('consumes a trackpad packet that crosses the boundary before native rubber-banding can start', () => {
    startCarousel(['first', 'second']);
    scrollViewport(270);

    expect(dispatchWheel({ deltaX: 150 }).defaultPrevented).toBe(true);
    expect(viewport.scrollLeft).toBe(CARD_STEP_PX);
    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledWith('second');

    for (let i = 0; i < 5; i++) {
      expect(dispatchWheel({ deltaX: 30 }).defaultPrevented).toBe(true);
      expect(viewport.scrollLeft).toBe(CARD_STEP_PX);
    }

    dispatchWheel({ deltaX: -500 });

    expect(viewport.scrollLeft).toBe(0);
  });

  it('preserves trackpad delta and momentum within the carousel bounds', () => {
    startCarousel(['first', 'second']);
    dispatchWheel({ deltaX: 70 });
    dispatchWheel({ deltaX: 35 });

    expect(viewport.scrollLeft).toBe(105);
    expect(isMoving).toBe(true);
  });

  it('moves one card per trackpad flick', async () => {
    startCarousel(['first', 'second', 'third', 'fourth']);
    dispatchWheel({ deltaX: 1000 });

    expect(viewport.scrollLeft).toBe(CARD_STEP_PX);

    await jest.advanceTimersByTimeAsync(50);

    expect(onSettle).toHaveBeenCalledWith('second');

    dispatchWheel({ deltaX: 200 });

    expect(viewport.scrollLeft).toBe(CARD_STEP_PX);

    await jest.advanceTimersByTimeAsync(WHEEL_GESTURE_IDLE_MS);
    dispatchWheel({ deltaX: 200 });

    expect(viewport.scrollLeft).toBe(CARD_STEP_PX + 200);
  });

  it('leaves a vertical wheel to the page', () => {
    startCarousel(['first', 'second']);

    const event = dispatchWheel({ deltaX: 2, deltaY: 120 });

    expect(event.defaultPrevented).toBe(false);
    expect(viewport.scrollLeft).toBe(0);
    expect(isMoving).toBe(false);
  });
});

describe('mouse', () => {
  it('limits a drag to the neighbouring cards', () => {
    startCarousel(['first', 'second', 'third', 'fourth']);

    expect(carousel.getGestureBounds()).toEqual([0, CARD_STEP_PX]);

    carousel.alignToAccount('third');

    expect(carousel.getGestureBounds()).toEqual([CARD_STEP_PX, 3 * CARD_STEP_PX]);
  });

  it('does not take the card away from a drag', async () => {
    startCarousel(['first', 'second', 'third']);
    carousel.startMouseDrag();
    scrollViewport(100);
    await jest.advanceTimersByTimeAsync(300);

    expect(viewport.scrollLeft).toBe(100);
    expect(onSettle).not.toHaveBeenCalled();
  });

  it('settles on the card under a released drag', () => {
    startCarousel(['first', 'second', 'third']);
    carousel.startMouseDrag();
    scrollViewport(CARD_STEP_PX);

    expect(isMoving).toBe(true);

    carousel.finishMouseDrag(0);

    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledWith('second');
  });

  it.each([
    ['turns the card after a fast release', -1, 'second'],
    ['returns to the card after a slow release', -0.1, 'first'],
  ])('%s', async (_, pointerVelocity, settledId) => {
    startCarousel(['first', 'second', 'third']);
    carousel.startMouseDrag();
    scrollViewport(CARD_STEP_PX / 4);
    carousel.finishMouseDrag(pointerVelocity);
    await jest.advanceTimersByTimeAsync(1000);

    expect(onSettle).toHaveBeenLastCalledWith(settledId);
  });
});

describe('alignment with the current account', () => {
  it('jumps to a card outside the mounted window without animation', () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);
    carousel.alignToAccount('fifth');

    expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
    expect(isMoving).toBe(false);
    expect(onSettle).toHaveBeenCalledWith('fifth');
  });

  it('waits for the artwork of a far card before jumping to it', async () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);

    const finishDecoding = addArtwork(4);

    carousel.alignToAccount('fifth');
    await jest.advanceTimersByTimeAsync(100);

    expect(viewport.scrollLeft).toBe(0);

    finishDecoding();
    await jest.advanceTimersByTimeAsync(50);

    expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
    expect(onSettle).toHaveBeenCalledWith('fifth');
  });

  it('jumps anyway when the artwork takes too long', async () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);
    addArtwork(4);
    carousel.alignToAccount('fifth');
    await jest.advanceTimersByTimeAsync(450);

    expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
  });

  it('drops a pending jump when another account is aligned', async () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);

    const finishDecoding = addArtwork(4);

    carousel.alignToAccount('fifth');
    carousel.alignToAccount('first');
    finishDecoding();
    await jest.advanceTimersByTimeAsync(50);

    expect(viewport.scrollLeft).toBe(0);
  });

  it('animates to a neighbouring card', async () => {
    startCarousel(['first', 'second', 'third']);
    carousel.alignToAccount('second');

    expect(isMoving).toBe(true);

    await jest.advanceTimersByTimeAsync(500);

    expect(viewport.scrollLeft).toBe(CARD_STEP_PX);
    expect(isMoving).toBe(false);
  });

  it('keeps following a resting finger after the account changes outside the carousel', async () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);
    dispatchTouch('touchstart', [{}]);
    carousel.alignToAccount('fifth');
    scrollViewport(4 * CARD_STEP_PX - 100);
    await jest.advanceTimersByTimeAsync(300);

    expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX - 100);
    expect(onSettle).not.toHaveBeenCalled();
  });

  it('settles an external instant jump when a stationary finger releases', async () => {
    startCarousel(['first', 'second', 'third', 'fourth', 'fifth']);
    dispatchTouch('touchstart', [{}]);
    carousel.alignToAccount('fifth');
    viewport.dispatchEvent(new Event('scroll'));
    dispatchTouch('touchend', [], window);
    viewport.dispatchEvent(new Event('scrollend'));
    await jest.advanceTimersByTimeAsync(500);

    expect(viewport.scrollLeft).toBe(4 * CARD_STEP_PX);
    expect(onSettle).toHaveBeenCalledWith('fifth');
  });

  it('does not take the card away from the finger', () => {
    startCarousel(['first', 'second', 'third']);
    dispatchTouch('touchstart', [{}]);
    scrollViewport(100);
    carousel.alignToAccount('third');

    expect(viewport.scrollLeft).toBe(100);
  });
});

it('changes the card order only when the nearest card changes', () => {
  startCarousel(['first', 'second', 'third']);

  const items = Array.from(viewport.querySelectorAll<HTMLElement>('[data-card-carousel-item]'));
  const setZIndex = jest.spyOn(items[0].style, 'zIndex', 'set');

  dispatchTouch('touchstart', [{}]);
  scrollViewport(50);
  scrollViewport(100);

  expect(setZIndex).not.toHaveBeenCalled();

  scrollViewport(200);

  expect(setZIndex).toHaveBeenCalledTimes(1);
  expect(Number(items[1].style.zIndex)).toBeGreaterThan(Number(items[0].style.zIndex));
});

it('restores snapping when it stops in the middle of a movement', async () => {
  startCarousel(['first', 'second']);
  dispatchWheel({ deltaX: 70 });

  expect(viewport.classList.contains('snapDisabled')).toBe(true);

  carousel.stop();
  await jest.advanceTimersByTimeAsync(50);

  expect(viewport.classList.contains('snapDisabled')).toBe(false);
});

it('poses only the cards near the viewport', () => {
  startCarousel(['first', 'second', 'third', 'fourth', 'fifth', 'sixth']);

  const poses = Array.from(viewport.querySelectorAll<HTMLElement>('[data-card-carousel-pose]'));

  expect(poses[0].style.transform).not.toBe('');
  expect(poses[1].style.transform).not.toBe('');
  expect(poses[2].style.transform).toBe('');
  expect(poses[5].style.transform).toBe('');
});
