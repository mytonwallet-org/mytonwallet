import { useEffect } from '../lib/teact/teact';

import type { CardMotionFrame } from '../util/card/types';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { createCardPressMotion, getCardPressMatrix } from '../util/card/pressMotion';
import { vibrate } from '../util/haptics';
import useCardPress from './useCardPress';

jest.mock('../lib/teact/teact', () => ({ useEffect: jest.fn() }));
jest.mock('../lib/fasterdom/fasterdom', () => ({ requestMeasure: jest.fn(), requestMutation: jest.fn() }));
jest.mock('../util/haptics', () => ({ vibrate: jest.fn() }));

let now = 0;
let measures: (() => void)[];
let mutations: (() => void)[];
let cleanup: (() => void) | undefined;
let rotator: HTMLElement;
const receive = jest.fn<void, [CardMotionFrame]>();

beforeEach(() => {
  jest.useFakeTimers({ doNotFake: ['performance'] });
  now = 0;
  jest.spyOn(window, 'matchMedia').mockImplementation((media) => ({ matches: true, media } as MediaQueryList));
  measures = [];
  mutations = [];

  jest.mocked(requestMeasure).mockImplementation((cb) => {
    measures.push(cb);
  });

  jest.mocked(requestMutation).mockImplementation((cb) => {
    mutations.push(cb);
  });

  jest.spyOn(performance, 'now').mockImplementation(() => now);
});

afterEach(() => {
  cleanup?.();
  cleanup = undefined;
  jest.clearAllMocks();
  jest.restoreAllMocks();
  jest.useRealTimers();
});

function frame() {
  now += 1000 / 60;
  jest.advanceTimersByTime(1000 / 60);

  const tasks = measures;
  measures = [];
  tasks.forEach((cb) => cb());

  const writes = mutations;
  mutations = [];
  writes.forEach((cb) => cb());
}

function pointer(target: EventTarget, type: string, x = 100, y = 100, id = 1, pointerType = 'touch') {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.assign(event, { isPrimary: true, button: 0, pointerId: id, clientX: x, clientY: y, pointerType });
  target.dispatchEvent(event);

  return event;
}

function mount(isDisabled = false) {
  const card = document.createElement('div');
  rotator = document.createElement('div');
  jest.spyOn(card, 'getBoundingClientRect').mockReturnValue({ left: 0, top: 0, width: 100, height: 100 } as DOMRect);
  useCardPress({ cardRef: { current: card }, rotatorRef: { current: rotator }, isDisabled, onMotionFrame: receive });
  cleanup = jest.mocked(useEffect).mock.calls.at(-1)![0]() as (() => void) | undefined;

  return card;
}

function last() {
  return receive.mock.calls.at(-1)![0];
}

function isPlaying() {
  return Boolean(receive.mock.calls.at(-1)?.[0].isPlaying);
}

it('uses the stationary wrapper and the native initial frame', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  frame();
  frame();

  const native = createCardPressMotion();
  native.press(1, 1);
  native.advance(1 / 60);

  const matrix = getCardPressMatrix(native.value, 100).join(',');
  expect(rotator.style.transform).toBe(`matrix3d(${matrix})`);
});

it('publishes the pointer and lets lighting observe the release tail', () => {
  const card = mount();
  pointer(card, 'pointerdown', 80, 30);
  for (let i = 0; i < 12; i++) frame();
  expect(last().isPlaying).toBe(true);
  expect(last().pointer![0]).toBeCloseTo(0.6, 12);
  expect(last().pointer![1]).toBeCloseTo(-0.4, 12);
  pointer(window, 'pointerup', 80, 30);
  frame();

  const release = last();
  expect(release.pointer).toBeUndefined();
  expect(release.isPlaying).toBe(false);
  expect(release.press[2]).toBeGreaterThan(0);
  for (let i = 0; i < 300; i++) frame();
  expect(last().press).toEqual([0, 0, 0]);
});

it('does not rotate on hover or consume button clicks', () => {
  const card = mount();
  pointer(window, 'pointermove');
  frame();
  expect(rotator.style.cssText).toBe('');

  const button = document.createElement('button');
  card.append(button);

  const click = jest.fn();
  button.addEventListener('click', click);

  const down = pointer(button, 'pointerdown');
  pointer(window, 'pointerup');
  button.click();
  expect(down.defaultPrevented).toBe(false);
  expect(click).toHaveBeenCalledTimes(1);
});

it('plays immediately on mouse hover, tracks the cursor and settles after leaving', () => {
  const card = mount();
  const capture = jest.fn();
  Object.assign(card, { setPointerCapture: capture });
  pointer(card, 'pointerenter', 80, 30, 1, 'mouse');
  frame();
  expect(last()).toMatchObject({ isPlaying: true, isHovering: true });
  expect(last().pointer![0]).toBeCloseTo(0.6);
  expect(last().pointer![1]).toBeCloseTo(-0.4);
  expect(now).toBeLessThan(150);
  pointer(window, 'pointermove', 20, 70, 1, 'mouse');
  for (let i = 0; i < 60; i++) frame();
  expect(last().pointer![0]).toBeCloseTo(-0.6);
  expect(last().light.opacity).toBeCloseTo(1);
  expect(capture).not.toHaveBeenCalled();
  expect(vibrate).not.toHaveBeenCalled();
  pointer(card, 'pointerleave', 120, 70, 1, 'mouse');
  frame();
  expect(last().isPlaying).toBe(false);
  expect(last().pointer).toBeUndefined();
  for (let i = 0; i < 300; i++) frame();
  expect(rotator.style.transform).toBe('none');
  expect(last().light.opacity).toBe(0);
});

it('publishes a resting frame when play is disabled midway', () => {
  const card = mount();
  pointer(card, 'pointerenter', 80, 30, 1, 'mouse');
  frame();
  expect(last()).toMatchObject({ isPlaying: true, isHovering: true });
  cleanup!();
  cleanup = undefined;
  expect(last()).toMatchObject({ isPlaying: false, isHovering: false, press: [0, 0, 0], light: { opacity: 0 } });
  expect(last().pointer).toBeUndefined();
});

it('retains hover play after a normal click and preserves controls, scrolling and context menus', () => {
  const card = mount();
  const button = document.createElement('button');
  card.append(button);

  const clicked = jest.fn();
  button.addEventListener('click', clicked);
  pointer(card, 'pointerenter', 60, 40, 1, 'mouse');
  pointer(button, 'pointerdown', 60, 40, 1, 'mouse');
  pointer(window, 'pointerup', 60, 40, 1, 'mouse');

  const click = new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 });
  button.dispatchEvent(click);
  for (let i = 0; i < 12; i++) frame();
  expect(clicked).toHaveBeenCalledTimes(1);
  expect(click.defaultPrevented).toBe(false);
  expect(last()).toMatchObject({ isPlaying: true, isHovering: true });

  const wheel = new WheelEvent('wheel', { cancelable: true, deltaY: 100 });
  window.dispatchEvent(wheel);
  expect(wheel.defaultPrevented).toBe(false);

  const context = new Event('contextmenu', { bubbles: true, cancelable: true });
  card.dispatchEvent(context);
  expect(context.defaultPrevented).toBe(false);
  expect(vibrate).not.toHaveBeenCalled();
  document.dispatchEvent(new Event('scroll'));
  frame();
  expect(isPlaying()).toBe(false);
  for (let i = 0; i < 180; i++) frame();
  expect(rotator.style.transform).toBe('none');
});

it('keeps touch play behind the hold threshold while mouse hover plays immediately', () => {
  const card = mount();
  pointer(card, 'pointerenter', 60, 40);
  frame();
  expect(isPlaying()).toBe(false);
  pointer(card, 'pointerdown', 60, 40);
  jest.advanceTimersByTime(149);
  expect(vibrate).not.toHaveBeenCalled();
  frame();
  expect(last()).toMatchObject({ isPlaying: true, isHovering: false });
  expect(vibrate).toHaveBeenCalledTimes(1);
  pointer(window, 'pointerup', 60, 40);
  frame();
  expect(isPlaying()).toBe(false);
});

it('settles a hover that leaves before the first measurement and can reenter cleanly', () => {
  const card = mount();
  pointer(card, 'pointerenter', 80, 30, 1, 'mouse');
  pointer(card, 'pointerleave', 120, 30, 1, 'mouse');
  for (let i = 0; i < 300; i++) frame();
  expect(isPlaying()).toBe(false);
  expect(rotator.style.transform).toBe('none');
  expect(last().light.opacity).toBe(0);
  pointer(card, 'pointerenter', 20, 70, 1, 'mouse');
  frame();
  expect(last()).toMatchObject({ isPlaying: true, isHovering: true });
  window.dispatchEvent(new Event('blur'));
  frame();
  expect(isPlaying()).toBe(false);
  expect(rotator.style.transform).toBe('none');
});

it('finishes the release spring when scrolling takes the input instead of snapping to identity', () => {
  const card = mount();
  pointer(card, 'pointerenter', 80, 30, 1, 'mouse');
  for (let i = 0; i < 60; i++) frame();
  document.dispatchEvent(new Event('scroll'));
  frame();
  expect(isPlaying()).toBe(false);
  expect(rotator.style.transform).toContain('matrix3d(');
  pointer(card, 'pointerenter', 20, 70, 1, 'mouse');
  for (let i = 0; i < 180; i++) frame();
  expect(isPlaying()).toBe(false);
  expect(rotator.style.transform).toBe('none');
});

it('renders a very short tap even when released before the measurement', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  pointer(window, 'pointerup');
  frame();
  frame();
  expect(rotator.style.transform).toContain('matrix3d(');
  for (let i = 0; i < 180; i++) frame();
  expect(rotator.style.transform).toBe('none');
});

it('ignores other pointers and returns after pointer cancellation', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  frame();
  frame();
  pointer(window, 'pointerup', 0, 0, 2);
  frame();
  expect(rotator.style.transform).toContain('matrix3d(');
  pointer(window, 'pointercancel');
  for (let i = 0; i < 180; i++) frame();
  expect(rotator.style.transform).toBe('none');
});

it('clears the pointer on blur, ancestor scroll and cleanup, including queued frames', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  frame();
  frame();
  window.dispatchEvent(new Event('blur'));
  frame();
  expect(rotator.style.transform).toBe('none');
  pointer(card, 'pointerdown');
  frame();
  frame();
  document.dispatchEvent(new Event('scroll'));
  for (let i = 0; i < 180; i++) frame();
  expect(rotator.style.transform).toBe('none');
  pointer(card, 'pointerdown');
  cleanup?.();
  cleanup = undefined;
  frame();
  frame();
  expect(rotator.style.cssText).toBe('');
});

it('installs no listeners when disabled', () => {
  const listener = jest.spyOn(window, 'addEventListener');
  mount(true);
  expect(listener).not.toHaveBeenCalled();
  expect(cleanup).toBeUndefined();
});

it('enters play at 150 ms, gives one haptic and ends on release', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  jest.advanceTimersByTime(149);
  expect(vibrate).not.toHaveBeenCalled();
  expect(isPlaying()).toBe(false);
  frame();
  expect(isPlaying()).toBe(true);
  expect(vibrate).toHaveBeenCalledTimes(1);
  pointer(window, 'pointermove', 50, 30);
  for (let i = 0; i < 60; i++) frame();
  expect(vibrate).toHaveBeenCalledTimes(1);
  pointer(window, 'pointerup');
  frame();
  expect(isPlaying()).toBe(false);
});

it('keeps glow invisible through a short tap and its entire settling tail', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  for (let i = 0; i < 6; i++) frame();
  expect(last().light.opacity).toBe(0);
  pointer(window, 'pointerup');

  for (let i = 0; i < 180; i++) {
    frame();
    expect(last().light.opacity).toBe(0);
  }

  expect(vibrate).not.toHaveBeenCalled();
});

it('cancels the hold candidate after more than 12 px before recognition', () => {
  const card = mount();
  pointer(card, 'pointerdown', 50, 50);
  pointer(window, 'pointermove', 63, 50);
  for (let i = 0; i < 20; i++) frame();
  expect(isPlaying()).toBe(false);
  expect(vibrate).not.toHaveBeenCalled();
});

it.each(['button', 'a', 'input', 'span'])('preserves interactive descendants: %s', (tag) => {
  const card = mount();
  const control = document.createElement(tag);
  if (tag === 'span') control.setAttribute('role', 'button');
  card.append(control);
  pointer(control, 'pointerdown');
  for (let i = 0; i < 20; i++) frame();
  expect(isPlaying()).toBe(false);
  expect(vibrate).not.toHaveBeenCalled();
});

function touch(target: HTMLElement, type: string) {
  const event = new Event(type, { bubbles: true, cancelable: true });

  Object.assign(event, {
    touches: [{ identifier: 8, clientX: 60, clientY: 40 }],
    changedTouches: [{ identifier: 8, clientX: 60, clientY: 40 }],
  });

  target.dispatchEvent(event);

  return event;
}

it('keeps touch glow and movement when capture transfers from the touched child to the card', () => {
  const card = mount();
  const artwork = document.createElement('div');
  card.append(artwork);

  let hasCapture = false;

  Object.assign(card, {
    setPointerCapture: () => { hasCapture = true; },
    hasPointerCapture: () => hasCapture,
    releasePointerCapture: () => { hasCapture = false; },
  });

  pointer(artwork, 'pointerdown', 60, 40);
  touch(artwork, 'touchstart');
  for (let i = 0; i < 12; i++) frame();

  // In Safari the touched child holds the pointer capture first. Moving it to the card fires
  // `lostpointercapture` on the child, which bubbles up before the next moves arrive.
  pointer(artwork, 'lostpointercapture', 60, 40);
  expect(touch(artwork, 'touchmove').defaultPrevented).toBe(true);
  pointer(window, 'pointermove', 80, 30);
  for (let i = 0; i < 60; i++) frame();

  const held = last();
  expect(held.isPlaying).toBe(true);
  expect(held.light.opacity).toBeCloseTo(1);
  expect(held.pointer![0]).toBeCloseTo(0.6);
  expect(held.pointer![1]).toBeCloseTo(-0.4);
  hasCapture = false;
  pointer(card, 'lostpointercapture', 80, 30);
  for (let i = 0; i < 300; i++) frame();
  expect(last()).toMatchObject({ isPlaying: false, light: { opacity: 0 } });
});

it('locks touch and wheel only during play without changing ancestor layout', () => {
  const card = mount();
  const parent = document.createElement('div');
  parent.style.cssText = 'overflow:auto;height:400px;padding-top:12px';
  parent.append(card);

  const original = parent.style.cssText;
  pointer(card, 'pointerdown', 60, 40);
  touch(card, 'touchstart');
  expect(touch(card, 'touchmove').defaultPrevented).toBe(false);
  for (let i = 0; i < 12; i++) frame();
  expect(touch(card, 'touchmove').defaultPrevented).toBe(true);

  const wheel = new WheelEvent('wheel', { cancelable: true, deltaY: 100 });
  window.dispatchEvent(wheel);
  expect(wheel.defaultPrevented).toBe(true);
  expect(parent.style.cssText).toBe(original);
  pointer(window, 'pointerup');
  expect(touch(card, 'touchmove').defaultPrevented).toBe(false);

  const nextWheel = new WheelEvent('wheel', { cancelable: true, deltaY: 100 });
  window.dispatchEvent(nextWheel);
  expect(nextWheel.defaultPrevented).toBe(false);
});

it('suppresses the click following play and preserves a subsequent tap and keyboard activation', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  for (let i = 0; i < 12; i++) frame();
  pointer(window, 'pointerup');

  const click = new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 });
  card.dispatchEvent(click);
  expect(click.defaultPrevented).toBe(true);
  pointer(card, 'pointerdown');
  pointer(window, 'pointerup');

  const next = new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 });
  card.dispatchEvent(next);
  expect(next.defaultPrevented).toBe(false);

  const keyboard = new MouseEvent('click', { bubbles: true, cancelable: true, detail: 0 });
  card.dispatchEvent(keyboard);
  expect(keyboard.defaultPrevented).toBe(false);
});

it('restores a held surface on blur and cleanup, and cancels pending recognition', () => {
  const card = mount();
  pointer(card, 'pointerdown');
  for (let i = 0; i < 55; i++) frame();
  expect(last().light.opacity).toBeCloseTo(1);
  window.dispatchEvent(new Event('blur'));
  frame();
  expect(isPlaying()).toBe(false);
  expect(last().light.opacity).toBe(0);
  pointer(card, 'pointerdown');
  cleanup?.();
  cleanup = undefined;
  jest.advanceTimersByTime(1000);
  frame();
  expect(isPlaying()).toBe(false);
  expect(rotator.style.cssText).toBe('');
});

it('lets a control that allows play own the hold and tracks its pointer without a touch observer', () => {
  const card = mount();
  const balance = document.createElement('span');
  balance.setAttribute('role', 'button');
  balance.setAttribute('data-card-play-allowed', 'true');
  card.append(balance);
  pointer(balance, 'pointerdown', 80, 30);
  for (let i = 0; i < 10; i++) frame();
  expect(isPlaying()).toBe(true);
  expect(last().pointer![0]).toBeCloseTo(0.6);
  expect(last().pointer![1]).toBeCloseTo(-0.4);
  pointer(window, 'pointermove', 60, 40);
  frame();
  frame();
  expect(last().pointer![0]).toBeCloseTo(0.2);
  expect(last().pointer![1]).toBeCloseTo(-0.2);
  pointer(window, 'pointerup', 60, 40);

  const click = new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 });
  balance.dispatchEvent(click);
  expect(click.defaultPrevented).toBe(true);
  frame();
  expect(isPlaying()).toBe(false);
});

it('settles only the transform after scrolling takes the input, without publishing light on each frame', () => {
  const card = mount();
  pointer(card, 'pointerenter', 90, 10, 1, 'mouse');
  for (let i = 0; i < 12; i++) frame();

  const before = rotator.style.transform;
  document.dispatchEvent(new Event('scroll'));
  expect(rotator.style.transform).toBe(before);
  frame();

  const calls = receive.mock.calls.length;
  for (let i = 0; i < 120; i++) frame();
  expect(receive).toHaveBeenCalledTimes(calls);
  expect(rotator.style.transform).toBe('none');
  expect(measures).toHaveLength(0);
});
