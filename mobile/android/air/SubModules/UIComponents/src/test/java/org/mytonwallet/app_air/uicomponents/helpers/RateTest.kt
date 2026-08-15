package org.mytonwallet.app_air.uicomponents.helpers

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.utils.thinSpace

class RateTest {

    @Test
    fun formattedRateUsesGroupingSeparators() {
        val rate = Rate(
            sendAmount = BigDecimal("12345.67"),
            receiveAmount = BigDecimal.ONE
        )

        assertEquals("12${thinSpace}345.67 TON", rate.fmtSend("TON", 2, round = false))
    }
}
