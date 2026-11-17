import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';
import { getActions } from '../../../global';

import type { PerpsTradeState } from '../../../global/types';

import { pause } from '../../../util/schedulers';
import usePerpsTradeQuotes from './usePerpsTradeQuotes';

jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getActions: jest.fn(),
}));

const TRADE = {
  id: 'trade-1',
  kind: 'open',
  step: 'form',
  amount: '1000',
  error: 'PerpsInsufficientUsdc',
} as PerpsTradeState;

const loadPerpsTradePreview = jest.fn();

let root: HTMLDivElement;

function TradeQuotes({ trade = TRADE, usdcBalance = 0n }: { trade?: PerpsTradeState; usdcBalance?: bigint }) {
  usePerpsTradeQuotes(trade, true, usdcBalance, 0n);

  return undefined;
}

beforeEach(() => {
  jest.mocked(getActions).mockReturnValue({
    loadPerpsTradePreview,
    loadPerpsFundingRequirements: jest.fn(),
  } as unknown as ReturnType<typeof getActions>);
  loadPerpsTradePreview.mockClear();
  // The estimate waits while the window is in the background, which jsdom reports until it gets focus
  window.dispatchEvent(new Event('focus'));
  root = document.createElement('div');
  document.body.appendChild(root);
});

afterEach(() => {
  jest.useRealTimers();
  TeactDOM.render(undefined, root);
  root.remove();
});

describe('usePerpsTradeQuotes', () => {
  it('estimates again when the missing funds arrive, since the lack of them stops the refresh', async () => {
    TeactDOM.render(<TradeQuotes usdcBalance={0n} />, root);
    await pause(400);
    loadPerpsTradePreview.mockClear();

    TeactDOM.render(<TradeQuotes usdcBalance={2_000_000_000n} />, root);
    await pause(400);

    expect(loadPerpsTradePreview).toHaveBeenCalledTimes(1);
  });

  it('does not replace a running estimate with a refresh, and refreshes after it ends', async () => {
    jest.useFakeTimers();
    const idleTrade = { ...TRADE, error: undefined };

    TeactDOM.render(<TradeQuotes trade={{ ...idleTrade, isPreviewLoading: true }} />, root);
    await jest.advanceTimersByTimeAsync(400);
    loadPerpsTradePreview.mockClear();

    await jest.advanceTimersByTimeAsync(25_000);
    expect(loadPerpsTradePreview).not.toHaveBeenCalled();

    TeactDOM.render(<TradeQuotes trade={idleTrade} />, root);
    await jest.advanceTimersByTimeAsync(10_500);
    expect(loadPerpsTradePreview).toHaveBeenCalledTimes(1);
  });
});
