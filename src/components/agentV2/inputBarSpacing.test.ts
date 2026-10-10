import { updateAgentV2InputBarSpacing } from './inputBarSpacing';

jest.mock('../../lib/fasterdom/fasterdom', () => ({
  requestMeasure: (callback: NoneToVoidFunction) => callback(),
  requestMutation: (callback: NoneToVoidFunction) => callback(),
  requestForcedReflow: (callback: NoneToVoidFunction) => callback(),
}));

describe('Agent V2 input bar spacing', () => {
  let frameCallback: FrameRequestCallback | undefined;

  beforeEach(() => {
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      frameCallback = callback;
      return 1;
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
    frameCallback = undefined;
  });

  it('keeps a bottom-pinned conversation visible without smooth layout corrections', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 200 });
    const scrollTo = jest.fn(({ top }: ScrollToOptions) => {
      element.scrollTop = top ?? element.scrollTop;
    });
    Object.defineProperty(element, 'scrollTo', { configurable: true, value: scrollTo });
    document.body.appendChild(element);

    updateAgentV2InputBarSpacing(element, 132, true);
    frameCallback?.(0);
    element.remove();

    expect(element.style.getPropertyValue('--agent-input-bar-height')).toBe('132px');
    expect(element.scrollTop).toBe(300);
    expect(scrollTo).toHaveBeenNthCalledWith(1, { top: 300, behavior: 'instant' });
    expect(scrollTo).toHaveBeenNthCalledWith(2, { top: 300, behavior: 'instant' });
  });

  it('does not move a conversation that the user scrolled up', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 80 });

    updateAgentV2InputBarSpacing(element, 132, false);

    expect(element.scrollTop).toBe(80);
  });

  it('shares the input height with sibling overlays through the layout container', () => {
    const layout = document.createElement('div');
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 80 });
    layout.appendChild(element);

    updateAgentV2InputBarSpacing(element, 132, false, layout);

    expect(layout.style.getPropertyValue('--agent-input-bar-height')).toBe('132px');
  });

  it('does not infer bottom state from a large input height increase', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 150 });

    updateAgentV2InputBarSpacing(element, 120, false);

    expect(element.scrollTop).toBe(150);
  });

  it('does not re-snap after the user scrolls up before the next frame', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 200 });
    document.body.appendChild(element);
    updateAgentV2InputBarSpacing(element, 132, true);
    element.scrollTop = 120;

    frameCallback?.(0);

    expect(element.scrollTop).toBe(120);
    element.remove();
  });

  it('does not mutate a detached conversation on the next frame', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 200 });
    updateAgentV2InputBarSpacing(element, 132, true);
    element.scrollTop = 120;

    frameCallback?.(0);

    expect(element.scrollTop).toBe(120);
  });

  it('rechecks scroll ownership before applying a queued bottom snap', () => {
    const element = createScrollElement({ scrollHeight: 300, clientHeight: 100, scrollTop: 200 });
    let canStickToBottom = true;

    updateAgentV2InputBarSpacing(element, 132, () => canStickToBottom);
    canStickToBottom = false;
    element.scrollTop = 120;

    frameCallback?.(0);

    expect(element.scrollTop).toBe(120);
  });
});

function createScrollElement({
  scrollHeight, clientHeight, scrollTop,
}: { scrollHeight: number; clientHeight: number; scrollTop: number }) {
  const element = document.createElement('div');
  Object.defineProperties(element, {
    scrollHeight: { configurable: true, value: scrollHeight },
    clientHeight: { configurable: true, value: clientHeight },
    scrollTo: {
      configurable: true,
      value: ({ top }: ScrollToOptions) => {
        element.scrollTop = top ?? element.scrollTop;
      },
    },
  });
  element.scrollTop = scrollTop;
  return element;
}
