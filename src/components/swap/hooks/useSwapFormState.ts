import { useMemo } from '../../../lib/teact/teact';

import type { GlobalState, UserSwapToken } from '../../../global/types';
import { SwapInputSource, SwapType } from '../../../global/types';

import { INIT_SWAP_ASSETS, MAX_PRICE_IMPACT_VALUE } from '../../../config';
import { fromDecimal } from '../../../util/decimals';
import { explainSwapFee, getMaxSwapAmount, isBalanceSufficientForSwap } from '../../../util/fee/swapFee';
import { findNativeToken } from '../../../util/tokens';

/**
 * Derives everything the swap form shows and checks from the current swap state: the tokens, the fees,
 * the maximum amount, the balance checks and whether the form can be submitted.
 */
export default function useSwapFormState(
  currentSwap: GlobalState['currentSwap'],
  tokens: UserSwapToken[] | undefined,
  swapType: SwapType,
) {
  const {
    tokenInSlug,
    tokenOutSlug,
    amountIn,
    amountOut,
    errorType,
    isEstimating,
    networkFee,
    realNetworkFee,
    priceImpact = 0,
    inputSource,
    dieselStatus,
    dieselFee,
    maxAmountFromBackend,
  } = currentSwap;

  const currentTokenInSlug = tokenInSlug ?? INIT_SWAP_ASSETS.in.slug;
  const currentTokenOutSlug = tokenOutSlug ?? INIT_SWAP_ASSETS.out.slug;

  const tokenIn = useMemo(
    () => tokens?.find((token) => token.slug === currentTokenInSlug),
    [currentTokenInSlug, tokens],
  );
  const tokenOut = useMemo(
    () => tokens?.find((token) => token.slug === currentTokenOutSlug),
    [currentTokenOutSlug, tokens],
  );

  const nativeUserTokenIn = useMemo(
    () => {
      const nativeTokenInSlug = findNativeToken(tokenIn?.chain)?.slug;
      if (!nativeTokenInSlug) return undefined;
      return tokens?.find((token) => token.slug === nativeTokenInSlug);
    },
    [tokenIn?.chain, tokens],
  );
  const nativeTokenInBalance = nativeUserTokenIn?.amount ?? 0n;

  const amountInBigint = amountIn && tokenIn ? fromDecimal(amountIn, tokenIn.decimals) : undefined;
  const amountOutBigint = amountOut && tokenOut ? fromDecimal(amountOut, tokenOut.decimals) : undefined;
  const balanceIn = tokenIn?.amount ?? 0n;

  const explainedFee = useMemo(
    () => explainSwapFee({
      swapType,
      tokenInSlug,
      networkFee,
      realNetworkFee,
      dieselStatus,
      dieselFee,
      nativeTokenInBalance,
    }),
    [swapType, tokenInSlug, networkFee, realNetworkFee, dieselStatus, dieselFee, nativeTokenInBalance],
  );

  const maxAmountFromBackendBigint = maxAmountFromBackend && tokenIn
    ? fromDecimal(maxAmountFromBackend, tokenIn.decimals)
    : undefined;

  const maxAmount = getMaxSwapAmount({
    swapType,
    tokenInBalance: balanceIn,
    tokenIn,
    fullNetworkFee: explainedFee.fullFee?.networkTerms,
    maxAmountFromBackend: maxAmountFromBackendBigint,
  });

  // Note: this constant has 3 distinct meaningful values
  const isEnoughBalance = isBalanceSufficientForSwap({
    swapType,
    tokenInBalance: balanceIn,
    tokenIn,
    fullNetworkFee: explainedFee.fullFee?.networkTerms,
    amountIn,
    nativeTokenInBalance,
    maxAmountFromBackend: maxAmountFromBackendBigint,
  });

  const networkFeeBigint = networkFee !== undefined && nativeUserTokenIn
    ? fromDecimal(networkFee, nativeUserTokenIn.decimals)
    : 0n;
  const isEnoughNative = nativeTokenInBalance >= networkFeeBigint;

  const isDieselNotAuthorized = explainedFee.isGasless && dieselStatus === 'not-authorized';

  const canSubmit = isDieselNotAuthorized || (
    (amountInBigint ?? 0n) > 0n
    && (amountOutBigint ?? 0n) > 0n
    && isEnoughBalance
    && (!explainedFee.isGasless || dieselStatus === 'available' || dieselStatus === 'stars-fee')
    && !isEstimating
    && errorType === undefined
  );

  const hasAmountInError = amountInBigint !== undefined && maxAmount !== undefined && amountInBigint > maxAmount;
  const amountOutValue = (amountInBigint ?? 0n) <= 0n && inputSource === SwapInputSource.In
    ? ''
    : amountOut?.toString();
  const isAmountGreaterThanBalance = amountInBigint !== undefined && amountInBigint > balanceIn;
  const hasInsufficientFeeError = isEnoughBalance === false && !isAmountGreaterThanBalance
    && dieselStatus !== 'not-authorized' && dieselStatus !== 'pending-previous';

  const isPriceImpactError = priceImpact >= MAX_PRICE_IMPACT_VALUE;
  const isCrosschain = swapType !== SwapType.OnChain;

  return {
    currentTokenInSlug,
    currentTokenOutSlug,
    tokenIn,
    tokenOut,
    nativeUserTokenIn,
    balanceIn,
    explainedFee,
    maxAmount,
    isEnoughNative,
    isDieselNotAuthorized,
    canSubmit,
    hasAmountInError,
    amountOutValue,
    hasInsufficientFeeError,
    isPriceImpactError,
    isCrosschain,
  };
}
