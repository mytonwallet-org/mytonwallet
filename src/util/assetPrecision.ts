/** Matches backend `PRICE_PRECISION_TWO_MIN_USD` (stablecoin-range tweak). */
export const ASSET_AMOUNT_PRECISION_TWO_MIN_USD = 0.98;

/** Used when neither backend `precision` nor a usable USD price is available. */
export const DEFAULT_ASSET_AMOUNT_PRECISION = 2;

/**
 * Fractional digits for displaying a token amount, derived from its USD price.
 * Same thresholds as backend `pricePrecisionFromUsdPrice`.
 */
export function pricePrecisionFromUsdPrice(priceUsd: number | string): number {
  const price = Number(priceUsd);
  if (!Number.isFinite(price) || price < ASSET_AMOUNT_PRECISION_TWO_MIN_USD) {
    return 0;
  }
  if (price < 1000) {
    return 2;
  }
  return 4;
}

/** The most fractional digits a backend `precision` may ask for; a value outside 0..this is ignored. */
export const MAX_ASSET_AMOUNT_PRECISION = 18;

/** Prefers the backend field; otherwise derives from `priceUsd`, else the historic default of 2. */
export function getAssetAmountPrecision(token: { precision?: number; priceUsd?: number }): number {
  const { precision } = token;
  if (precision !== undefined && Number.isInteger(precision)
    && precision >= 0 && precision <= MAX_ASSET_AMOUNT_PRECISION) {
    return precision;
  }

  const price = Number(token.priceUsd);
  if (!Number.isFinite(price) || price <= 0) {
    return DEFAULT_ASSET_AMOUNT_PRECISION;
  }

  return pricePrecisionFromUsdPrice(price);
}
