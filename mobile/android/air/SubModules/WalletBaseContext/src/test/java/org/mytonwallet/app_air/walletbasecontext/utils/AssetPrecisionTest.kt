package org.mytonwallet.app_air.walletbasecontext.utils

import org.junit.Assert.assertEquals
import org.junit.Test

class AssetPrecisionTest {
    @Test
    fun pricePrecisionMatchesBackendThresholds() {
        assertEquals(0, AssetPrecision.pricePrecisionFromUsdPrice(0.0))
        assertEquals(0, AssetPrecision.pricePrecisionFromUsdPrice(0.0001))
        assertEquals(0, AssetPrecision.pricePrecisionFromUsdPrice(0.97))
        assertEquals(2, AssetPrecision.pricePrecisionFromUsdPrice(0.98))
        assertEquals(2, AssetPrecision.pricePrecisionFromUsdPrice(1.0))
        assertEquals(2, AssetPrecision.pricePrecisionFromUsdPrice(999.99))
        assertEquals(4, AssetPrecision.pricePrecisionFromUsdPrice(1000.0))
        assertEquals(4, AssetPrecision.pricePrecisionFromUsdPrice(95_000.0))
    }

    @Test
    fun amountPrecisionPrefersBackendField() {
        assertEquals(4, AssetPrecision.amountPrecision(4, 0.0001))
    }

    @Test
    fun amountPrecisionDerivesFromPrice() {
        assertEquals(4, AssetPrecision.amountPrecision(null, 95_000.0))
        assertEquals(2, AssetPrecision.amountPrecision(null, 2.0))
        assertEquals(0, AssetPrecision.amountPrecision(null, 0.0001))
    }

    @Test
    fun amountPrecisionFallsBackToTwo() {
        assertEquals(2, AssetPrecision.amountPrecision(null, null))
        assertEquals(2, AssetPrecision.amountPrecision(null, 0.0))
    }
}
