import React, { useRef, type VirtualElementComponent } from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import useAgentThreadSwipe from './useAgentThreadSwipe';

let mockCanAnimate = true;

jest.mock('../../util/windowEnvironment', () => ({
  ...jest.requireActual('../../util/windowEnvironment'),
  IS_TOUCH_ENV: true,
  REM: 16,
}));
jest.mock('../agent/helpers/getCanAnimate', () => ({
  __esModule: true,
  default: () => mockCanAnimate,
}));

const CLASS_NAMES = { swiped: 'swiped', armed: 'armed', actionShown: 'actionShown' };
// Three 50 px actions 10 px apart and from the edge, at the 16 px root font size of the tests
const OPEN_OFFSET = '190px';

describe('useAgentThreadSwipe', () => {
  let root: HTMLDivElement;
  let row: HTMLDivElement;

  function Harness() {
    const rowRef = useRef(row);
    useAgentThreadSwipe({
      rowRef, classNames: CLASS_NAMES, isRtl: false, onFullSwipe: jest.fn(),
    });

    return undefined;
  }

  beforeEach(() => {
    mockCanAnimate = true;
    root = document.createElement('div');
    row = document.createElement('div');
    row.setPointerCapture = jest.fn();
    document.body.append(root, row);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    row.remove();
  });

  it('slides the released row open over time', async () => {
    await renderAndSwipe();

    expect(row.style.getPropertyValue('--swipe-offset')).not.toBe(OPEN_OFFSET);
    await pause(600);
    expect(row.style.getPropertyValue('--swipe-offset')).toBe(OPEN_OFFSET);
  });

  it('puts the released row open at once without motion', async () => {
    mockCanAnimate = false;
    await renderAndSwipe();

    expect(row.style.getPropertyValue('--swipe-offset')).toBe(OPEN_OFFSET);
  });

  // A swipe toward the leading edge past half the open distance, let go 20 ms before the check
  async function renderAndSwipe() {
    TeactDOM.render(React.createElement(Harness, {}) as VirtualElementComponent, root);
    await pause(20);

    firePointer(row, 'pointerdown', 300);
    firePointer(row, 'pointermove', 280);
    firePointer(row, 'pointermove', 160);
    await pause(20);
    firePointer(row, 'pointerup', 160);
    await pause(20);
  }
});

function firePointer(element: HTMLElement, type: string, clientX: number) {
  const event = new MouseEvent(type, { bubbles: true, clientX, clientY: 10 });
  Object.defineProperties(event, {
    pointerType: { value: 'touch' },
    pointerId: { value: 1 },
  });
  element.dispatchEvent(event);
}
