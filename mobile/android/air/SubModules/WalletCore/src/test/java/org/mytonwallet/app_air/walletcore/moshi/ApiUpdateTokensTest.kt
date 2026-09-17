package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.api.ApiTokenUpdateKind
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class ApiUpdateTokensTest {
    @Test
    fun `decodes partial kind and models removals`() {
        val kind =
            MoshiBuilder
                .build()
                .adapter(ApiTokenUpdateKind::class.java)
                .fromJson("\"partial\"")
        val update = ApiUpdate.ApiUpdateTokens(
            kind = checkNotNull(kind),
            tokens = emptyMap(),
            removedSlugs = listOf("removed")
        )

        assertEquals(ApiTokenUpdateKind.PARTIAL, update.kind)
        assertEquals(listOf("removed"), update.removedSlugs)
    }
}
