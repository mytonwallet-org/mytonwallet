import type { GlobalState } from '../../types';
import type { SwapEstimateResult } from './swap';
import { SwapErrorType, SwapInputSource, SwapState } from '../../types';

import {
  BASE,
  BASE_USDC_MAINNET,
  BITCOIN,
  BITCOINCASH,
  DOGECOIN,
  LITECOIN,
  MYCOIN_MAINNET,
  SOLANA,
  TON_USDT_MAINNET,
  TONCOIN,
  TRX,
} from '../../../config';
import * as schedulers from '../../../util/schedulers';
import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { clearCurrentSwap, updateCurrentSwap } from '../../reducers';
import {
  buildSwapBuildRequest,
  estimateSwap,
  estimateSwapConcurrently,
  shouldBlockUnsupportedNearIntentsMemo,
} from './swap';

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
}));

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

describe('startSwap', () => {
  const ACCOUNT_ID = '0-mainnet';

  beforeEach(() => {
    const base = clearCurrentSwap(getGlobal());
    const { bySlug } = base.tokenInfo;

    setGlobal({
      ...base,
      currentAccountId: ACCOUNT_ID,
      accounts: {
        ...base.accounts,
        byId: {
          [ACCOUNT_ID]: {
            type: 'mnemonic',
            title: 'Test',
            byChain: { ton: { address: 'UQ1' }, solana: { address: 'So1' } },
          },
        },
      },
      byAccountId: {
        [ACCOUNT_ID]: {
          balances: { bySlug: { [TONCOIN.slug]: 1_000_000_000n, [TON_USDT_MAINNET.slug]: 50_000_000n } },
        },
      },
      tokenInfo: {
        bySlug: {
          ...bySlug,
          [TONCOIN.slug]: { ...bySlug[TONCOIN.slug], priceUsd: 3 },
          [TON_USDT_MAINNET.slug]: { ...bySlug[TON_USDT_MAINNET.slug], priceUsd: 1 },
        },
      },
    } as unknown as GlobalState);
  });

  it('sells a funded token when only the token to buy is given', () => {
    getActions().startSwap({ tokenOutSlug: SOLANA.slug });

    expect(getGlobal().currentSwap).toMatchObject({
      tokenInSlug: TON_USDT_MAINNET.slug,
      tokenOutSlug: SOLANA.slug,
    });
  });

  it('pays with the default token when the account has nothing to pair with the token to buy', () => {
    const global = getGlobal();
    setGlobal({
      ...global,
      accounts: {
        ...global.accounts!,
        byId: { [ACCOUNT_ID]: { ...global.accounts!.byId[ACCOUNT_ID], byChain: { bitcoin: { address: 'bc1' } } } },
      },
    });

    getActions().startSwap({ tokenOutSlug: BITCOIN.slug });

    expect(getGlobal().currentSwap).toMatchObject({ tokenInSlug: TONCOIN.slug, tokenOutSlug: BITCOIN.slug });
  });

  it('keeps both tokens when both are given', () => {
    getActions().startSwap({ tokenInSlug: TONCOIN.slug, tokenOutSlug: SOLANA.slug });

    expect(getGlobal().currentSwap).toMatchObject({ tokenInSlug: TONCOIN.slug, tokenOutSlug: SOLANA.slug });
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

describe('estimateSwap', () => {
  const ACCOUNT_ID = '0-mainnet';
  const cexEstimate = {
    route: 'cex',
    cexLabel: 'near-intents',
    from: BASE_USDC_MAINNET.slug,
    fromAmount: '10',
    to: SOLANA.slug,
    toAmount: '0.05',
    swapFee: '0',
    fromMin: '1',
    fromMax: '1000',
  };

  function mockApi(draft: unknown) {
    (callApi as jest.Mock).mockImplementation((method: string) => Promise.resolve(
      method === 'swapEstimate' ? cexEstimate : draft,
    ));
  }

  const dexEstimate = {
    route: 'dex' as const,
    from: BASE.slug,
    to: BASE_USDC_MAINNET.tokenAddress,
    fromAmount: '300',
    toAmount: '900',
    toMinAmount: '850',
    impact: 0,
    dieselStatus: 'not-available' as const,
    networkFee: '0.001',
    realNetworkFee: '0.001',
    swapFee: '0',
    swapFeePercent: 0,
    ourFee: '0',
    ourFeePercent: 0,
  };

  function mockDexApi() {
    (callApi as jest.Mock).mockImplementation((method: string) => Promise.resolve(
      method === 'swapEstimate' ? dexEstimate : undefined,
    ));
  }

  beforeEach(() => {
    (callApi as jest.Mock).mockReset();
    const base = clearCurrentSwap(getGlobal());

    setGlobal(updateCurrentSwap({
      ...base,
      currentAccountId: ACCOUNT_ID,
      accounts: {
        ...base.accounts,
        byId: {
          [ACCOUNT_ID]: {
            type: 'mnemonic',
            title: 'Test',
            byChain: { base: { address: '0x1' }, solana: { address: 'So1' } },
          },
        },
      },
      byAccountId: {
        [ACCOUNT_ID]: { balances: { bySlug: { [BASE_USDC_MAINNET.slug]: 20_000_000n, [BASE.slug]: 0n } } },
      },
      swapTokenInfo: {
        ...base.swapTokenInfo,
        bySlug: { [BASE_USDC_MAINNET.slug]: BASE_USDC_MAINNET, [SOLANA.slug]: SOLANA },
      },
    } as unknown as GlobalState, {
      state: SwapState.Initial,
      tokenInSlug: BASE_USDC_MAINNET.slug,
      tokenOutSlug: SOLANA.slug,
      amountIn: '10',
      inputSource: SwapInputSource.In,
    }));
  });

  it.each([DOGECOIN, BITCOIN, LITECOIN, BITCOINCASH, TONCOIN, SOLANA, TRX])(
    'prices native $slug Max against the full balance and ordinary swaps against their amount',
    async (token) => {
      const balance = 300n * 10n ** BigInt(token.decimals);
      const base = getGlobal();
      setGlobal(updateCurrentSwap({
        ...base,
        accounts: {
          ...base.accounts,
          byId: {
            [ACCOUNT_ID]: {
              type: 'mnemonic', title: 'Test',
              byChain: { [token.chain]: { address: 'source' }, base: { address: '0x1' } },
            },
          },
        },
        byAccountId: { [ACCOUNT_ID]: { balances: { bySlug: { [token.slug]: balance } } } },
        swapTokenInfo: {
          ...base.swapTokenInfo,
          bySlug: { [token.slug]: token, [BASE_USDC_MAINNET.slug]: BASE_USDC_MAINNET },
        },
      } as unknown as GlobalState, {
        tokenInSlug: token.slug, tokenOutSlug: BASE_USDC_MAINNET.slug, amountIn: '299', isMaxAmount: true,
      }));
      mockApi({ explainedFee: { fullFee: { nativeSum: 488_000n }, realFee: { nativeSum: 488_000n } } });
      await estimateSwap(getGlobal(), () => false);
      expect(callApi).toHaveBeenCalledWith('checkTransactionDraft', token.chain, expect.objectContaining({
        amount: balance,
      }));
      (callApi as jest.Mock).mockClear();
      setGlobal(updateCurrentSwap(getGlobal(), { isMaxAmount: false, amountIn: '10' }));
      await estimateSwap(getGlobal(), () => false);
      expect(callApi).toHaveBeenCalledWith('checkTransactionDraft', token.chain, expect.objectContaining({
        amount: 10n * 10n ** BigInt(token.decimals),
      }));
    },
  );

  it('prices on-chain native Max via swapEstimate and ordinary swaps against their amount', async () => {
    const token = BASE;
    const balance = 300n * 10n ** BigInt(token.decimals);
    const base = getGlobal();
    setGlobal(updateCurrentSwap({
      ...base,
      accounts: {
        ...base.accounts,
        byId: {
          [ACCOUNT_ID]: {
            type: 'mnemonic', title: 'Test',
            byChain: { [token.chain]: { address: '0x1' } },
          },
        },
      },
      byAccountId: { [ACCOUNT_ID]: { balances: { bySlug: { [token.slug]: balance } } } },
      swapTokenInfo: {
        ...base.swapTokenInfo,
        bySlug: { [token.slug]: token, [BASE_USDC_MAINNET.slug]: BASE_USDC_MAINNET },
      },
    } as unknown as GlobalState, {
      tokenInSlug: token.slug, tokenOutSlug: BASE_USDC_MAINNET.slug, amountIn: '299', isMaxAmount: true,
    }));
    mockDexApi();
    await estimateSwap(getGlobal(), () => false);
    expect(callApi).toHaveBeenCalledWith('swapEstimate', ACCOUNT_ID, expect.objectContaining({
      fromAmount: '300',
      isFromAmountMax: true,
    }));
    expect(callApi).not.toHaveBeenCalledWith('checkTransactionDraft', expect.anything(), expect.anything());
    (callApi as jest.Mock).mockClear();
    setGlobal(updateCurrentSwap(getGlobal(), { isMaxAmount: false, amountIn: '10' }));
    await estimateSwap(getGlobal(), () => false);
    expect(callApi).toHaveBeenCalledWith('swapEstimate', ACCOUNT_ID, expect.objectContaining({
      fromAmount: '10',
      isFromAmountMax: false,
    }));
  });

  it('blocks the swap when the source chain cannot price the transfer', async () => {
    mockApi(undefined);

    const result = await estimateSwap(getGlobal(), () => false);

    expect(result).toMatchObject({ errorType: SwapErrorType.UnexpectedError, amountOut: '0.05' });
  });

  it('keeps the swap submittable with the fee once the source chain prices the transfer', async () => {
    mockApi({
      explainedFee: {
        fullFee: { nativeSum: 500_000_000_000_000n },
        realFee: { nativeSum: 400_000_000_000_000n },
      },
    });

    const result = await estimateSwap(getGlobal(), () => false);

    expect(result).toMatchObject({ errorType: undefined, networkFee: '0.0005', realNetworkFee: '0.0004' });
  });
});

describe('submitSwapCex', () => {
  const ACCOUNT_ID = '0-mainnet';
  const SWAP_ID = 'cex-swap';
  const MFA_REQUEST_HASH = 'mfa-request';
  const ENCLAVE_TOKEN = 'enclave-token';

  // The real handlers live in action modules this test does not load
  const releaseEnclaveSession = jest.fn();
  const showError = jest.fn();
  addActionHandler('releaseEnclaveSession', releaseEnclaveSession);
  addActionHandler('showError', showError);

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(schedulers, 'pause').mockResolvedValue(undefined);
    const base = clearCurrentSwap(getGlobal());

    setGlobal(updateCurrentSwap({
      ...base,
      currentAccountId: ACCOUNT_ID,
      accounts: {
        ...base.accounts,
        byId: {
          [ACCOUNT_ID]: {
            type: 'mnemonic',
            title: 'Test',
            byChain: { ton: { address: 'UQ1', mfa: { address: 'UQmfa' } } },
          },
        },
      },
      byAccountId: { [ACCOUNT_ID]: { balances: { bySlug: {} } } },
      swapTokenInfo: {
        ...base.swapTokenInfo,
        bySlug: { [TON_USDT_MAINNET.slug]: TON_USDT_MAINNET, [BASE.slug]: BASE },
      },
    } as unknown as GlobalState, {
      state: SwapState.Password,
      tokenInSlug: TON_USDT_MAINNET.slug,
      tokenOutSlug: BASE.slug,
      amountIn: '10',
      amountOut: '0.0036',
      inputSource: SwapInputSource.In,
      toAddress: '0xdestination',
      networkFee: '0.05',
    }));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('asks an MFA account for Telegram confirmation without showing the swap as complete first', async () => {
    const swapsBeforeDeposit = mockCexSubmitResult({ swapId: SWAP_ID, mfaRequestHash: MFA_REQUEST_HASH });

    await submitSwapCex();

    expect(swapsBeforeDeposit).toEqual([{ state: SwapState.Password, isLoading: true }]);
    expect(getGlobal().currentSwap).toMatchObject({
      state: SwapState.ConfirmMfa,
      isLoading: undefined,
      swapId: SWAP_ID,
      mfaRequestHash: MFA_REQUEST_HASH,
    });
    expect(releaseEnclaveSession).toHaveBeenCalledWith(
      expect.anything(),
      expect.anything(),
      { enclaveToken: ENCLAVE_TOKEN },
    );
  });

  it('completes an MFA account swap whose deposit needs no Telegram confirmation', async () => {
    mockCexSubmitResult({ swapId: SWAP_ID });

    await submitSwapCex();

    expect(getGlobal().currentSwap).toMatchObject({ state: SwapState.Complete, isLoading: undefined });
  });

  it('keeps an MFA account on the password screen when the deposit fails', async () => {
    mockCexSubmitResult(undefined);

    await submitSwapCex();

    expect(getGlobal().currentSwap).toMatchObject({ state: SwapState.Password, isLoading: undefined });
    expect(showError).toHaveBeenCalled();
  });

  function mockCexSubmitResult(submitResult: unknown) {
    const swapsBeforeDeposit: Pick<GlobalState['currentSwap'], 'state' | 'isLoading'>[] = [];

    (callApi as jest.Mock).mockImplementation((method: string) => {
      switch (method) {
        case 'swapCexCreateTransaction':
          return Promise.resolve({
            swap: { id: SWAP_ID, fromAmount: '10', networkFee: '0.05', cex: { payinAddress: 'UQpayin' } },
            activity: { id: 'activity' },
          });
        case 'swapCexSubmit': {
          const { state, isLoading } = getGlobal().currentSwap;
          swapsBeforeDeposit.push({ state, isLoading });
          return Promise.resolve(submitResult);
        }
        default:
          return Promise.resolve(undefined);
      }
    });

    return swapsBeforeDeposit;
  }

  function submitSwapCex() {
    return getActions().submitSwapCex({ enclaveToken: ENCLAVE_TOKEN }) as unknown as Promise<void>;
  }
});
