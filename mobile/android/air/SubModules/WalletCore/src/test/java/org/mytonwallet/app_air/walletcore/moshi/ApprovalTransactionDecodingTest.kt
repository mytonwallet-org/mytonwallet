package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.adapter.EnumJsonAdapterFactory

class ApprovalTransactionDecodingTest {
    private val adapter = Moshi.Builder()
        .add(EnumJsonAdapterFactory())
        .build()
        .adapter(ApiTransactionType::class.java)

    @Test
    fun decodesApprovalType() {
        assertEquals(ApiTransactionType.APPROVAL, adapter.fromJson("\"approval\""))
    }

    @Test
    fun decodesPerpsTypes() {
        assertEquals(ApiTransactionType.PERPS_DEPOSIT, adapter.fromJson("\"perps_deposit\""))
        assertEquals(ApiTransactionType.PERPS_WITHDRAW, adapter.fromJson("\"perps_withdraw\""))
    }
}
