import { SwapErrorType } from '../../../global/types';

export type SwapError = SwapErrorType | 'insufficientBalance' | 'insufficientFee';

interface Params {
  errorType?: SwapErrorType;
  isAmountGreaterThanBalance: boolean;
  hasInsufficientFeeError: boolean;
}

const AMOUNT_ERROR_TYPES = new Set([
  SwapErrorType.NotEnoughLiquidity,
  SwapErrorType.TooSmallAmount,
  SwapErrorType.ChangellyMinSwap,
  SwapErrorType.ChangellyMaxSwap,
]);

/**
 * Picks the reason the swap can't be submitted, to be shown on the submit button. A refusal of the estimate wins over
 * the local checks, while an unexpected error says nothing about the swap and yields to them.
 */
export function resolveSwapError({
  errorType,
  isAmountGreaterThanBalance,
  hasInsufficientFeeError,
}: Params): SwapError | undefined {
  if (errorType !== undefined && errorType !== SwapErrorType.UnexpectedError) return errorType;
  if (isAmountGreaterThanBalance) return 'insufficientBalance';
  if (hasInsufficientFeeError) return 'insufficientFee';

  return errorType;
}

/** Returns `true` if the estimate rejects the entered amount itself, so the amount field shows the error */
export function isSwapAmountError(errorType: SwapErrorType | undefined) {
  return errorType !== undefined && AMOUNT_ERROR_TYPES.has(errorType);
}
