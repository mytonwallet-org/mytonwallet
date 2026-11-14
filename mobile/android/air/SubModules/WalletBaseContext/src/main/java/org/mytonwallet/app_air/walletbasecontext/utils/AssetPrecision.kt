package org.mytonwallet.app_air.walletbasecontext.utils

/** Matches backend `pricePrecisionFromUsdPrice` / web `src/util/assetPrecision.ts`. */
object AssetPrecision {
    const val TWO_MIN_USD = 0.98
    const val DEFAULT_AMOUNT_PRECISION = 2

    fun pricePrecisionFromUsdPrice(priceUsd: Double): Int {
        if (!priceUsd.isFinite() || priceUsd < TWO_MIN_USD) return 0
        if (priceUsd < 1000) return 2
        return 4
    }

    /** Prefers the backend field; otherwise derives from `priceUsd`, else the historic default of 2. */
    fun amountPrecision(precision: Int?, priceUsd: Double?): Int {
        if (precision != null) return precision
        if (priceUsd == null || !priceUsd.isFinite() || priceUsd <= 0) {
            return DEFAULT_AMOUNT_PRECISION
        }
        return pricePrecisionFromUsdPrice(priceUsd)
    }
}
