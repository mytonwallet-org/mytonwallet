import { getAgentBubbleMenuLayout, getAgentPointerMenuLayout } from './bubbleMenuLayout';

describe('getAgentPointerMenuLayout', () => {
  it('opens a right-clicked menu at the pointer, keeping clear of the pointer\'s line only', () => {
    const layout = getAgentPointerMenuLayout({ x: 240, y: 380 });

    expect(layout).toMatchObject({
      withPortal: true,
      doNotCoverTrigger: false,
      isCenteredHorizontally: false,
      topShiftY: 4,
      preferredPositionX: 'left',
      triggerRect: {
        left: 0, right: window.innerWidth, width: window.innerWidth, top: 380, bottom: 380, height: 0,
      },
    });
    expect(layout.deltaX).toBeUndefined();
  });

  it('hangs a long-pressed menu from the bubble, unlike a right-clicked one', () => {
    const bubbleRect = {
      left: 16, right: 300, top: 100, bottom: 500, width: 284, height: 400,
    } as DOMRect;

    expect(getAgentBubbleMenuLayout(bubbleRect, { x: 240, y: 380 }, false)).toMatchObject({
      doNotCoverTrigger: true,
      deltaX: 16 - 240,
      triggerRect: { top: 100, bottom: 500 },
    });
  });
});
