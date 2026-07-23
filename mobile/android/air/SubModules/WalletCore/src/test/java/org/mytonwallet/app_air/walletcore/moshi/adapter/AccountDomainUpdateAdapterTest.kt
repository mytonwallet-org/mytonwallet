package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.JsonDataException
import com.squareup.moshi.Moshi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AccountDomainUpdateAdapterTest {
    private val adapter = Moshi.Builder()
        .add(AccountDomainUpdateAdapter())
        .build()
        .adapter(AccountDomainUpdate::class.java)

    @Test
    fun decodesDomainSet() {
        assertEquals(AccountDomainUpdate.Set("wallet.ton"), adapter.fromJson("\"wallet.ton\""))
    }

    @Test
    fun decodesDomainClear() {
        assertEquals(AccountDomainUpdate.Clear, adapter.fromJson("false"))
    }

    @Test
    fun rejectsInvalidBoolean() {
        assertThrows(JsonDataException::class.java) {
            adapter.fromJson("true")
        }
    }
}
