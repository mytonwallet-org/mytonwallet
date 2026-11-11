import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type { ApiHistoryList } from '../../../api/types';

import { pause } from '../../../util/schedulers';

import Plot from './Plot';

const PRICES: ApiHistoryList = [[1704067200, 200], [1704153600, 250], [1704240000, 300]];

const originalResizeObserver = globalThis.ResizeObserver;

// The plot draws nothing until it knows its width
beforeAll(() => {
  globalThis.ResizeObserver = class {
    constructor(private callback: ResizeObserverCallback) {}

    observe() {
      this.callback([{ contentRect: { width: 300 } } as ResizeObserverEntry], this as unknown as ResizeObserver);
    }

    unobserve() {}

    disconnect() {}
  } as unknown as typeof ResizeObserver;
});

afterAll(() => {
  globalThis.ResizeObserver = originalResizeObserver;
});

async function renderSeriesOpacities(backfillCount: number) {
  const root = document.createElement('div');
  document.body.appendChild(root);
  try {
    TeactDOM.render(
      <Plot prices={PRICES} backfillCount={backfillCount} selectedIndex={-1} onSelectIndex={() => {}} />,
      root,
    );
    await pause(50);
    const paths = Array.from(root.querySelectorAll('path'));
    expect(paths.length).toBeGreaterThan(0);

    return paths.map((path) => path.closest('[opacity]')?.getAttribute('opacity') ?? '1');
  } finally {
    TeactDOM.render(undefined, root);
    root.remove();
  }
}

it('draws a token-only series at full opacity', async () => {
  expect(new Set(await renderSeriesOpacities(0))).toEqual(new Set(['1']));
});

it('dims only the stock part of a series that has token prices', async () => {
  expect(new Set(await renderSeriesOpacities(1))).toEqual(new Set(['0.4', '1']));
});

it('dims the whole series when the token has no prices of its own', async () => {
  expect(new Set(await renderSeriesOpacities(PRICES.length))).toEqual(new Set(['0.4']));
});
