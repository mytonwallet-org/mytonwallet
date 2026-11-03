package org.mytonwallet.app_air.uibrowser.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.search.AgentThreadSearchResult
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

class AgentThreadSearchResultsTest {
    @Test
    fun queryDisplaysAllMatchingThreadsAndPreservesTheirThreadTarget() {
        val latest = result("latest")
        val older = result("older")
        val threads = listOf(latest, older)

        val visible = selectVisibleAgentThreads("staking", "staking", threads)

        assertEquals(listOf("latest", "older"), visible.map { it.thread.id })
        assertSame(older, visible[1])
    }

    @Test
    fun emptyQueryDisplaysUpToNineRecentThreadsInTheirListOrder() {
        val threads = (1..12).map { result("thread-$it") }

        val visible = selectVisibleAgentThreads("", "", threads)

        assertEquals((1..9).map { "thread-$it" }, visible.map { it.thread.id })
        assertSame(threads[8], visible[8])
        assertEquals(threads.take(3), selectVisibleAgentThreads("", "", threads.take(3)))
    }

    @Test
    fun queryChangeHidesOldThreadRoutesUntilItsResultsArrive() {
        val threads = listOf(result("old-query-thread"))

        assertTrue(selectVisibleAgentThreads("staking", "portfolio", threads).isEmpty())
        assertTrue(selectVisibleAgentThreads(null, "staking", threads).isEmpty())
    }

    @Test
    fun walletDataRefreshNeverPublishesEmptyChatsForTheSameKeyword() {
        for (keyword in listOf("", "staking")) {
            val published = mutableListOf<ExploreVM.SearchResult>()
            val first = ExploreVM.ActiveSearchRequest(keyword, published::add)
            first.publishLocalResult(ExploreVM.SearchResult(keyword))
            val chats = listOf(result("latest"), result("older"))
            first.publishResult(first.result!!.withRecentChats(chats))
            published.clear()

            val refresh = ExploreVM.ActiveSearchRequest(
                keyword,
                published::add,
                previous = first
            )
            refresh.publishLocalResult(
                ExploreVM.SearchResult(keyword, recentSearches = emptyList())
            )
            refresh.publishResult(refresh.result!!.withRecentChats(chats))

            assertEquals(1, published.size)
            assertEquals(chats, published.single().recentChats)
        }
    }

    @Test
    fun openingSearchSeedsItsFirstResultFromCacheAndNewQueriesDiscardOldMatches() {
        val chats = listOf(result("cached"))
        val published = mutableListOf<ExploreVM.SearchResult>()
        val recent = ExploreVM.ActiveSearchRequest("", published::add, cachedRecent = chats)
        recent.publishLocalResult(ExploreVM.SearchResult(""))
        assertEquals(chats, published.single().recentChats)

        val query = ExploreVM.ActiveSearchRequest("staking", published::add, previous = recent)
        query.publishLocalResult(ExploreVM.SearchResult("staking"))
        assertTrue(published.last().recentChats.isNullOrEmpty())
    }

    @Test
    fun repeatedPendingAddressSearchPublishesItsFirstResultToRestartTheLookup() {
        val keyword = "wallet.ton"
        val published = mutableListOf<ExploreVM.SearchResult>()
        val onResult: (ExploreVM.SearchResult) -> Unit = { published.add(it) }
        val pending = ExploreVM.SearchResult(keyword, isWalletInfoLookupPending = true)
        val first = ExploreVM.ActiveSearchRequest(keyword, onResult)
        first.publishLocalResult(pending)
        assertEquals(1, published.size)

        val repeated = ExploreVM.ActiveSearchRequest(keyword, onResult, previous = first)
        repeated.publishLocalResult(pending)
        assertEquals(2, published.size)
        assertTrue(published.last().isWalletInfoLookupPending)

        repeated.publishResult(repeated.result!!)
        assertEquals(2, published.size)
        val completed = repeated.result!!.copy(isWalletInfoLookupPending = false)
        repeated.publishResult(completed)
        assertEquals(completed, published.last())

        val completedRepeat = ExploreVM.ActiveSearchRequest(
            keyword,
            onResult,
            previous = repeated
        )
        completedRepeat.publishLocalResult(completed)
        assertEquals(3, published.size)
    }

    @Test
    fun newConsumerReceivesSeededChatsWhileTheSameConsumerKeepsUnchangedResults() {
        val chats = listOf(result("cached"))
        val firstResults = mutableListOf<ExploreVM.SearchResult>()
        val firstConsumer: (ExploreVM.SearchResult) -> Unit = { firstResults.add(it) }
        val first = ExploreVM.ActiveSearchRequest("", firstConsumer, cachedRecent = chats)
        first.publishLocalResult(ExploreVM.SearchResult(""))

        val refresh = ExploreVM.ActiveSearchRequest("", firstConsumer, previous = first)
        refresh.publishLocalResult(ExploreVM.SearchResult(""))
        assertEquals(1, firstResults.size)

        val replacementResults = mutableListOf<ExploreVM.SearchResult>()
        val replacement = ExploreVM.ActiveSearchRequest(
            "",
            replacementResults::add,
            previous = refresh
        )
        replacement.publishLocalResult(ExploreVM.SearchResult(""))
        replacement.publishResult(replacement.result!!.withRecentChats(chats))

        assertEquals(1, replacementResults.size)
        assertEquals(chats, replacementResults.single().recentChats)
    }

    private fun result(id: String) = AgentThreadSearchResult(
        thread = AgentV2ThreadSummary(id, revision = 1),
        title = id,
        subtitle = "Answer"
    )
}
