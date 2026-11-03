import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { GlobalState, UserSwapToken } from '../../global/types';
import { SwapInputSource, SwapState, SwapType } from '../../global/types';

import { ETH, ETH_USDT_MAINNET, TRC20_USDT_MAINNET } from '../../config';

import TokenSelector from '../common/TokenSelector';
import SwapModal from './SwapModal';

const mockActions: Record<string, jest.Mock> = {};

jest.mock('../../global', () => {
  const getActions = () => new Proxy(mockActions, {
    get: (actions, name: string) => (actions[name] ??= jest.fn()),
  });

  return {
    ...jest.requireActual('../../global'),
    getActions,
    withGlobal: () => (Component: unknown) => Component,
  };
});
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));
jest.mock('../ui/Modal', () => ({ __esModule: true, default: ({ children }: { children: unknown }) => children }));
jest.mock('../ui/Transition', () => ({
  __esModule: true,
  default: ({ children, activeKey }: { children: (...args: unknown[]) => unknown; activeKey: number }) => (
    children(true, false, activeKey)
  ),
}));
jest.mock('../common/TokenSelector', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('../common/AccountSwitcherPill', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../common/AccountSwitcherSlide', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../common/TransactionBanner', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/ModalHeader', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapBlockchain', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapComplete', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapInitial', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapMfaConfirm', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapPassword', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./SwapWaitTokens', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./TokenTrade', () => ({ __esModule: true, default: () => undefined }));

const TRON_USDT = { ...TRC20_USDT_MAINNET, amount: 0n, isPopular: true } as unknown as UserSwapToken;

describe('SwapModal picking the token to receive on the Sell screen', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    Object.keys(mockActions).forEach((name) => delete mockActions[name]);
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await jest.runAllTimersAsync();
    root.remove();
    jest.useRealTimers();
  });

  it('keeps 100% the maximum, so the new pair leaves room for its own fee', async () => {
    await renderPicker({ tradeAmount: '24.12', amountIn: '24.11964', isMaxAmount: true });

    jest.mocked(TokenSelector).mock.calls.at(-1)![0].onTokenSelect(TRON_USDT);

    expect(mockActions.setSwapTokenOut).toHaveBeenCalledWith({ tokenSlug: TRON_USDT.slug });
    expect(mockActions.setTradeAmount).toHaveBeenCalledWith({ amount: '24.12', isMaxAmount: true });
  });

  it('keeps a typed amount as it is', async () => {
    await renderPicker({ tradeAmount: '10', amountIn: '10', isMaxAmount: false });

    jest.mocked(TokenSelector).mock.calls.at(-1)![0].onTokenSelect(TRON_USDT);

    expect(mockActions.setTradeAmount).toHaveBeenCalledWith({ amount: '10', isMaxAmount: false });
  });

  async function renderPicker(swap: Partial<GlobalState['currentSwap']>) {
    const currentSwap: GlobalState['currentSwap'] = {
      state: SwapState.SelectTokenTo,
      slippage: 5,
      tradeDirection: 'sell',
      tokenInSlug: ETH.slug,
      tokenOutSlug: ETH_USDT_MAINNET.slug,
      inputSource: SwapInputSource.In,
      ...swap,
    };

    TeactDOM.render(
      <SwapModal
        currentSwap={currentSwap}
        swapType={SwapType.OnChain}
        swapRoute="dex"
        accountId="0-mainnet"
        tradeCardCurrencies={['EUR']}
      />,
      root,
    );
    await jest.advanceTimersByTimeAsync(100);
  }
});
