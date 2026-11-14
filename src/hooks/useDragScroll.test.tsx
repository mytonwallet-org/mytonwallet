import React, { useRef } from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import animateHorizontalScroll from '../util/animateHorizontalScroll';
import useDragScroll from './useDragScroll';

jest.mock('../util/animateHorizontalScroll', () => ({
  __esModule: true,
  default: jest.fn(() => Promise.resolve()),
}));

type DragOptions = Omit<Parameters<typeof useDragScroll>[0], 'containerRef'>;

let root: HTMLDivElement;
let container: HTMLDivElement;

function Probe(options: DragOptions) {
  const containerRef = useRef<HTMLDivElement>();

  useDragScroll({ containerRef, ...options });

  return <div ref={containerRef} data-probe />;
}

beforeEach(() => {
  jest.useFakeTimers();
  jest.mocked(animateHorizontalScroll).mockClear();
  root = document.createElement('div');
  document.body.append(root);
});

afterEach(async () => {
  window.dispatchEvent(new Event('click'));
  TeactDOM.render(undefined, root);
  await jest.advanceTimersByTimeAsync(50);
  root.remove();
  jest.useRealTimers();
});

async function renderProbe(options: DragOptions = {}) {
  TeactDOM.render(<Probe {...options} />, root);
  await jest.advanceTimersByTimeAsync(50);
  container = root.querySelector('[data-probe]')!;
}

function dispatchMouse(type: string, target: EventTarget, pageX: number, buttons = 1) {
  const event = new MouseEvent(type, { bubbles: true, button: 0, buttons });

  Object.defineProperty(event, 'pageX', { value: pageX });
  target.dispatchEvent(event);
}

it('does not start a drag below the given threshold', async () => {
  const onDragStart = jest.fn();

  await renderProbe({ dragThreshold: 12, onDragStart });
  dispatchMouse('mousedown', container, 100);
  dispatchMouse('mousemove', window, 90);

  expect(onDragStart).not.toHaveBeenCalled();

  dispatchMouse('mousemove', window, 80);

  expect(onDragStart).toHaveBeenCalledTimes(1);
});

it('keeps the scroll position within the given bounds', async () => {
  await renderProbe({ getScrollBounds: () => [0, 308] });
  dispatchMouse('mousedown', container, 1000);
  dispatchMouse('mousemove', window, 0);
  await jest.advanceTimersByTimeAsync(50);

  expect(container.scrollLeft).toBe(308);
});

it('starts from the position the container has when the drag begins', async () => {
  await renderProbe();
  dispatchMouse('mousedown', container, 200);
  container.scrollLeft = 50;
  dispatchMouse('mousemove', window, 190);
  await jest.advanceTimersByTimeAsync(50);

  expect(container.scrollLeft).toBe(60);
});

it('reports the release velocity instead of running its own momentum', async () => {
  const onDragEnd = jest.fn();

  await renderProbe({ onDragEnd });
  dispatchMouse('mousedown', container, 200);
  jest.advanceTimersByTime(10);
  dispatchMouse('mousemove', window, 100);
  jest.advanceTimersByTime(10);
  dispatchMouse('mousemove', window, 80);
  dispatchMouse('mouseup', window, 80);
  await jest.advanceTimersByTimeAsync(50);

  expect(onDragEnd).toHaveBeenCalledWith(-6);
  expect(animateHorizontalScroll).not.toHaveBeenCalled();
});

it('applies the last move before reporting the release', async () => {
  let releasedAt: number | undefined;

  await renderProbe({
    onDragEnd: () => {
      releasedAt = container.scrollLeft;
    },
  });
  container.scrollLeft = 300;
  dispatchMouse('mousedown', container, 300);
  dispatchMouse('mousemove', window, 200);
  await jest.advanceTimersByTimeAsync(50);
  dispatchMouse('mousemove', window, 100);
  dispatchMouse('mouseup', window, 100);

  expect(releasedAt).toBe(500);
});

it('keeps the position that the release callback sets', async () => {
  await renderProbe({
    onDragEnd: () => {
      container.scrollLeft = 0;
    },
  });
  container.scrollLeft = 300;
  dispatchMouse('mousedown', container, 300);
  dispatchMouse('mousemove', window, 200);
  dispatchMouse('mouseup', window, 200);
  await jest.advanceTimersByTimeAsync(50);

  expect(container.scrollLeft).toBe(0);
});

it('reports zero velocity when the pointer rests before the release', async () => {
  const onDragEnd = jest.fn();

  await renderProbe({ onDragEnd });
  dispatchMouse('mousedown', container, 200);
  jest.advanceTimersByTime(10);
  dispatchMouse('mousemove', window, 100);
  jest.advanceTimersByTime(300);
  dispatchMouse('mouseup', window, 100);

  expect(onDragEnd).toHaveBeenCalledWith(0);
});

it('keeps its own momentum without `onDragEnd`', async () => {
  await renderProbe();
  dispatchMouse('mousedown', container, 200);
  jest.advanceTimersByTime(10);
  dispatchMouse('mousemove', window, 100);
  dispatchMouse('mouseup', window, 100);
  await jest.advanceTimersByTimeAsync(50);

  expect(animateHorizontalScroll).toHaveBeenCalledTimes(1);
});

it('finishes the drag when the pointer returns with the button released', async () => {
  const onDragEnd = jest.fn();

  await renderProbe({ onDragEnd });
  dispatchMouse('mousedown', container, 200);
  dispatchMouse('mousemove', window, 100);
  await jest.advanceTimersByTimeAsync(50);
  dispatchMouse('mousemove', window, 50, 0);
  await jest.advanceTimersByTimeAsync(50);

  expect(onDragEnd).toHaveBeenCalledTimes(1);
  expect(container.scrollLeft).toBe(100);
});

it('does not start a drag after the button is released outside the window', async () => {
  const onDragStart = jest.fn();

  await renderProbe({ onDragStart });
  dispatchMouse('mousedown', container, 200);
  dispatchMouse('mousemove', window, 100, 0);
  dispatchMouse('mousemove', window, 50);

  expect(onDragStart).not.toHaveBeenCalled();
});

it('cancels only the click that comes with the release', async () => {
  const onClick = jest.fn();

  await renderProbe({ onDragEnd: jest.fn() });
  container.addEventListener('click', onClick);
  dispatchMouse('mousedown', container, 200);
  dispatchMouse('mousemove', window, 100);
  dispatchMouse('mouseup', window, 100);
  container.click();

  expect(onClick).not.toHaveBeenCalled();

  dispatchMouse('mousedown', container, 200);
  dispatchMouse('mousemove', window, 100);
  dispatchMouse('mousemove', window, 100, 0);
  await jest.advanceTimersByTimeAsync(0);
  container.click();

  expect(onClick).toHaveBeenCalledTimes(1);
});

it('finishes the drag when the window loses focus', async () => {
  const onDragEnd = jest.fn();

  await renderProbe({ onDragEnd });
  dispatchMouse('mousedown', container, 200);
  dispatchMouse('mousemove', window, 100);
  window.dispatchEvent(new Event('blur'));

  expect(onDragEnd).toHaveBeenCalledTimes(1);

  dispatchMouse('mousemove', window, 50);
  await jest.advanceTimersByTimeAsync(50);

  expect(container.scrollLeft).toBe(100);
});
