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
 * The identity of the question the swap form asks the backend. Two swap states sharing a key ask the same question,
 * so an estimate made for one of them answers the other. The inactive amount is the estimate's own output, and a
 * maximum amount is resolved by the backend, so neither takes part.
 */
export function getSwapEstimateInputKey(currentSwap: GlobalState['currentSwap']) {
  const amountKey = currentSwap.inputSource === SwapInputSource.In ? 'amountIn' : 'amountOut';

  return JSON.stringify([
    currentSwap.tokenInSlug,
    currentSwap.tokenOutSlug,
    currentSwap.slippage,
    currentSwap.inputSource,
    currentSwap.isMaxAmount,
    currentSwap.isMaxAmount ? undefined : currentSwap[amountKey],
  ]);
}

/**
 * Returns true if the swap estimate prepared for the global 1 is suitable for the global 2
 */
export function isSwapEstimateInputEqual(global1: GlobalState, global2: GlobalState) {
  return getSwapEstimateInputKey(global1.currentSwap) === getSwapEstimateInputKey(global2.currentSwap);
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
    quotedAmountOut: undefined,
    amountOutMin: '0',
    priceImpact: 0,
    errorType: undefined,
    limits: undefined,
    dieselStatus: undefined,
    dexLabel: undefined,
    dexRouterLabel: undefined,
    routes: undefined,
    currentCexLabel: undefined,
    currentCexProviderName: undefined,
    currentCexTermsOfUseUrl: undefined,
    currentCexPrivacyPolicyUrl: undefined,
    currentCexAmlKycPolicyUrl: undefined,
    swapHint: undefined,
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
