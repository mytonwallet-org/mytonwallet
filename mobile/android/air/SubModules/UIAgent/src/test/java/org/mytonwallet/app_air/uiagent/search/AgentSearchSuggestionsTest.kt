package org.mytonwallet.app_air.uiagent.search

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

class AgentSearchSuggestionsTest {
    @Test
    fun firstPageSearchUsesChatListOrderAndKeepsUpToNineRecentThreads() = runBlocking {
        val requests = mutableListOf<Pair<String?, String?>>()
        val older = thread("pinned", "2026-10-18T10:00:00.250Z").copy(isPinned = true)
        val latest = thread("latest", "2026-10-18T10:00:00.750Z")
        val remaining = (1..10).map {
            AgentV2ThreadListItem(thread("older-$it", "2026-10-17T10:00:00Z"))
        }
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { cursor, _, query ->
                requests.add(cursor to query)
                check(cursor == null) { "Search must not load additional thread pages" }
                AgentV2ThreadListResponse(
                    listOf(
                        AgentV2ThreadListItem(older),
                        AgentV2ThreadListItem(latest, "Latest reply")
                    ) + remaining,
                    "next"
                )
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )

        val recentResults = provider.search()
        val searchResults = provider.search("staking")

        assertEquals(listOf(null to null, null to "staking"), requests)
        assertEquals(
            listOf(
                "pinned", "latest", "older-1", "older-10", "older-2",
                "older-3", "older-4", "older-5", "older-6"
            ),
            recentResults.map { it.thread.id }
        )
        assertEquals(listOf("latest", "pinned"), searchResults.take(2).map { it.thread.id })
        assertEquals(12, searchResults.size)
        assertEquals("Latest reply", recentResults[1].subtitle)
    }

    @Test
    fun deliversRecentAndServerMatchedThreadsWithSupportedListRequestLimits() = runBlocking {
        val queries = mutableListOf<String?>()
        val latest = thread("latest", "2026-10-18T10:00:00Z")
        val matching = thread("matched-by-message", "2026-10-17T10:00:00Z").copy(
            title = "Portfolio"
        )
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, limit, query ->
                queries.add(query)
                require(limit in 1..50) { "invalid_request" }
                AgentV2ThreadListResponse(
                    listOf(AgentV2ThreadListItem(if (query == null) latest else matching))
                )
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )

        val recentResults = provider.search()
        val queryResults = provider.search("swaps")

        assertEquals(listOf(null, "swaps"), queries)
        assertEquals(listOf(latest), recentResults.map { it.thread })
        assertEquals(listOf(matching), queryResults.map { it.thread })
    }

    @Test
    fun preservesServerMatchesOutsideTitleAndPreviewAndTheirThreadTargets() = runBlocking {
        val queries = mutableListOf<String?>()
        val chosen = thread("chosen", "2026-10-18T10:00:00Z").copy(
            title = "Portfolio",
            icon = "💬",
            hasCustomTitle = true
        )
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, _, query ->
                queries.add(query)
                AgentV2ThreadListResponse(listOf(AgentV2ThreadListItem(chosen, "Latest answer")))
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )

        val results = provider.search("validator rewards")

        assertEquals(listOf("validator rewards"), queries)
        assertEquals(listOf(chosen), results.map { it.thread })
        assertEquals("Portfolio", results.single().title)
        assertEquals("💬", results.single().icon)
    }

    @Test
    fun cancelledQueryNeverReachesTheBackendAndRequestCancellationPropagates() = runBlocking {
        var requestCount = 0
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, _, _ ->
                requestCount++
                throw CancellationException()
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 1000
        )
        val pendingSearch = launch { provider.search("staking") }
        yield()
        pendingSearch.cancel()
        pendingSearch.join()
        assertEquals(0, requestCount)

        val activeSearch = launch { provider.search() }
        activeSearch.join()
        assertEquals(1, requestCount)
        assertTrue(activeSearch.isCancelled)
    }

    @Test
    fun cachedRecentThreadsRemainAvailableDuringRefreshAndFailedRequests() = runBlocking {
        val latest = thread("latest", "2026-10-18T10:00:00Z")
        val refresh = CompletableDeferred<AgentV2ThreadListResponse>()
        var requests = 0
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, _, _ ->
                requests++
                if (requests == 1) {
                    AgentV2ThreadListResponse(listOf(AgentV2ThreadListItem(latest)))
                } else {
                    refresh.await()
                }
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )
        val first = provider.search()
        val pending = async { provider.search() }
        yield()

        assertEquals(first, provider.cachedRecent)
        refresh.completeExceptionally(IllegalStateException("offline"))
        assertEquals(first, pending.await())
        assertEquals(2, requests)
        provider.resetRecent()
        assertEquals(null, provider.cachedRecent)
    }

    @Test
    fun deletedThreadCannotReturnFromAnInflightResponseOrFailedRefresh() = runBlocking {
        val deleted = thread("deleted", "2026-10-18T10:00:00Z")
        val retained = thread("retained", "2026-10-17T10:00:00Z")
        val original = AgentV2ThreadListResponse(
            listOf(AgentV2ThreadListItem(deleted), AgentV2ThreadListItem(retained))
        )
        val response = CompletableDeferred<AgentV2ThreadListResponse>()
        var requests = 0
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, _, _ ->
                when (++requests) {
                    1 -> original
                    2 -> response.await()
                    else -> throw IllegalStateException("offline")
                }
            },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )
        provider.search()
        val pending = async { provider.search() }
        yield()
        provider.removeRecent(deleted.id)
        assertEquals(listOf(retained), provider.cachedRecent?.map { it.thread })

        response.complete(original)
        try {
            pending.await()
            throw AssertionError("A pre-deletion response must not restore deleted chats")
        } catch (_: CancellationException) {
            assertEquals(listOf(retained), provider.cachedRecent?.map { it.thread })
        }

        assertEquals(listOf(retained), provider.search().map { it.thread })
        assertEquals(listOf(retained), provider.cachedRecent?.map { it.thread })
        assertEquals(3, requests)
    }

    @Test
    fun sessionResetDiscardsAnInflightRecentResponse() = runBlocking {
        val response = CompletableDeferred<AgentV2ThreadListResponse>()
        val provider = AgentThreadSearchProvider(
            hasConsent = { true },
            loadThreads = { _, _, _ -> response.await() },
            fallbackTitle = { "New Chat" },
            debounceMillis = 0
        )
        val pending = async { provider.search() }
        yield()
        provider.resetRecent()
        response.complete(
            AgentV2ThreadListResponse(
                listOf(AgentV2ThreadListItem(thread("previous-account", "2026-10-18T10:00:00Z")))
            )
        )
        try {
            pending.await()
            throw AssertionError("A previous session must not publish cached chats")
        } catch (_: CancellationException) {
            assertEquals(null, provider.cachedRecent)
        }
    }

    @Test
    fun doesNotReadThreadsWithoutConsent() = runBlocking {
        var requestCount = 0
        val loader: suspend (String?, Int, String?) -> AgentV2ThreadListResponse = { _, _, _ ->
            requestCount++
            AgentV2ThreadListResponse(emptyList(), "same-cursor")
        }
        val noConsent = AgentThreadSearchProvider({ false }, loader, { "New Chat" }, 0)
        assertTrue(noConsent.search().isEmpty())
        assertEquals(0, requestCount)
    }

    private fun thread(id: String, lastActivityAt: String) = AgentV2ThreadSummary(
        id = id,
        revision = 1,
        lastActivityAt = lastActivityAt,
        title = id
    )
}
