import React from '../lib/teact/teact';
import TeactDOM from '../lib/teact/teact-dom';

import { MINUTE } from '../util/dateFormat';
import useInactivityTimeout from './useInactivityTimeout';

const RENDER_DELAY = 50;

function Probe({ isActive, onTimeout }: { isActive?: boolean; onTimeout: NoneToVoidFunction }) {
  useInactivityTimeout(onTimeout, isActive);

  return <div />;
}

describe('useInactivityTimeout', () => {
  let root: HTMLDivElement;
  const onTimeout = jest.fn();

  async function render(isActive?: boolean) {
    TeactDOM.render(<Probe isActive={isActive} onTimeout={onTimeout} />, root);
    await jest.advanceTimersByTimeAsync(RENDER_DELAY);
  }

  async function unmount() {
    TeactDOM.render(undefined, root);
    await jest.advanceTimersByTimeAsync(RENDER_DELAY);
  }

  beforeEach(() => {
    jest.useFakeTimers();
    onTimeout.mockClear();
    root = document.createElement('div');
    document.body.append(root);
  });

  afterEach(async () => {
    await unmount();
    root.remove();
    jest.useRealTimers();
  });

  it('calls `onTimeout` once after 5 minutes without user input', async () => {
    await render(true);

    await jest.advanceTimersByTimeAsync(5 * MINUTE - 2 * RENDER_DELAY);
    expect(onTimeout).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(2 * RENDER_DELAY);
    expect(onTimeout).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(10 * MINUTE);
    expect(onTimeout).toHaveBeenCalledTimes(1);
  });

  it('restarts the countdown on user input', async () => {
    await render(true);

    await jest.advanceTimersByTimeAsync(4 * MINUTE);
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    await jest.advanceTimersByTimeAsync(4 * MINUTE);
    expect(onTimeout).not.toHaveBeenCalled();

    await jest.advanceTimersByTimeAsync(MINUTE);
    expect(onTimeout).toHaveBeenCalledTimes(1);
  });

  it('calls `onTimeout` when the page becomes visible after the deadline', async () => {
    await render(true);

    // A suspended page: the clock moves on while the timer does not fire
    jest.setSystemTime(Date.now() + 6 * MINUTE);
    document.dispatchEvent(new Event('visibilitychange'));
    expect(onTimeout).toHaveBeenCalledTimes(1);
  });

  it('calls `onTimeout` on user input that comes after the deadline', async () => {
    await render(true);

    // The system wakes from sleep: the page stays visible and the overdue timer has not fired yet
    jest.setSystemTime(Date.now() + 6 * MINUTE);
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onTimeout).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(10 * MINUTE);
    expect(onTimeout).toHaveBeenCalledTimes(1);
  });

  it('does not call `onTimeout` while `isActive` is false', async () => {
    await render();

    await jest.advanceTimersByTimeAsync(10 * MINUTE);
    expect(onTimeout).not.toHaveBeenCalled();
  });

  it('stops the countdown on unmount', async () => {
    await render(true);
    await unmount();

    // Teact detaches `useLastCallback` on unmount, so a leaked timer shows up only in the timer count
    expect(jest.getTimerCount()).toBe(0);
  });
});
