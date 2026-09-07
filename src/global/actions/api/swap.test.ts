import type { GlobalState } from '../../types';
import type { SwapEstimateResult } from './swap';
import { SwapInputSource, SwapState } from '../../types';

import { MYCOIN_MAINNET, TONCOIN, TRX } from '../../../config';
import { getGlobal, setGlobal } from '../../index';
import { clearCurrentSwap, updateCurrentSwap } from '../../reducers';
import {
  buildSwapBuildRequest,
  estimateSwapConcurrently,
  shouldBlockUnsupportedNearIntentsMemo,
} from './swap';

describe('estimateSwapConcurrently', () => {
  beforeEach(() => {
    setGlobal(updateCurrentSwap(clearCurrentSwap(getGlobal()), {
      state: SwapState.Initial,
      isEstimating: false,
    }));
  });

  const estimationResultMock: SwapEstimateResult = {
    networkFee: '0.1',
    realNetworkFee: '0.05',
  };

  it.each([
    ['initial', SwapState.Initial],
    ['password', SwapState.Password],
    ['address input', SwapState.Blockchain],
  ])(
    'estimates visibly on the %p screen',
    async () => {
      const initialGlobal = updateCurrentSwap(getGlobal(), { isEstimating: true });
      setGlobal(initialGlobal);
      let estimateCallCount = 0;

      await estimateSwapConcurrently((argGlobal, shouldStop) => {
        expect(argGlobal).toEqual(getGlobal()); // The provided global should be up-to-date
        expect(getGlobal()).toEqual(initialGlobal); // The spinner should be kept
        expect(shouldStop()).toBe(false); // The `estimate` function shouldn't be asked to stop
        estimateCallCount++;
        return estimationResultMock;
      });

      expect(estimateCallCount).toBe(1);
      expect(getGlobal()).toEqual(updateCurrentSwap(initialGlobal, {
        ...estimationResultMock,
        isEstimating: false, // The spinner should disappear
      }));
    },
  );

  it('keeps the spinner, ignores the result and tells the `estimate` function to stop,'
    + ' if the form input changes during estimation', async () => {
    const input1 = {
      tokenInSlug: TONCOIN.slug,
      tokenOutSlug: TRX.slug,
      amountIn: '1',
      inputSource: SwapInputSource.In,
    } satisfies Partial<GlobalState['currentSwap']>;
    const input2 = {
      ...input1,
      tokenInSlug: TRX.slug,
      tokenOutSlug: TONCOIN.slug,
    } satisfies Partial<GlobalState['currentSwap']>;

    const initialGlobal = getGlobal();
    setGlobal(updateCurrentSwap(initialGlobal, input1));

    await estimateSwapConcurrently((_, shouldStop) => {
      setGlobal(updateCurrentSwap(getGlobal(), input2));
      expect(shouldStop()).toBe(true);
      return estimationResultMock;
    });

    expect(getGlobal()).toEqual(updateCurrentSwap(initialGlobal, {
      ...input2,
      isEstimating: true,
    }));
  });

  it('doesn\'t estimate and keeps the spinner if there is another estimation in progress', async () => {
    const initialGlobal = updateCurrentSwap(getGlobal(), { isEstimating: true });
    setGlobal(initialGlobal);

    await estimateSwapConcurrently(async () => {
      const estimateFn = jest.fn();

      await estimateSwapConcurrently(estimateFn);

      expect(estimateFn).not.toHaveBeenCalled();
      expect(getGlobal()).toEqual(initialGlobal);

      return estimationResultMock;
    });

    // The first estimation should reset the spinner (because the input hasn't changed)
    expect(getGlobal()).toEqual(updateCurrentSwap(initialGlobal, {
      ...estimationResultMock,
      isEstimating: false,
    }));
  });

  it('keeps the spinner if estimation has been rate-limited', async () => {
    const initialGlobal = updateCurrentSwap(getGlobal(), { isEstimating: true });
    setGlobal(initialGlobal);

    await estimateSwapConcurrently(() => 'rateLimited');

    expect(getGlobal()).toEqual(initialGlobal);
  });

  it('doesn\'t enable the spinner', async () => {
    const initialGlobal = getGlobal();

    await estimateSwapConcurrently((_global, shouldStop) => {
      expect(getGlobal()).toEqual(initialGlobal);
      expect(shouldStop()).toBe(false);
      return estimationResultMock;
    });

    expect(getGlobal()).toEqual(updateCurrentSwap(initialGlobal, estimationResultMock));
  });

  describe.each([
    ['password', SwapState.Password],
    ['address input', SwapState.Blockchain],
  ])('hidden estimation on the %p screen', (_stateName, state) => {
    it('doesn\'t start estimation', async () => {
      const initialGlobal = updateCurrentSwap(getGlobal(), { state });
      setGlobal(initialGlobal);
      const estimateFn = jest.fn();

      await estimateSwapConcurrently(estimateFn);

      expect(estimateFn).not.toHaveBeenCalled();
      expect(getGlobal()).toEqual(initialGlobal);
    });

    it('ignores the result and tells the `estimate` function to stop,'
      + ' if the estimation started before that screen', async () => {
      const initialGlobal = getGlobal();

      await estimateSwapConcurrently((_global, shouldStop) => {
        setGlobal(updateCurrentSwap(getGlobal(), { state }));
        expect(shouldStop()).toBe(true);
        return estimationResultMock;
      });

      expect(getGlobal()).toEqual(updateCurrentSwap(initialGlobal, { state }));
    });
  });
});

describe('shouldBlockUnsupportedNearIntentsMemo', () => {
  it('blocks Near Intents memo deposits for EVM-like source chains', () => {
    expect(shouldBlockUnsupportedNearIntentsMemo('near-intents', 'base', 'memo')).toBe(true);
    expect(shouldBlockUnsupportedNearIntentsMemo('near-intents', 'ethereum', 'memo')).toBe(true);
  });

  it('allows Near Intents memo deposits only for memo-capable wallet transfer chains', () => {
    expect(shouldBlockUnsupportedNearIntentsMemo('near-intents', 'ton', 'memo')).toBe(false);
    expect(shouldBlockUnsupportedNearIntentsMemo('near-intents', 'solana', 'memo')).toBe(false);
  });

  it('does not block memo-less Near Intents or non-Near CEX results', () => {
    expect(shouldBlockUnsupportedNearIntentsMemo('near-intents', 'base')).toBe(false);
    expect(shouldBlockUnsupportedNearIntentsMemo('changelly', 'base', 'memo')).toBe(false);
  });
});

describe('buildSwapBuildRequest', () => {
  const ACCOUNT_ADDRESS = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ';

  function makeGlobal(currentSwap: Partial<GlobalState['currentSwap']>): GlobalState {
    return {
      currentAccountId: 'acc',
      accounts: { byId: { acc: { byChain: { ton: { address: ACCOUNT_ADDRESS } } } } },
      byAccountId: { acc: {} },
      swapTokenInfo: {
        bySlug: {
          [TONCOIN.slug]: { slug: TONCOIN.slug, chain: 'ton', decimals: TONCOIN.decimals },
          [MYCOIN_MAINNET.slug]: {
            slug: MYCOIN_MAINNET.slug,
            chain: 'ton',
            decimals: MYCOIN_MAINNET.decimals,
            tokenAddress: MYCOIN_MAINNET.minterAddress,
          },
        },
      },
      currentSwap: {
        tokenInSlug: TONCOIN.slug,
        tokenOutSlug: MYCOIN_MAINNET.slug,
        amountIn: '10',
        amountOutMin: '900',
        slippage: 5,
        ...currentSwap,
      },
    } as unknown as GlobalState;
  }

  it('reports the input side when the user fixed what they pay', () => {
    const request = buildSwapBuildRequest(makeGlobal({
      inputSource: SwapInputSource.In,
      amountOut: '1000',
      quotedAmountOut: '1000',
    }));

    expect(request.swapMode).toBe('exact_in');
    expect(request.toAmount).toBe('1000');
  });

  it('reports the output side and sends what was quoted rather than what was typed', () => {
    // The form keeps the figure the user entered while the estimate answers with what the venue
    // could reach against it. The routes in the same request were priced for the latter.
    const request = buildSwapBuildRequest(makeGlobal({
      inputSource: SwapInputSource.Out,
      amountOut: '1000',
      quotedAmountOut: '999.87',
    }));

    expect(request.swapMode).toBe('exact_out');
    expect(request.toAmount).toBe('999.87');
  });

  it('falls back to the form figure when no estimate has answered yet', () => {
    const request = buildSwapBuildRequest(makeGlobal({
      inputSource: SwapInputSource.Out,
      amountOut: '1000',
    }));

    expect(request.toAmount).toBe('1000');
  });
});
