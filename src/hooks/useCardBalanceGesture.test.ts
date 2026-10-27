import { useUnmountCleanup } from '../lib/teact/teact';

import useCardBalanceGesture from './useCardBalanceGesture';

jest.mock('../lib/teact/teact', () => ({
  useMemo: (factory: () => unknown) => factory(),
  useUnmountCleanup: jest.fn(),
}));
jest.mock('./useLastCallback', () => ({ __esModule: true, default: (callback: any) => callback }));

beforeEach(() => jest.useFakeTimers());
afterEach(() => {
  jest.mocked(useUnmountCleanup).mock.calls.at(-1)?.[0]();
  jest.clearAllMocks();
  jest.useRealTimers();
});

function setup(isHidden = false) {
  const onMenu = jest.fn();
  const onToggle = jest.fn();
  const handlers = useCardBalanceGesture({ isHidden, onMenu, onToggle });

  return { handlers, onMenu, onToggle };
}

function down(handlers: ReturnType<typeof useCardBalanceGesture>, x = 10, pointerType = 'mouse') {
  handlers.onPointerDown(
    { pointerId: 1, pointerType, button: 0, clientX: x, clientY: 10 } as React.PointerEvent<HTMLElement>,
  );
}

function touchEnd() {
  const e = new Event('touchend', { cancelable: true });
  window.dispatchEvent(e);

  return e;
}

function pointer(type: string, x = 10) {
  const e = new Event(type);
  Object.assign(e, { pointerId: 1, clientX: x, clientY: 10 });
  window.dispatchEvent(e);
}

function click(handlers: ReturnType<typeof useCardBalanceGesture>) {
  const e = new MouseEvent('click', { detail: 1, cancelable: true });
  handlers.onClick(e as unknown as React.MouseEvent<HTMLElement>);

  return e;
}

it('toggles privacy on a tap whether the balance is hidden or revealed', () => {
  const revealed = setup();
  click(revealed.handlers);
  expect(revealed.onToggle).toHaveBeenCalledTimes(1);
  expect(revealed.onMenu).not.toHaveBeenCalled();

  const hidden = setup(true);
  click(hidden.handlers);
  expect(hidden.onToggle).toHaveBeenCalledTimes(1);
});

it('opens currency selection on a hold and consumes the following click', () => {
  const { handlers, onMenu, onToggle } = setup();
  down(handlers);
  jest.advanceTimersByTime(400);
  pointer('pointerup');
  expect(click(handlers).defaultPrevented).toBe(true);
  expect(onMenu).toHaveBeenCalledTimes(1);
  expect(onToggle).not.toHaveBeenCalled();
});

it('never opens currency selection for a concealed balance', () => {
  const { handlers, onMenu } = setup(true);
  down(handlers);
  jest.advanceTimersByTime(500);

  const e = new MouseEvent('contextmenu', { cancelable: true });
  handlers.onContextMenu(e as unknown as React.MouseEvent<HTMLElement>);
  expect(onMenu).not.toHaveBeenCalled();
  expect(e.defaultPrevented).toBe(true);
});

it('opens currency selection on context click without toggling privacy', () => {
  const { handlers, onMenu, onToggle } = setup();

  handlers.onContextMenu(new MouseEvent('contextmenu', { cancelable: true }) as unknown as
    React.MouseEvent<HTMLElement>);

  expect(onMenu).toHaveBeenCalledTimes(1);
  expect(onToggle).not.toHaveBeenCalled();
});

it('cancels a hold during a swipe and consumes the accidental release click', () => {
  const { handlers, onMenu, onToggle } = setup();
  down(handlers);
  pointer('pointermove', 30);
  jest.advanceTimersByTime(500);
  click(handlers);
  expect(onMenu).not.toHaveBeenCalled();
  expect(onToggle).not.toHaveBeenCalled();
});

it('toggles privacy from the keyboard', () => {
  const { handlers, onMenu, onToggle } = setup();
  handlers.onKeyDown(new KeyboardEvent('keydown', { key: 'Enter' }) as unknown as React.KeyboardEvent<HTMLElement>);
  handlers.onKeyDown(new KeyboardEvent('keydown', { key: ' ' }) as unknown as React.KeyboardEvent<HTMLElement>);
  expect(onToggle).toHaveBeenCalledTimes(2);
  expect(onMenu).not.toHaveBeenCalled();

  const repeated = new KeyboardEvent('keydown', { key: 'Enter', repeat: true, cancelable: true });
  handlers.onKeyDown(repeated as unknown as React.KeyboardEvent<HTMLElement>);
  expect(repeated.defaultPrevented).toBe(true);
  expect(onToggle).toHaveBeenCalledTimes(2);
});

it('cancels only the release of the touch that opened the menu, so its emulated mousedown cannot close it', () => {
  const { handlers, onMenu } = setup();
  down(handlers, 10, 'touch');
  jest.advanceTimersByTime(400);
  expect(onMenu).toHaveBeenCalledTimes(1);
  expect(touchEnd().defaultPrevented).toBe(true);
  expect(touchEnd().defaultPrevented).toBe(false);

  down(handlers);
  jest.advanceTimersByTime(400);
  expect(touchEnd().defaultPrevented).toBe(false);
});

it('cancels a pending hold on window blur and component unmount', () => {
  const { handlers, onMenu } = setup();
  down(handlers);
  window.dispatchEvent(new Event('blur'));
  jest.advanceTimersByTime(500);
  expect(onMenu).not.toHaveBeenCalled();
  down(handlers);
  jest.mocked(useUnmountCleanup).mock.calls.at(-1)![0]();
  jest.advanceTimersByTime(500);
  expect(onMenu).not.toHaveBeenCalled();
});
