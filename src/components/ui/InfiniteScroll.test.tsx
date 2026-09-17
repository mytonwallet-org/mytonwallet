import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { LoadMoreDirection } from '../../global/types';

import InfiniteScroll from './InfiniteScroll';

describe('InfiniteScroll', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await Promise.resolve();
    root.remove();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('keeps the wheel direction when restoring a virtualized viewport changes scroll coordinates', async () => {
    const onLoadMore = jest.fn();

    TeactDOM.render(
      <InfiniteScroll
        items={[1, 2]}
        itemSelector=".test-item"
        loadMoreStrategy="scrollDirection"
        preloadBackwards={0}
        sensitiveArea={800}
        onLoadMore={onLoadMore}
      >
        <div className="test-item">First</div>
        <div className="test-item">Last</div>
      </InfiniteScroll>,
      root,
    );
    await Promise.resolve();

    const container = root.firstElementChild as HTMLDivElement;
    const [firstItem, lastItem] = Array.from(container.querySelectorAll<HTMLElement>('.test-item'));
    let firstItemOffset = 100;

    Object.defineProperties(container, {
      scrollTop: { configurable: true, writable: true, value: 867 },
      scrollHeight: { configurable: true, value: 3000 },
      offsetHeight: { configurable: true, value: 900 },
    });
    mockItemGeometry(firstItem, () => firstItemOffset, container);
    mockItemGeometry(lastItem, () => 2900, container);

    dispatchScroll(container);
    await resetDebounce();

    firstItemOffset = 400;
    container.scrollTop = 400;
    dispatchWheel(container, 20);
    dispatchScroll(container);

    expect(onLoadMore).not.toHaveBeenCalled();
    await resetDebounce();

    container.scrollTop = 300;
    dispatchWheel(container, -20);
    dispatchScroll(container);

    expect(onLoadMore).toHaveBeenCalledTimes(1);
    expect(onLoadMore).toHaveBeenCalledWith({ direction: LoadMoreDirection.Forwards });
  });

  it.each([
    ['forwards restoration events when pagination follows scroll direction', 'scrollDirection', 1],
    ['keeps restoration events private when pagination follows anchor movement', 'anchorMovement', 0],
  ] as const)('%s', async (_title, loadMoreStrategy, expectedCalls) => {
    const onLoadMore = jest.fn();
    const onScroll = jest.fn();
    const renderList = (items: number[]) => TeactDOM.render(
      <InfiniteScroll
        items={items}
        itemSelector=".test-item"
        loadMoreStrategy={loadMoreStrategy}
        preloadBackwards={0}
        onLoadMore={onLoadMore}
        onScroll={onScroll}
      >
        <div className="test-item">First</div>
        <div className="test-item">Last</div>
      </InfiniteScroll>,
      root,
    );

    renderList([1, 2]);
    await Promise.resolve();

    const container = root.firstElementChild as HTMLDivElement;
    const [firstItem, lastItem] = Array.from(container.querySelectorAll<HTMLElement>('.test-item'));
    let firstItemOffset = 100;

    Object.defineProperties(container, {
      scrollTop: { configurable: true, writable: true, value: 100 },
      scrollHeight: { configurable: true, value: 3000 },
      offsetHeight: { configurable: true, value: 900 },
    });
    mockItemGeometry(firstItem, () => firstItemOffset, container);
    mockItemGeometry(lastItem, () => 2900, container);

    dispatchScroll(container);
    onScroll.mockClear();

    firstItemOffset = 400;
    renderList([0, 1, 2]);
    await flushFasterdom();
    dispatchScroll(container);

    expect(onScroll).toHaveBeenCalledTimes(expectedCalls);
  });
});

function dispatchScroll(container: HTMLDivElement) {
  container.dispatchEvent(new Event('scroll', { bubbles: true }));
}

function dispatchWheel(container: HTMLDivElement, deltaY: number) {
  container.dispatchEvent(new WheelEvent('wheel', { bubbles: true, deltaY }));
}

async function resetDebounce() {
  await jest.advanceTimersByTimeAsync(1001);
}

async function flushFasterdom() {
  await jest.advanceTimersByTimeAsync(36);
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function mockItemGeometry(
  element: HTMLElement,
  getOffsetTop: () => number,
  container: HTMLDivElement,
) {
  Object.defineProperties(element, {
    offsetTop: { configurable: true, get: getOffsetTop },
    offsetHeight: { configurable: true, value: 100 },
    getBoundingClientRect: {
      configurable: true,
      value: () => ({ top: getOffsetTop() - container.scrollTop }),
    },
  });
}
