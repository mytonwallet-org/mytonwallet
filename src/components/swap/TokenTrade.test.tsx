// Imports schedule layout work, so they must share the test clock.
import '../../../tests/initFakeTimers';

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { GlobalState, UserSwapToken } from '../../global/types';
import { SwapInputSource, SwapState, SwapType } from '../../global/types';

import { ETH, ETH_USDT_MAINNET } from '../../config';
import { INITIAL_STATE } from '../../global/initialState';
import { fromDecimal, toDecimal } from '../../util/decimals';

import useOffRampMaxAmount from './hooks/useOffRampMaxAmount';

import RichNumberInput from '../ui/RichNumberInput';
import SwapSubmitButton from './components/SwapSubmitButton';
import TokenTrade from './TokenTrade';

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
  default: () => Object.assign((key: string, values?: Record<string, string>) => (
    (key === '$swap_better_rate_minimum' ? 'Better rate is available starting from %value%.' : key)
      .replace(/%(\w+)%/g, (placeholder, name: string) => values?.[name] ?? placeholder)
  ), { code: 'en', isRtl: false }),
}));
jest.mock('./hooks/useOffRampMaxAmount', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('./hooks/useSwapEstimatePolling', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./components/SwapSubmitButton', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('../common/AccountSwitcherPill', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../common/FiatCurrencyIcon', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../common/TokenIcon', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Button', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/FeeLine', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/Modal', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../ui/RichNumberInput', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./TokenTradeMenu', () => ({ __esModule: true, default: () => undefined }));
jest.mock('./TokenTradeSlippageModal', () => ({ __esModule: true, default: () => undefined }));

const TokenTradeWithState = TokenTrade as unknown as (props: Record<string, unknown>) => ReturnType<typeof TokenTrade>;

const BALANCE = fromDecimal('24.12', ETH.decimals);
const CARD_MAX = BALANCE - fromDecimal('0.00001', ETH.decimals);
const TOKENS = [
  { ...ETH, amount: BALANCE, priceUsd: 2267.93, isPopular: true },
  { ...ETH_USDT_MAINNET, amount: 0n, isPopular: true },
] as unknown as UserSwapToken[];

describe('TokenTrade selling for a card', () => {
  let root: HTMLDivElement;

  beforeAll(async () => {
    await import('../../../tests/initGlobal');
  });

  afterAll(() => {
    jest.useRealTimers();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    Object.keys(mockActions).forEach((name) => delete mockActions[name]);
    jest.mocked(useOffRampMaxAmount).mockReturnValue({ amount: CARD_MAX, isLoading: false });
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await jest.runAllTimersAsync();
    root.remove();
  });

  it('cuts 100% chosen for a token down to the card maximum instead of reporting a short balance', async () => {
    await renderTrade({ tradeAmount: toDecimal(BALANCE, ETH.decimals), isMaxAmount: true });

    const cardMaxAmount = toDecimal(CARD_MAX, ETH.decimals);
    expect(mockActions.setTradeAmount).toHaveBeenCalledWith({ amount: cardMaxAmount, isMaxAmount: true });
    expect(jest.mocked(SwapSubmitButton).mock.calls.map(([props]) => props.errorText)).not.toContain(
      'Insufficient Balance',
    );
    expect(getButtonProps()).toMatchObject({ errorText: undefined, canSubmit: true, isEstimating: false });

    root.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(mockActions.openOffRampWidgetModal).toHaveBeenCalledWith({
      chain: ETH.chain,
      currency: 'EUR',
      amount: cardMaxAmount,
    });

    mockActions.setTradeAmount.mockClear();
    await renderTrade({ tradeAmount: cardMaxAmount, isMaxAmount: true });

    expect(mockActions.setTradeAmount).not.toHaveBeenCalled();
  });

  it('keeps an amount typed over the card maximum chosen by 100%', async () => {
    await renderTrade({
      tradeAmount: toDecimal(CARD_MAX, ETH.decimals),
      isMaxAmount: true,
      isTradeAmountInToken: true,
    });

    jest.mocked(RichNumberInput).mock.calls.at(-1)![0].onChange!('10');
    await jest.advanceTimersByTimeAsync(100);

    expect(mockActions.setTradeAmount).not.toHaveBeenCalled();
    expect(getButtonProps()).toMatchObject({ errorText: undefined, canSubmit: true });

    await jest.advanceTimersByTimeAsync(500);

    expect(mockActions.setTradeAmount).toHaveBeenCalledTimes(1);
    expect(mockActions.setTradeAmount).toHaveBeenCalledWith({ amount: '10' });
  });

  it('holds the submission while the card maximum is unknown', async () => {
    jest.mocked(useOffRampMaxAmount).mockReturnValue({ isLoading: true });
    await renderTrade({ tradeAmount: toDecimal(BALANCE, ETH.decimals), isMaxAmount: true });

    expect(mockActions.setTradeAmount).not.toHaveBeenCalled();
    expect(getButtonProps()).toMatchObject({ errorText: undefined, canSubmit: false, isEstimating: true });
  });

  it.each([
    [{ type: 'betterRate', additionalAmount: '0.01', symbol: 'ETH' },
      'Better rate is available if you add 0.01 ETH for network fee.'],
    [{ type: 'betterRateMinimum', minimumAmount: '30.000001', symbol: 'ETH' },
      'Better rate is available starting from 30.000001 ETH.'],
  ] as const)('shows %j on a successful swap quote and removes it when the quote changes', async (hint, text) => {
    const swap = { tradeCardCurrency: undefined, tradeAmount: '1', amountIn: '1', amountOut: '2' };
    await renderTrade({ ...swap, swapQuoteHint: hint });
    expect(root.textContent).toContain(text);

    await renderTrade(swap);
    expect(root.textContent).not.toContain(text);
  });

  it('keeps a typed amount above the card maximum as a short balance', async () => {
    await renderTrade({ tradeAmount: toDecimal(BALANCE, ETH.decimals), isMaxAmount: false });

    expect(mockActions.setTradeAmount).not.toHaveBeenCalled();
    expect(getButtonProps()).toMatchObject({ errorText: 'Insufficient Balance', canSubmit: false });
  });

  it('marks 100% of the card maximum as the maximum, for a token chosen later to recount it', async () => {
    await renderTrade({});

    getPercentButton('100%').click();
    await jest.advanceTimersByTimeAsync(100);

    expect(mockActions.setTradeAmount).toHaveBeenCalledWith({
      amount: toDecimal(CARD_MAX, ETH.decimals),
      isMaxAmount: true,
    });

    getPercentButton('50%').click();
    await jest.advanceTimersByTimeAsync(100);

    expect(mockActions.setTradeAmount).toHaveBeenLastCalledWith({
      amount: toDecimal(CARD_MAX / 2n, ETH.decimals),
      isMaxAmount: false,
    });
  });

  async function renderTrade(swap: Partial<GlobalState['currentSwap']>) {
    const currentSwap: GlobalState['currentSwap'] = {
      state: SwapState.Initial,
      slippage: 5,
      tradeDirection: 'sell',
      tradeCardCurrency: 'EUR',
      tokenInSlug: ETH.slug,
      tokenOutSlug: ETH_USDT_MAINNET.slug,
      inputSource: SwapInputSource.In,
      ...swap,
    };

    TeactDOM.render(
      <TokenTradeWithState
        isActive
        currentSwap={currentSwap}
        tokens={TOKENS}
        swapType={SwapType.OnChain}
        baseCurrency="USD"
        currencyRates={INITIAL_STATE.currencyRates}
        cardCurrencies={['EUR']}
        accountId="0-mainnet"
      />,
      root,
    );
    await jest.advanceTimersByTimeAsync(100);
  }

  function getButtonProps() {
    return jest.mocked(SwapSubmitButton).mock.calls.at(-1)![0];
  }

  function getPercentButton(text: string) {
    return Array.from(root.querySelectorAll('button')).find((button) => button.textContent === text)!;
  }
});
