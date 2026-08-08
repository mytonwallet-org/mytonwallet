package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class ApiAddSubWalletResultTest {
    private val adapter = Moshi.Builder()
        .addLast(KotlinJsonAdapterFactory())
        .build()
        .adapter(ApiAddSubWalletResult::class.java)

    @Test
    fun decodesExistingAccountWithoutChainData() {
        val result = adapter.fromJson(
            """{"isNew":false,"accountId":"0-mainnet","address":null}"""
        )

        requireNotNull(result)
        assertFalse(result.isNew)
        assertEquals("0-mainnet", result.accountId)
        assertNull(result.byChain)
    }
}
