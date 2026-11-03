package org.mytonwallet.app_air.uiagent.viewControllers.news

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

class AgentNewsFeedModelTest {
    @Test
    fun firstPreviewInitializesInstallReadMarkAndFullUnreadPageShowsThirtyPlus() = runBlocking {
        var mark: String? = null
        val readState = AgentNewsReadState({ mark }, { mark = it })
        val initial = item(1, "2026-10-19T00:00:00Z")
        val client = FakeClient().apply {
            onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", listOf(initial)) }
        }
        val model = AgentNewsPreviewModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            readState,
            language = { "en" }
        )

        model.refresh()

        assertEquals(initial.deliveredAt, mark)
        assertEquals(0, model.unreadCount)

        val unread = (1..30).map {
            item(it, "2026-10-20T00:${it.toString().padStart(2, '0')}:00Z")
        }
        client.onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", unread.reversed()) }
        model.refresh()

        assertEquals(initial.deliveredAt, mark)
        assertEquals(unread.last(), model.latestItem)
        assertEquals(30, model.unreadCount)
        assertEquals("30+", formatAgentNewsUnreadCount(model.unreadCount))

        readState.markRead(unread)
        readState.markRead(listOf(initial))

        assertEquals(unread.last().deliveredAt, mark)
        assertEquals(0, model.unreadCount)
    }

    @Test
    fun unreadCountBadgeShowsTheNumberBelowAPageAndThirtyPlusFromAPage() {
        assertNull(formatAgentNewsUnreadCount(0))
        assertEquals("1", formatAgentNewsUnreadCount(1))
        assertEquals("29", formatAgentNewsUnreadCount(29))
        assertEquals("30+", formatAgentNewsUnreadCount(30))
        assertEquals("30+", formatAgentNewsUnreadCount(1000))
    }

    @Test
    fun paginationKeepsNewestDuplicateAndOriginalUnreadBoundaryWhileReadMarkOnlyGrows() =
        runBlocking {
            var mark: String? = "2026-10-18T00:00:00Z"
            val readState = AgentNewsReadState({ mark }, { mark = it })
            val older = item(1, "2026-10-19T00:00:00Z")
            val first = item(2, "2026-10-20T00:00:00Z")
            val second = item(3, "2026-10-21T00:00:00Z")
            val updatedSecond = second.copy(
                deliveredAt = "2026-10-22T00:00:00Z",
                headline = "Updated"
            )
            val client = FakeClient().apply {
                onGetFeed = { _, cursor ->
                    when (cursor) {
                        null -> AgentV2NewsFeedPage("en", listOf(second, first), "older")

                        "older" -> AgentV2NewsFeedPage(
                            "en",
                            listOf(
                                first.copy(deliveredAt = "2026-10-17T00:00:00Z"),
                                updatedSecond,
                                older
                            ),
                            "oldest"
                        )

                        else -> AgentV2NewsFeedPage("en", listOf(item(4, "2026-10-16T00:00:00Z")))
                    }
                }
            }
            val model = AgentNewsFeedModel(
                CoroutineScope(coroutineContext + Dispatchers.Unconfined),
                client,
                readState,
                language = { "en" }
            )

            model.refresh()

            assertEquals(listOf(2, 3), model.items.map { it.eventId })
            assertEquals(2, model.unreadEventId)
            assertEquals(second.deliveredAt, mark)

            model.loadMore()

            assertEquals(listOf(older, first, updatedSecond), model.items)
            assertEquals(1, model.unreadEventId)
            assertEquals(updatedSecond.deliveredAt, mark)

            model.loadMore()
            model.loadMore()

            assertEquals(listOf(4, 1, 2, 3), model.items.map { it.eventId })
            assertEquals(updatedSecond.deliveredAt, mark)
            assertEquals(1, model.unreadEventId)
            assertEquals(listOf(null, "older", "oldest"), client.cursors)
            assertNull(model.nextCursor)
            assertFalse(model.isLoadingMore)
        }

    @Test
    fun refreshReplacesHistoryAcrossGapAndLoadsMissingItemsFromNewCursor() = runBlocking {
        val initial = (1..30).map {
            item(it, "2026-10-19T00:${it.toString().padStart(2, '0')}:00Z")
        }
        val missing = (31..41).map {
            item(it, "2026-10-19T00:${it.toString().padStart(2, '0')}:00Z")
        }
        val fresh = (42..71).map {
            item(it, "2026-10-20T00:${(it - 42).toString().padStart(2, '0')}:00Z")
        }
        var mark: String? = initial.last().deliveredAt
        var resets = 0
        val client = FakeClient().apply {
            onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", initial.reversed(), "older") }
        }
        val model = AgentNewsFeedModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" }
        ).apply {
            onReset = { resets++ }
        }
        model.refresh()
        client.onGetFeed = { _, cursor ->
            if (cursor == null) {
                AgentV2NewsFeedPage("en", fresh.reversed(), "missing")
            } else {
                AgentV2NewsFeedPage("en", missing.reversed())
            }
        }

        model.refresh()

        assertEquals(fresh, model.items)
        assertEquals("missing", model.nextCursor)
        assertEquals(1, resets)
        assertEquals(42, model.unreadEventId)
        assertEquals(fresh.last().deliveredAt, mark)

        model.loadMore()

        assertEquals(missing + fresh, model.items)
        assertEquals(31, model.unreadEventId)
        assertEquals(listOf(null, null, "missing"), client.cursors)
        assertNull(model.nextCursor)
    }

    @Test
    fun refreshWithOverlapKeepsOlderHistoryAndViewport() = runBlocking {
        val allItems = (1..45).map {
            item(it, "2026-10-20T00:${it.toString().padStart(2, '0')}:00Z")
        }
        var mark: String? = allItems[29].deliveredAt
        var resets = 0
        val client = FakeClient().apply {
            onGetFeed = { _, _ ->
                AgentV2NewsFeedPage("en", allItems.take(30).reversed(), "older")
            }
        }
        val model = AgentNewsFeedModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" }
        ).apply {
            onReset = { resets++ }
        }
        model.refresh()
        client.onGetFeed = { _, _ ->
            AgentV2NewsFeedPage("en", allItems.drop(15).reversed(), "refreshed-older")
        }

        model.refresh()

        assertEquals(allItems, model.items)
        assertEquals("refreshed-older", model.nextCursor)
        assertEquals(0, resets)
    }

    @Test
    fun paginationLocaleChangeClearsHistoryAndReloadsCurrentLanguageWithoutOldCursor() =
        runBlocking {
            var mark: String? = "2026-10-18T00:00:00Z"
            var language = "en"
            var resets = 0
            val pending = CompletableDeferred<AgentV2NewsFeedPage>()
            val requests = mutableListOf<Pair<String, String?>>()
            val initial = item(1, "2026-10-19T00:00:00Z")
            val fresh = item(2, "2026-10-20T00:00:00Z")
            val older = item(3, "2026-10-18T00:00:00Z")
            val client = FakeClient().apply {
                onGetFeed = { lang, cursor ->
                    requests.add(lang to cursor)
                    when {
                        cursor == "older" -> AgentV2NewsFeedPage("ru", emptyList(), "ignored")
                        cursor == "new-older" -> AgentV2NewsFeedPage("ru", listOf(older))
                        lang == "en" -> AgentV2NewsFeedPage("en", listOf(initial), "older")
                        else -> pending.await()
                    }
                }
            }
            val model = AgentNewsFeedModel(
                CoroutineScope(coroutineContext + Dispatchers.Unconfined),
                client,
                AgentNewsReadState({ mark }, { mark = it }),
                language = { language }
            ).apply {
                onReset = { resets++ }
            }
            model.refresh()
            language = "ru"

            model.loadMore()

            assertTrue(model.items.isEmpty())
            assertNull(model.nextCursor)
            assertNull(model.unreadEventId)
            assertTrue(model.isLoading)
            assertFalse(model.isLoadingMore)
            assertEquals(1, resets)
            assertEquals(listOf("en" to null, "en" to "older", "ru" to null), requests)

            pending.complete(AgentV2NewsFeedPage("ru", listOf(fresh), "new-older"))

            assertEquals(listOf(fresh), model.items)
            assertEquals("ru", model.locale)
            assertEquals("new-older", model.nextCursor)
            assertEquals(2, model.unreadEventId)
            assertFalse(model.isLoading)

            model.loadMore()

            assertEquals(listOf(older, fresh), model.items)
            assertEquals("ru" to "new-older", requests.last())
            assertEquals(1, client.cursors.count { it == "older" })
            assertNull(model.nextCursor)
        }

    @Test
    fun refreshCancelsOlderPageBeforeItCanChangeItemsOrReadMark() = runBlocking {
        var mark: String? = "2026-10-18T00:00:00Z"
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        val initial = item(1, "2026-10-19T00:00:00Z")
        val fresh = item(2, "2026-10-20T00:00:00Z")
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage("en", listOf(initial), "older")
                } else {
                    withContext(NonCancellable) { pending.await() }
                }
            }
        }
        val model = AgentNewsFeedModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" }
        )
        model.refresh()
        model.loadMore()

        client.onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", listOf(fresh, initial)) }
        model.refresh()
        pending.complete(
            AgentV2NewsFeedPage("en", listOf(item(3, "2026-10-25T00:00:00Z")), "stale")
        )

        assertEquals(listOf(initial, fresh), model.items)
        assertEquals(fresh.deliveredAt, mark)
        assertNull(model.nextCursor)
        assertFalse(model.isLoading)
        assertFalse(model.isLoadingMore)
    }

    @Test
    fun localDiscussionsSurviveOlderPagesAndDeletionRemovesOnlyMatchingThread() = runBlocking {
        var mark: String? = null
        val recent = item(2, "2026-10-20T00:00:00Z")
        val older = item(1, "2026-10-19T00:00:00Z")
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage("en", listOf(recent), "older")
                } else {
                    AgentV2NewsFeedPage("en", listOf(older))
                }
            }
        }
        val model = AgentNewsFeedModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" }
        )
        val olderThread = AgentV2ThreadSummary("older-thread", revision = 1, icon = "📰")
        val recentThread = AgentV2ThreadSummary("recent-thread", revision = 1, icon = "💡")

        model.refresh()
        model.markDiscussion(older.eventId, olderThread)
        model.markDiscussion(recent.eventId, recentThread)
        model.loadMore()

        assertEquals(
            AgentV2NewsFeedItem.Discussion(olderThread.id, olderThread.icon),
            model.items.first().discussion
        )

        model.removeDiscussion(olderThread.id)
        model.refresh()
        model.loadMore()

        assertNull(model.items.first().discussion)
        assertEquals(
            AgentV2NewsFeedItem.Discussion(recentThread.id, recentThread.icon),
            model.items.last().discussion
        )
    }

    private fun item(id: Int, deliveredAt: String) = AgentV2NewsFeedItem(
        eventId = id,
        deliveredAt = deliveredAt,
        headline = "News $id",
        body = "Body $id",
        sources = emptyList()
    )

    private class FakeClient : AgentNewsFeedClient {
        val cursors = mutableListOf<String?>()
        var onGetFeed: suspend (String, String?) -> AgentV2NewsFeedPage = { _, _ ->
            AgentV2NewsFeedPage("en", emptyList())
        }

        override suspend fun getNewsFeed(lang: String, cursor: String?): AgentV2NewsFeedPage {
            cursors.add(cursor)
            return onGetFeed(lang, cursor)
        }
    }
}
