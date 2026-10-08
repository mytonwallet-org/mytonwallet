export const MIN_SLIPPAGE_VALUE = 0.1;
export const MAX_SLIPPAGE_VALUE = 50;
/** The slider stops. The scale is logarithmic, so the usual small values get as much room as the large ones */
export const SLIPPAGE_TICKS = [0.1, 0.2, 0.5, 1, 2, 5, 10, 50];

const SCALE_RATIO = MAX_SLIPPAGE_VALUE / MIN_SLIPPAGE_VALUE;

/** Maps a slippage percentage to the slider position in the `[0, 1]` range */
export function slippageToPosition(value: number) {
  return Math.log(value / MIN_SLIPPAGE_VALUE) / Math.log(SCALE_RATIO);
}

export function positionToSlippage(position: number) {
  return roundSlippage(MIN_SLIPPAGE_VALUE * SCALE_RATIO ** position);
}

function roundSlippage(value: number) {
  return Math.round(value * 10) / 10;
}

export function isSlippageValid(value?: number): value is number {
  return value !== undefined && value >= MIN_SLIPPAGE_VALUE && value <= MAX_SLIPPAGE_VALUE;
}
