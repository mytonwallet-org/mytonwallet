import type { GlobalState } from '../types';
import { SwapInputSource, SwapState } from '../types';

export function shouldAvoidSwapEstimation(global: GlobalState) {
  // For a better UX, we should leave the fees and the other swap data intact during swap confirmation (for example,
  // to avoid switching from/to gasless mode).
  // `isEstimating` forces estimation, because by design it means that there was a swap parameter change that
  // invalidates the current swap estimation.
  return !global.currentSwap.isEstimating && (
    global.currentSwap.state === SwapState.Blockchain
    || global.currentSwap.state === SwapState.Password
  );
}

/**
 * Returns true if the swap estimate prepared for the global 1 is suitable for the global 2
 */
export function isSwapEstimateInputEqual({ currentSwap: swap1 }: GlobalState, { currentSwap: swap2 }: GlobalState) {
  const amountKey = swap1.inputSource === SwapInputSource.In ? 'amountIn' : 'amountOut';

  return swap1.tokenInSlug === swap2.tokenInSlug
    && swap1.tokenOutSlug === swap2.tokenOutSlug
    && swap1.slippage === swap2.slippage
    && swap1.inputSource === swap2.inputSource
    && swap1.isMaxAmount === swap2.isMaxAmount
    && (swap2.isMaxAmount || swap1[amountKey] === swap2[amountKey]);
}

/**
 * Returns true is the swap form has enough data to start estimation
 */
export function isSwapFormFilled({ currentSwap }: GlobalState) {
  const amountKey = currentSwap.inputSource === SwapInputSource.In ? 'amountIn' : 'amountOut';

  return currentSwap.tokenInSlug
    && currentSwap.tokenOutSlug
    && Number(currentSwap[amountKey] ?? '0') > 0; // The backend fails if the amount is "0", "0.0", etc
}

export function doesSwapChangeRequireEstimation(globalBefore: GlobalState, globalAfter: GlobalState) {
  return isSwapFormFilled(globalAfter) && !isSwapEstimateInputEqual(globalBefore, globalAfter);
}

export function doesSwapChangeRequireEstimationReset(globalBefore: GlobalState, globalAfter: GlobalState) {
  return !isSwapFormFilled(globalAfter)
    || globalBefore.currentSwap.tokenInSlug !== globalAfter.currentSwap.tokenInSlug
    || globalBefore.currentSwap.tokenOutSlug !== globalAfter.currentSwap.tokenOutSlug;
}

export function doesSwapChangeRequireDexUnselect(
  { currentSwap: swap1 }: GlobalState,
  { currentSwap: swap2 }: GlobalState,
) {
  const amountKey = swap1.inputSource === SwapInputSource.In ? 'amountIn' : 'amountOut';

  return swap1.tokenInSlug !== swap2.tokenInSlug
    || swap1.tokenOutSlug !== swap2.tokenOutSlug
    || swap1.inputSource !== swap2.inputSource
    || !((swap1.isMaxAmount && swap2.isMaxAmount) || swap1[amountKey] === swap2[amountKey]);
}

/**
 * Returns the `currentSwap` parameters that should be set when it's impossible to estimate the current swap or no
 * estimation has been done.
 */
export function getSwapEstimateResetParams(global: GlobalState) {
  const amountReset = global.currentSwap.inputSource === SwapInputSource.In
    ? { amountOut: undefined }
    : { amountIn: undefined };

  return {
    ...amountReset,
    amountOutMin: '0',
    priceImpact: 0,
    errorType: undefined,
    limits: undefined,
    dieselStatus: undefined,
    estimates: undefined,
    bestRateDexLabel: undefined,
    currentCexLabel: undefined,
    currentCexProviderName: undefined,
    currentCexTermsOfUseUrl: undefined,
    currentCexPrivacyPolicyUrl: undefined,
    currentCexAmlKycPolicyUrl: undefined,
    isManualDepositRequired: undefined,
    networkFee: undefined,
    realNetworkFee: undefined,
    swapFee: undefined,
    swapFeePercent: undefined,
    ourFee: undefined,
    ourFeePercent: undefined,
    dieselFee: undefined,
  } satisfies Partial<GlobalState['currentSwap']>;
}
