import { SwapErrorType } from '../../../global/types';

import { isSwapAmountError, resolveSwapError } from './resolveSwapError';

const NO_ERRORS = {
  isAmountGreaterThanBalance: false,
  hasInsufficientFeeError: false,
};

describe('resolveSwapError', () => {
  it('returns nothing when the swap can be submitted', () => {
    expect(resolveSwapError(NO_ERRORS)).toBeUndefined();
  });

  it.each([
    SwapErrorType.InvalidPair,
    SwapErrorType.ChangellyMinSwap,
    SwapErrorType.ChangellyMaxSwap,
    SwapErrorType.TooSmallAmount,
    SwapErrorType.NotEnoughLiquidity,
    SwapErrorType.QuoteUnavailable,
    SwapErrorType.ServiceUnavailable,
  ])('shows the estimate error %s even when the amount exceeds the balance', (errorType) => {
    expect(resolveSwapError({ ...NO_ERRORS, errorType, isAmountGreaterThanBalance: true })).toBe(errorType);
  });

  it('shows a local check before an unexpected error', () => {
    const errorType = SwapErrorType.UnexpectedError;
    expect(resolveSwapError({ ...NO_ERRORS, errorType, isAmountGreaterThanBalance: true })).toBe('insufficientBalance');
    expect(resolveSwapError({ ...NO_ERRORS, errorType, hasInsufficientFeeError: true })).toBe('insufficientFee');
    expect(resolveSwapError({ ...NO_ERRORS, errorType })).toBe(errorType);
  });

  it('shows the balance shortage before the fee shortage', () => {
    expect(resolveSwapError({ isAmountGreaterThanBalance: true, hasInsufficientFeeError: true }))
      .toBe('insufficientBalance');
    expect(resolveSwapError({ ...NO_ERRORS, hasInsufficientFeeError: true })).toBe('insufficientFee');
  });
});

describe('isSwapAmountError', () => {
  it.each([
    SwapErrorType.NotEnoughLiquidity,
    SwapErrorType.TooSmallAmount,
    SwapErrorType.ChangellyMinSwap,
    SwapErrorType.ChangellyMaxSwap,
  ])('blames the amount for the error %s', (errorType) => {
    expect(isSwapAmountError(errorType)).toBe(true);
  });

  it.each([
    SwapErrorType.UnexpectedError,
    SwapErrorType.InvalidPair,
    SwapErrorType.NotEnoughForFee,
    undefined,
  ])('does not blame the amount for the error %s', (errorType) => {
    expect(isSwapAmountError(errorType)).toBe(false);
  });
});
