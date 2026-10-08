import {
  isSlippageValid,
  MAX_SLIPPAGE_VALUE,
  MIN_SLIPPAGE_VALUE,
  positionToSlippage,
  SLIPPAGE_TICKS,
  slippageToPosition,
} from './slippage';

describe('slippage scale', () => {
  it('spans the slider from the minimum to the maximum', () => {
    expect(slippageToPosition(MIN_SLIPPAGE_VALUE)).toBe(0);
    expect(slippageToPosition(MAX_SLIPPAGE_VALUE)).toBe(1);
  });

  it.each(SLIPPAGE_TICKS)('round-trips the %s%% tick', (tick) => {
    expect(positionToSlippage(slippageToPosition(tick))).toBe(tick);
  });

  it('keeps one decimal when converting a position', () => {
    expect(positionToSlippage(0.3)).toBe(0.6);
  });

  it('accepts values between the minimum and the maximum only', () => {
    expect(isSlippageValid(undefined)).toBe(false);
    expect(isSlippageValid(0)).toBe(false);
    expect(isSlippageValid(MIN_SLIPPAGE_VALUE / 2)).toBe(false);
    expect(isSlippageValid(MIN_SLIPPAGE_VALUE)).toBe(true);
    expect(isSlippageValid(MAX_SLIPPAGE_VALUE)).toBe(true);
    expect(isSlippageValid(MAX_SLIPPAGE_VALUE + 0.1)).toBe(false);
  });
});
