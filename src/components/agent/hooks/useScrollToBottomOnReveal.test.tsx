import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import { pause } from '../../../util/schedulers';
import useScrollToBottomOnReveal from './useScrollToBottomOnReveal';

let latestProgressHandler: NoneToVoidFunction | undefined;

describe('useScrollToBottomOnReveal', () => {
  let root: HTMLDivElement;
  let isAtBottomRef: React.RefObject<boolean>;
  let scrollToBottom: jest.Mock;
  let pendingFrame: FrameRequestCallback | undefined;
  let requestAnimationFrameSpy: jest.SpyInstance;
  let cancelAnimationFrameSpy: jest.SpyInstance;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    isAtBottomRef = { current: true };
    scrollToBottom = jest.fn();
    pendingFrame = undefined;
    latestProgressHandler = undefined;
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  it('coalesces progress and follows only while the conversation is at the bottom', () => {
    renderHarness();
    captureAnimationFrame();

    latestProgressHandler!();
    latestProgressHandler!();

    expect(requestAnimationFrameSpy).toHaveBeenCalledTimes(1);
    pendingFrame!(16);
    expect(scrollToBottom).toHaveBeenCalledTimes(1);

    isAtBottomRef.current = false;
    latestProgressHandler!();
    expect(requestAnimationFrameSpy).toHaveBeenCalledTimes(1);

    isAtBottomRef.current = true;
    latestProgressHandler!();
    expect(requestAnimationFrameSpy).toHaveBeenCalledTimes(2);
    pendingFrame!(32);
    expect(scrollToBottom).toHaveBeenCalledTimes(2);
  });

  it('rechecks user position before following and cancels a pending frame on unmount', async () => {
    renderHarness();
    await pause(20);
    captureAnimationFrame();

    latestProgressHandler!();
    isAtBottomRef.current = false;
    pendingFrame!(16);
    expect(scrollToBottom).not.toHaveBeenCalled();

    isAtBottomRef.current = true;
    latestProgressHandler!();
    TeactDOM.render(undefined, root);
    await pause(20);

    expect(cancelAnimationFrameSpy).toHaveBeenCalledWith(42);
  });

  function renderHarness() {
    TeactDOM.render(
      <Harness isAtBottomRef={isAtBottomRef} scrollToBottom={scrollToBottom} />,
      root,
    );
  }

  function captureAnimationFrame() {
    requestAnimationFrameSpy = jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      pendingFrame = callback;
      return 42;
    });
    cancelAnimationFrameSpy = jest.spyOn(window, 'cancelAnimationFrame').mockImplementation(jest.fn());
  }
});

function Harness({
  isAtBottomRef,
  scrollToBottom,
}: {
  isAtBottomRef: React.RefObject<boolean>;
  scrollToBottom: NoneToVoidFunction;
}) {
  latestProgressHandler = useScrollToBottomOnReveal(isAtBottomRef, scrollToBottom);
  return undefined;
}
