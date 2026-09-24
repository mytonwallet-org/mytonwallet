package org.mytonwallet.app_air.walletcore.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MCardsInfoTest {
    @Test
    fun mintStartAcceptsIsoUtcFractionalSecondsAndOffsets() {
        assertEquals(
            1735689600000L,
            MCardInfo(10, 0, 1.0, "2025-01-01T00:00:00Z").mintStartsAtMillis
        )
        assertEquals(
            1735689600123L,
            MCardInfo(10, 0, 1.0, "2025-01-01T03:30:00.1234+03:30").mintStartsAtMillis
        )
    }

    @Test
    fun invalidStartAndAvailableSupplyDoNotShowCountdown() {
        assertNull(MCardInfo(10, 0, 1.0, "invalid").mintStartsAtMillis)
        assertNull(MCardInfo(10, 1, 1.0, "2025-01-01T00:00:00Z").mintStartsAtMillis)
    }
}
