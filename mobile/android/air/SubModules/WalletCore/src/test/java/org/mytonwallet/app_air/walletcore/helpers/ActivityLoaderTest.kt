package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Test

class ActivityLoaderTest {
    private data class Activity(val id: String, val source: String, val stableId: String = id)

    @Test
    fun mergesIndexedAndTemporaryActivitiesOncePerId() {
        val indexedPending = Activity("pending", "indexed")
        val temporaryPending = Activity("pending", "temporary")
        val confirmed = Activity("confirmed", "indexed")

        val result = mergeUniqueActivitySources(
            indexedActivities = listOf(indexedPending, confirmed),
            temporaryActivities = listOf(temporaryPending),
            getId = { it.stableId }
        )

        assertEquals(listOf(indexedPending, confirmed), result)
    }

    @Test
    fun keepsIndexedReplacementWhenRawIdsShareStableId() {
        val pending = Activity(id = "pending", stableId = "local", source = "indexed")
        val local = Activity(id = "local", source = "temporary")

        val result = mergeUniqueActivitySources(
            indexedActivities = listOf(pending),
            temporaryActivities = listOf(local),
            getId = { it.stableId }
        )

        assertEquals(listOf(pending), result)
    }
}
