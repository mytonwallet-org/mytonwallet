import { useEffect } from '../lib/teact/teact';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import * as windowEnvironment from '../util/windowEnvironment';
import useCardTilt from './useCardTilt';

jest.mock('../lib/teact/teact', () => ({ useEffect: jest.fn() }));
jest.mock('../lib/fasterdom/fasterdom', () => ({ requestMeasure: jest.fn(), requestMutation: jest.fn() }));
jest.mock('../util/windowEnvironment', () => ({ __esModule: true, IS_TOUCH_ENV: false }));

afterEach(() => {
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

it.each([false, true])('uses only pointer input and removes listeners (touch: %s)', (isTouchEnvironment) => {
  Object.assign(windowEnvironment, { IS_TOUCH_ENV: isTouchEnvironment });
  const card = document.createElement('div');
  const addCardListener = jest.spyOn(card, 'addEventListener');
  const removeCardListener = jest.spyOn(card, 'removeEventListener');
  const addWindowListener = jest.spyOn(window, 'addEventListener');

  useCardTilt({ cardRef: { current: card } });
  const cleanup = jest.mocked(useEffect).mock.calls[0][0]();

  const events = isTouchEnvironment
    ? ['touchstart', 'touchmove', 'touchend', 'touchcancel']
    : ['mousemove', 'mouseleave'];
  expect(addCardListener.mock.calls.map(([event]) => event)).toEqual(events);
  expect(addWindowListener).not.toHaveBeenCalled();

  card.style.setProperty('--card-pointer-x', '0.8');
  card.style.setProperty('--card-pointer-y', '0.2');
  card.style.setProperty('--card-glow-opacity', '1');
  card.style.setProperty('--card-press', '1');
  cleanup?.();
  jest.mocked(requestMutation).mock.calls[0][0]();
  expect(card.style.cssText).toBe('');
  for (const [event, listener] of addCardListener.mock.calls) {
    expect(removeCardListener).toHaveBeenCalledWith(event, listener);
  }

  addCardListener.mockClear();
  useCardTilt({ cardRef: { current: card }, isDisabled: true });
  expect(jest.mocked(useEffect).mock.calls[1][0]()).toBeUndefined();
  expect(addCardListener).not.toHaveBeenCalled();
});

it.each([false, true])('reports a held or hovered card through `--card-press` (touch: %s)', (isTouchEnvironment) => {
  Object.assign(windowEnvironment, { IS_TOUCH_ENV: isTouchEnvironment });
  const card = document.createElement('div');
  jest.spyOn(card, 'getBoundingClientRect').mockReturnValue({
    left: 0, top: 0, width: 100, height: 100,
  } as DOMRect);
  const now = jest.spyOn(performance, 'now').mockReturnValue(0);

  useCardTilt({ cardRef: { current: card } });
  jest.mocked(useEffect).mock.calls[0][0]();

  if (isTouchEnvironment) {
    const touchStart = new Event('touchstart');
    Object.defineProperty(touchStart, 'touches', { value: [{ clientX: 80, clientY: 20 }] });
    card.dispatchEvent(touchStart);
  } else {
    card.dispatchEvent(new MouseEvent('mousemove', { clientX: 80, clientY: 20 }));
  }
  // The pointer measurement is scheduled before the animation frame
  jest.mocked(requestMeasure).mock.calls[0][0]();

  function runFrame(timeMs: number) {
    now.mockReturnValue(timeMs);
    jest.mocked(requestMeasure).mock.calls.at(-1)![0]();
    jest.mocked(requestMutation).mock.calls.at(-1)![0]();
  }

  runFrame(100);
  expect(card.style.getPropertyValue('--card-press')).toBe('1');
  expect(Number(card.style.getPropertyValue('--card-pointer-x'))).toBeGreaterThan(0.5);

  card.dispatchEvent(new Event(isTouchEnvironment ? 'touchend' : 'mouseleave'));
  runFrame(200);
  expect(card.style.getPropertyValue('--card-press')).toBe('0');
});
