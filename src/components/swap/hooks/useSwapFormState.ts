import { useMemo } from '../../../lib/teact/teact';

import type { GlobalState, UserSwapToken } from '../../../global/types';
import { SwapErrorType, SwapInputSource, SwapType } from '../../../global/types';

import { INIT_SWAP_ASSETS, MAX_PRICE_IMPACT_VALUE } from '../../../config';
import { fromDecimal } from '../../../util/decimals';
import { explainSwapFee, getMaxSwapAmount, isBalanceSufficientForSwap } from '../../../util/fee/swapFee';
import { findNativeToken } from '../../../util/tokens';
import { isSwapAmountError } from '../helpers/resolveSwapError';

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

  const route = currentSwap.route ?? (swapType === SwapType.OnChain ? 'dex' : 'cex');

  const explainedFee = useMemo(
    () => explainSwapFee({
      swapType,
      route,
      tokenInSlug,
      networkFee,
      realNetworkFee,
      dieselStatus,
      dieselFee,
      nativeTokenInBalance,
    }),
    [swapType, route, tokenInSlug, networkFee, realNetworkFee, dieselStatus, dieselFee, nativeTokenInBalance],
  );

  const maxAmountFromBackendBigint = maxAmountFromBackend && tokenIn
    ? fromDecimal(maxAmountFromBackend, tokenIn.decimals)
    : undefined;

  const maxAmount = getMaxSwapAmount({
    swapType,
    route,
    tokenInBalance: balanceIn,
    tokenIn,
    fullNetworkFee: explainedFee.fullFee?.networkTerms,
    maxAmountFromBackend: maxAmountFromBackendBigint,
  });

  // Note: this constant has 3 distinct meaningful values
  const isEnoughBalance = isBalanceSufficientForSwap({
    swapType,
    route,
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
  // The tokens of a swap to the wallet come from outside, so the wallet balance doesn't limit the amount
  const isAmountGreaterThanBalance = swapType !== SwapType.CrosschainToWallet
    && amountInBigint !== undefined && amountInBigint > balanceIn;

  const canSubmit = (isDieselNotAuthorized && !isAmountGreaterThanBalance) || (
    (amountInBigint ?? 0n) > 0n
    && (amountOutBigint ?? 0n) > 0n
    && isEnoughBalance
    && (!explainedFee.isGasless || dieselStatus === 'available' || dieselStatus === 'stars-fee')
    && !isEstimating
    && errorType === undefined
  );

  // The native token's max amount leaves room for the fee, so an amount above it also means a fee shortage
  const hasMaxAmountError = amountInBigint !== undefined && maxAmount !== undefined && amountInBigint > maxAmount;
  const hasAmountInError = hasMaxAmountError || isSwapAmountError(errorType);
  const amountOutValue = (amountInBigint ?? 0n) <= 0n && inputSource === SwapInputSource.In
    ? ''
    : amountOut?.toString();
  const hasInsufficientFeeError = isEnoughBalance === false && !isAmountGreaterThanBalance
    && dieselStatus !== 'not-authorized' && dieselStatus !== 'pending-previous';
  const hasFeeError = hasInsufficientFeeError || errorType === SwapErrorType.NotEnoughForFee;

  const isPriceImpactError = priceImpact >= MAX_PRICE_IMPACT_VALUE;
  const isCrosschain = route === 'cex';

  return {
    currentTokenInSlug,
    currentTokenOutSlug,
    tokenIn,
    tokenOut,
    balanceIn,
    explainedFee,
    maxAmount,
    isEnoughNative,
    isDieselNotAuthorized,
    canSubmit,
    hasAmountInError,
    hasMaxAmountError,
    amountOutValue,
    isAmountGreaterThanBalance,
    hasInsufficientFeeError,
    hasFeeError,
    isPriceImpactError,
    isCrosschain,
  };
}
