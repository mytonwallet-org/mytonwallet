package org.mytonwallet.app_air.walletcore.stores

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

class ActivityReconciliationContextTest {
    private data class Activity(
        val id: String,
        val isLocal: Boolean = false,
        val isVisible: Boolean = true
    )

    @Test
    fun selectsOnlyBoundedNonLocalMainActivities() {
        val byId = mapOf(
            "local:local" to Activity("local:local", isLocal = true),
            "recent-1" to Activity("recent-1"),
            "recent-2" to Activity("recent-2"),
            "deep" to Activity("deep"),
            "token-only" to Activity("token-only")
        )

        val result = selectRecentNonLocalActivities(
            ids = listOf("local:local", "missing", "recent-1", "recent-2", "deep"),
            byId = byId,
            maxCount = 2,
            isLocal = { it.isLocal }
        )

        assertEquals(listOf("recent-1", "recent-2"), result.map { it.id })
    }

    @Test
    fun selectsOnlyChangedVisibleActivitiesForNotification() {
        val byId = mapOf(
            "changed" to Activity("changed"),
            "hidden" to Activity("hidden", isVisible = false),
            "unchanged" to Activity("unchanged")
        )

        val result = selectUpdatedVisibleActivities(
            updatedIds = listOf("removed", "hidden", "changed"),
            byId = byId,
            isVisible = { it.isVisible }
        )

        assertEquals(listOf("changed"), result.map { it.id })
    }

    @Test
    fun propagatesChainedStableIdToPendingAndPatchInstances() {
        val previousPending = transaction("pending-1").also {
            it.replacedStableId = "local"
        }
        val reconciledPending = transaction("pending-2")
        val authoritativeUpsert = transaction("pending-2")

        processReplacedStableIdsFromSdkPatch(
            previousActivities = listOf(previousPending),
            replacementActivities = listOf(reconciledPending, authoritativeUpsert),
            replacedIds = mapOf(previousPending.id to reconciledPending.id)
        )

        assertEquals(
            listOf("local", "local"),
            listOf(reconciledPending.getStableId(), authoritativeUpsert.getStableId())
        )
    }

    @Test
    fun preservesLocalStableIdWhenLocalActivityArrivesFirst() {
        val local = transaction("local")
        val pending = transaction("pending")

        processReplacedStableIdsFromSdkPatch(
            previousActivities = listOf(local),
            replacementActivities = listOf(pending),
            replacedIds = mapOf(local.id to pending.id)
        )

        assertEquals(local.id, pending.getStableId())
    }

    @Test
    fun preservesPendingStableIdWhenPendingActivityArrivesFirst() {
        val lateLocal = transaction("local")
        val visiblePending = transaction("pending")
        val authoritativePending = transaction("pending")

        processReplacedStableIdsFromSdkPatch(
            previousActivities = listOf(lateLocal),
            replacementActivities = listOf(authoritativePending),
            replacedIds = mapOf(lateLocal.id to authoritativePending.id),
            visibleReplacementActivities = listOf(visiblePending)
        )

        assertEquals(visiblePending.id, authoritativePending.getStableId())
    }

    private fun transaction(id: String) = MApiTransaction.Transaction(
        id = id,
        externalMsgHashNorm = null,
        timestamp = 1,
        amount = BigInteger.ONE,
        fromAddress = "from",
        toAddress = "to",
        fee = BigInteger.ZERO,
        slug = "toncoin",
        isIncoming = false,
        normalizedAddress = "to",
        status = ApiTransactionStatus.PENDING
    )
}
