package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CexRefreshContextTest {
    private data class PatchRow(val id: String, val shouldHide: Boolean)

    @Test
    fun largeIncomingBatchKeepsActiveCexLocalAndPendingContext() {
        val context = selectBoundedCexRefreshContext(
            activeCexActivities = listOf("cex"),
            cexProjectionActivities = listOf("hidden-cex-source"),
            localActivities = listOf("local"),
            pendingActivities = listOf("pending"),
            incomingActivities = List(250) { "incoming-$it" },
            recentActivities = listOf("older-raw"),
            limit = 250
        ) { it }

        assertEquals(250, context.size)
        assertEquals(listOf("cex", "hidden-cex-source", "local", "pending"), context.take(4))
        assertTrue(context.contains("incoming-0"))
    }

    @Test
    fun retainsRecentRawContextAfterPriorityAndIncomingRows() {
        val context = selectBoundedCexRefreshContext(
            activeCexActivities = listOf("cex"),
            localActivities = listOf("local"),
            pendingActivities = listOf("pending"),
            incomingActivities = listOf("incoming"),
            recentActivities = listOf("older-raw"),
            limit = 250
        ) { it }

        assertEquals(listOf("cex", "local", "pending", "incoming", "older-raw"), context)
    }

    @Test
    fun keepsHiddenNonLocalPatchUpsertsForCacheApplication() {
        val upsert = listOf(
            PatchRow("local-swap", shouldHide = true),
            PatchRow("raw-split-leg", shouldHide = true),
            PatchRow("canonical-swap", shouldHide = false)
        )

        val nonLocal = excludeIncomingLocalPatchUpserts(upsert, setOf("local-swap")) { it.id }

        assertEquals(listOf("raw-split-leg", "canonical-swap"), nonLocal.map { it.id })
        assertTrue(nonLocal.first().shouldHide)
    }

    @Test
    fun authoritativePatchOverwritesExistingValueWithoutClientMerging() {
        val byId = mutableMapOf("activity" to PatchRow("activity", shouldHide = false))
        val hidden = PatchRow("activity", shouldHide = true)

        val changedIds = applyAuthoritativePatchById(
            byId = byId,
            removeIds = emptyList(),
            upserts = listOf(hidden)
        ) { it.id }

        assertEquals(listOf("activity"), changedIds)
        assertEquals(hidden, byId["activity"])
    }
}
