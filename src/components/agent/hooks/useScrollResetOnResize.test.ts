import React, { useRef, type VirtualElementComponent } from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import { pause } from '../../../util/schedulers';
import useScrollResetOnResize from './useScrollResetOnResize';

jest.mock('../../../hooks/useDeviceScreen', () => ({ useDeviceScreen: () => ({ isPortrait: true }) }));

describe('useScrollResetOnResize', () => {
  let root: HTMLDivElement;
  let list: HTMLDivElement;
  let scrollTop: number;
  let clientHeight: number;
  let viewport: EventTarget;
  let result: ReturnType<typeof useScrollResetOnResize>;

  function Harness() {
    const scrollRef = useRef(list);
    const isAtBottomRef = useRef(true);
    result = useScrollResetOnResize(scrollRef, isAtBottomRef);

    return undefined;
  }

  beforeEach(() => {
    root = document.createElement('div');
    list = document.createElement('div');
    scrollTop = 600;
    clientHeight = 400;
    Object.defineProperties(list, {
      scrollHeight: { configurable: true, value: 1000 },
      clientHeight: { configurable: true, get: () => clientHeight },
      // The list scrolls smoothly, so a new position does not land at once
      scrollTop: { configurable: true, get: () => scrollTop, set: jest.fn() },
    });
    viewport = new EventTarget();
    Object.defineProperty(window, 'visualViewport', { configurable: true, value: viewport });
    document.body.append(root, list);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    list.remove();
  });

  it('counts the smooth scroll to the end after the keyboard opens as its own until it lands', async () => {
    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    await pause(20);

    // The keyboard takes 300 px of the list, which scrolls down to keep its end in sight
    clientHeight = 100;
    viewport.dispatchEvent(new Event('resize'));
    await pause(20);

    scrollTop = 700;
    expect(result.getIsSnappingToBottom(list)).toBe(true);

    scrollTop = 900;
    expect(result.getIsSnappingToBottom(list)).toBe(false);
    scrollTop = 700;
    expect(result.getIsSnappingToBottom(list)).toBe(false);
  });

  it('counts a position further from the end than the last one as the user\'s', async () => {
    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    await pause(20);

    clientHeight = 100;
    viewport.dispatchEvent(new Event('resize'));
    await pause(20);

    scrollTop = 700;
    expect(result.getIsSnappingToBottom(list)).toBe(true);

    // PageUp takes the list up, and no pointer or wheel event tells about it
    scrollTop = 300;
    expect(result.getIsSnappingToBottom(list)).toBe(false);
    scrollTop = 500;
    expect(result.getIsSnappingToBottom(list)).toBe(false);
  });

  it('lets the user take the list over on the way', async () => {
    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    await pause(20);

    clientHeight = 100;
    viewport.dispatchEvent(new Event('resize'));
    await pause(20);
    scrollTop = 700;

    result.cancelSnapToBottom();
    expect(result.getIsSnappingToBottom(list)).toBe(false);
  });
});
