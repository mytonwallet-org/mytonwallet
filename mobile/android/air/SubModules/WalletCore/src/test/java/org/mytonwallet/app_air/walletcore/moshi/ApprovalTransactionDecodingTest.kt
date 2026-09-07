package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.EnumJsonAdapterFactory

class ApprovalTransactionDecodingTest {
    private val adapter = Moshi.Builder()
        .add(EnumJsonAdapterFactory())
        .build()
        .adapter(ApiTransactionType::class.java)

    @Test
    fun decodesApprovalType() {
        assertEquals(ApiTransactionType.APPROVAL, adapter.fromJson("\"approval\""))
    }
}
