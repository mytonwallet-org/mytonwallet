package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.api.ApiTokenUpdateKind

class TokenUpdateMergeTest {
    @Test
    fun `partial update merges changed tokens and removes explicit slugs`() {
        val result = mergeTokenUpdateMaps(
            current = mapOf("retained" to 1, "changed" to 1, "removed" to 1),
            incoming = mapOf("changed" to 2),
            presentSlugs = setOf("changed"),
            kind = ApiTokenUpdateKind.PARTIAL,
            removedSlugs = listOf("removed")
        )

        assertEquals(mapOf("retained" to 1, "changed" to 2), result)
    }

    @Test
    fun `full update drops omitted tokens but retains protected ones`() {
        val result = mergeTokenUpdateMaps(
            current = mapOf("retained" to 1, "omitted" to 1, "protected" to 1),
            incoming = mapOf("retained" to 2),
            presentSlugs = setOf("retained"),
            kind = ApiTokenUpdateKind.FULL,
            removedSlugs = listOf("protected"),
            protectedSlugs = setOf("protected")
        )

        assertEquals(mapOf("retained" to 2, "protected" to 1), result)
    }
}
