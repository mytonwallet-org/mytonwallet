import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { getAdjacentMediaId } from './helpers/getAdjacentMediaId';

import useControlsSignal from './hooks/useControlsSignal';

import Slides from './Slides';

jest.mock('../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../util/windowEnvironment'),
  IS_TOUCH_ENV: true,
}));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../../hooks/useHistoryBack', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('./MediaViewer.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
}));
jest.mock('./Media', () => ({
  __esModule: true,
  default: ({ mediaId }: { mediaId: string }) => <img data-media-id={mediaId} alt="" />,
}));

const MEDIA_IDS = ['first', 'second', 'third'];
// The window is 1024 px wide here, so a press within 128 px of an edge pages
const EDGE_X = 10;
const MIDDLE_X = 500;
// A press that does not count as a double one
const TAP_INTERVAL = 350;

describe('Slides of pictures on a touch screen', () => {
  let root: HTMLDivElement;
  const { getAreControlsVisible, setAreControlsVisible } = useControlsSignal();

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    setAreControlsVisible(true);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shades the side a press near an edge pages to, until the press ends or turns into a drag', async () => {
    renderSlides('second');
    await pause(20);
    const container = root.querySelector<HTMLElement>('.slides')!;
    const getShade = (side: 'prev' | 'next') => root.querySelector(`.edgePress_${side}`)!;

    dispatchTouch(container, 'touchstart', EDGE_X, 300);
    await pause(20);
    expect(getShade('prev').classList.contains('edgePress_visible')).toBe(true);
    expect(getShade('next').classList.contains('edgePress_visible')).toBe(false);
    dispatchTouch(container, 'touchend', EDGE_X, 300);
    await pause(20);
    expect(getShade('prev').classList.contains('edgePress_visible')).toBe(false);

    dispatchTouch(container, 'touchstart', 1014, 300);
    await pause(20);
    expect(getShade('next').classList.contains('edgePress_visible')).toBe(true);
    dispatchTouch(container, 'touchmove', 990, 300);
    await pause(20);
    expect(getShade('next').classList.contains('edgePress_visible')).toBe(false);
    dispatchTouch(container, 'touchend', 990, 300);

    dispatchTouch(container, 'touchstart', MIDDLE_X, 300);
    await pause(20);
    expect(root.querySelector('.edgePress_visible')).toBeNull();
    dispatchTouch(container, 'touchend', MIDDLE_X, 300);
  });

  it('shades no side that has no picture to page to', async () => {
    renderSlides('first');
    await pause(20);
    const container = root.querySelector<HTMLElement>('.slides')!;

    dispatchTouch(container, 'touchstart', EDGE_X, 300);
    await pause(20);
    expect(root.querySelector('.edgePress_visible')).toBeNull();
    dispatchTouch(container, 'touchend', EDGE_X, 300);
  });

  it('shows and hides the header and caption with a tap on the picture, as Telegram does', async () => {
    renderSlides('second');
    await pause(20);
    const container = root.querySelector<HTMLElement>('.slides')!;

    tap(container, MIDDLE_X, 300);
    expect(getAreControlsVisible()).toBe(false);
    await pause(TAP_INTERVAL);
    tap(container, MIDDLE_X, 300);
    expect(getAreControlsVisible()).toBe(true);
  });

  it('takes the header and caption away during a swipe down, and brings them back if it is let go', async () => {
    const onClose = jest.fn();
    renderSlides('second', onClose);
    await pause(20);
    const container = root.querySelector<HTMLElement>('.slides')!;

    dispatchTouch(container, 'touchstart', MIDDLE_X, 300);
    dispatchTouch(container, 'touchmove', MIDDLE_X, 330);
    expect(getAreControlsVisible()).toBe(false);
    dispatchTouch(container, 'touchend', MIDDLE_X, 330);
    expect(getAreControlsVisible()).toBe(true);
    expect(onClose).not.toHaveBeenCalled();

    dispatchTouch(container, 'touchstart', MIDDLE_X, 300);
    dispatchTouch(container, 'touchmove', MIDDLE_X, 420);
    dispatchTouch(container, 'touchend', MIDDLE_X, 420);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it.each([0.5, 2])('restores the header and caption when a swipe turns into a pinch at scale %s', async (scale) => {
    const onClose = jest.fn();
    renderSlides('second', onClose);
    await pause(20);
    const container = root.querySelector<HTMLElement>('.slides')!;

    dispatchTouch(container, 'touchstart', MIDDLE_X, 300);
    dispatchTouch(container, 'touchmove', MIDDLE_X, 330);
    expect(getAreControlsVisible()).toBe(false);
    dispatchTouch(container, 'touchstart', MIDDLE_X - 50, 330, MIDDLE_X + 50);
    dispatchTouch(container, 'touchmove', MIDDLE_X - 50 * scale, 330, MIDDLE_X + 50 * scale);
    dispatchTouch(container, 'touchend', MIDDLE_X, 330);

    expect(getAreControlsVisible()).toBe(true);
    expect(onClose).not.toHaveBeenCalled();
  });

  function renderSlides(mediaId: string, onClose = jest.fn()) {
    TeactDOM.render(
      <Slides
        isOpen
        mediaId={mediaId}
        isPicture
        getMediaId={(fromId, direction) => getAdjacentMediaId(MEDIA_IDS, fromId!, direction!)}
        selectMedia={jest.fn()}
        withAnimation={false}
        onClose={onClose}
      />,
      root,
    );
  }
});

function dispatchTouch(target: HTMLElement, type: string, x: number, y: number, secondX?: number) {
  const point = {
    clientX: x, clientY: y, pageX: x, pageY: y,
  };
  const points = secondX === undefined ? [point] : [point, { ...point, clientX: secondX, pageX: secondX }];
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, 'touches', { value: type === 'touchend' ? [] : points });
  Object.defineProperty(event, 'changedTouches', { value: points });
  target.dispatchEvent(event);
}

// A tap reaches the slides as the mouse events the browser makes of it
function tap(target: HTMLElement, x: number, y: number) {
  target.dispatchEvent(new MouseEvent('mousedown', {
    bubbles: true, cancelable: true, button: 0, clientX: x, clientY: y,
  }));
  document.dispatchEvent(new MouseEvent('mouseup', {
    bubbles: true, cancelable: true, button: 0, clientX: x, clientY: y,
  }));
}
