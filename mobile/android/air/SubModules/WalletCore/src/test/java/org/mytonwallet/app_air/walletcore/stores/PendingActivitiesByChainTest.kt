package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertEquals
import org.junit.Test

class PendingActivitiesByChainTest {
    private enum class Chain {
        TON,
        SOLANA
    }

    private data class PendingActivity(val id: String, val isPending: Boolean = true)

    @Test
    fun omittedPendingActivitiesKeepEveryChain() {
        val current = pendingByChain()

        assertEquals(current, replacePendingBucket(current, Chain.TON, null))
        assertEquals(current, replacePendingBucket(current, null, emptyList()))
    }

    @Test
    fun emptyPendingActivitiesClearOnlyTheirChain() {
        val result = replacePendingBucket(pendingByChain(), Chain.TON, emptyList())

        assertEquals(mapOf(Chain.SOLANA to listOf(PendingActivity("solana"))), result)
    }

    @Test
    fun pendingActivitiesReplaceOnlyTheirChain() {
        val replacement = listOf(PendingActivity("ton-next"))

        val result = replacePendingBucket(pendingByChain(), Chain.TON, replacement)

        assertEquals(replacement, result[Chain.TON])
        assertEquals(listOf(PendingActivity("solana")), result[Chain.SOLANA])
    }

    @Test
    fun explicitPendingUpdateSelectsPreviousChainIdsForRemoval() {
        val current = pendingByChain()

        assertEquals(
            setOf("ton"),
            selectPendingIdsToReplace(current, Chain.TON, emptyList()) { it.id }
        )
        assertEquals(
            setOf("ton"),
            selectPendingIdsToReplace(
                current,
                Chain.TON,
                listOf(PendingActivity("ton-next"))
            ) { it.id }
        )
    }

    @Test
    fun omittedPendingUpdateSelectsNoIdsForRemoval() {
        val current = pendingByChain()

        assertEquals(
            emptySet<String>(),
            selectPendingIdsToReplace(current, Chain.TON, null) { it.id }
        )
        assertEquals(
            emptySet<String>(),
            selectPendingIdsToReplace(current, null, emptyList()) { it.id }
        )
    }

    @Test
    fun patchRemovalsAndConfirmedUpsertsUpdateTheirExistingBuckets() {
        val current = mapOf(
            Chain.TON to listOf(PendingActivity("remove"), PendingActivity("confirm")),
            Chain.SOLANA to listOf(PendingActivity("solana"))
        )

        val result = applyPatchToPendingBuckets(
            current = current,
            removeIds = setOf("remove"),
            upsert = listOf(PendingActivity("confirm", isPending = false)),
            getId = { it.id },
            isPending = { it.isPending }
        )

        assertEquals(mapOf(Chain.SOLANA to listOf(PendingActivity("solana"))), result)
    }

    private fun pendingByChain() = mapOf(
        Chain.TON to listOf(PendingActivity("ton")),
        Chain.SOLANA to listOf(PendingActivity("solana"))
    )
}
