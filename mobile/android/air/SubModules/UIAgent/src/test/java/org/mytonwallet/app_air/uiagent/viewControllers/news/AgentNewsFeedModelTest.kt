package org.mytonwallet.app_air.uiagent.viewControllers.news

import java.lang.reflect.Proxy
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationOutcome

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
            language = { "en" },
            digestSchedule = { SCHEDULE }
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
        assertNull(formatAgentNewsUnreadCount(model.unreadCount))

        readState.markRead(unread)
        readState.markRead(listOf(initial))

        assertEquals(unread.last().deliveredAt, mark)
        assertEquals(0, model.unreadCount)
    }

    @Test
    fun unreadCountBadgeShowsTheNumberUpToTenAndOnlyTheDotAboveIt() {
        assertNull(formatAgentNewsUnreadCount(0))
        assertEquals("1", formatAgentNewsUnreadCount(1))
        assertEquals("10", formatAgentNewsUnreadCount(10))
        assertNull(formatAgentNewsUnreadCount(11))
        assertNull(formatAgentNewsUnreadCount(1000))
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
                createFeedScope(this),
                client,
                readState,
                language = { "en" },
                digestSchedule = { SCHEDULE }
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
            createFeedScope(this),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" },
            digestSchedule = { SCHEDULE }
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
            createFeedScope(this),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" },
            digestSchedule = { SCHEDULE }
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
    fun loadMoreSkipsRepeatedPagesAfterRefreshEvenWhenPrefetchIsComplete() = runBlocking {
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                when (cursor) {
                    null -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-11-10T20:00:00Z")),
                        "p2",
                        listOf(
                            digest("en:2026-11-10T18:00:00.000Z"),
                            digest("en:2026-11-09T18:00:00.000Z")
                        )
                    )

                    "p2" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(2, "2026-11-09T17:00:00Z")),
                        "p3"
                    )

                    "p3" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(1, "2026-11-08T17:00:00Z")),
                        "p4"
                    )

                    else -> AgentV2NewsFeedPage("en", listOf(item(0, "2026-11-07T17:00:00Z")))
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { SCHEDULE }
        )
        model.refresh()
        model.loadMore()
        model.loadMore()
        repeat(2) { yield() }
        assertEquals(listOf(1, 2, 3), model.items.map { it.eventId })
        assertEquals(listOf(null, "p2", "p3"), client.cursors)

        model.refresh()
        repeat(2) { yield() }
        model.loadMore()
        repeat(3) { yield() }

        assertEquals(listOf(null, "p2", "p3", null, "p2", "p3", "p4"), client.cursors)
        assertEquals(listOf(0, 1, 2, 3), model.items.map { it.eventId })
        assertNull(model.nextCursor)
        assertFalse(model.isLoadingMore)
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
                createFeedScope(this),
                client,
                AgentNewsReadState({ mark }, { mark = it }),
                language = { language },
                digestSchedule = { SCHEDULE }
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
            createFeedScope(this),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" },
            digestSchedule = { SCHEDULE }
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
    fun emptyFeedStaysEmptyWhileItReadsTheNewsAgainUntilTheyCome() = runBlocking {
        var mark: String? = null
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient()
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" },
            digestSchedule = { SCHEDULE }
        )
        assertFalse(model.isEmpty)

        model.refresh()

        assertTrue(model.hasLoaded)
        assertTrue(model.isEmpty)
        assertFalse(model.isLoading)

        client.onGetFeed = { _, _ -> error("Offline") }
        model.refresh()

        assertFalse(model.isEmpty)
        assertNotNull(model.error)

        client.onGetFeed = { _, _ -> pending.await() }
        model.refresh()

        assertTrue(model.isLoading)
        assertTrue(model.hasLoaded)
        assertTrue(model.isEmpty)

        val news = item(1, "2026-10-20T00:00:00Z")
        pending.complete(AgentV2NewsFeedPage("en", listOf(news)))

        assertEquals(listOf(news), model.items)
        assertFalse(model.isEmpty)
        assertFalse(model.isLoading)
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
            createFeedScope(this),
            client,
            AgentNewsReadState({ mark }, { mark = it }),
            language = { "en" },
            digestSchedule = { SCHEDULE }
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

    @Test
    fun liveFeedRequestsCarryTheScheduleTheirPagesFollowAndPaginationRefreshesForANewOne() =
        runBlocking {
            val requests = mutableListOf<String>()
            var schedule = SCHEDULE
            val client = LiveAgentNewsFeedClient(
                call = {
                    requests += it.arguments
                    AgentV2NewsFeedPage("ru", emptyList(), "older")
                }
            )
            val readState = AgentNewsReadState({ null }, {})
            val preview = AgentNewsPreviewModel(
                this,
                client,
                readState,
                language = { "ru-RU" },
                digestSchedule = { schedule }
            )
            val model = AgentNewsFeedModel(
                this,
                client,
                readState,
                language = { "ru-RU" },
                digestSchedule = { schedule }
            )
            preview.refresh()
            kotlinx.coroutines.yield()
            model.refresh()
            kotlinx.coroutines.yield()
            // Older pages of another schedule refresh the feed with the new one first
            schedule = AgentNewsDigestSchedule(19, "Asia/Tbilisi")
            model.loadMore()
            kotlinx.coroutines.yield()
            assertEquals(3, requests.size)
            model.loadMore()
            kotlinx.coroutines.yield()

            assertEquals(4, requests.size)
            assertEquals(
                """[{"lang":"ru-RU","digestHour":21,"timeZone":"Europe/Moscow"}]""",
                requests.first()
            )
            assertEquals(requests.first(), requests[1])
            assertEquals(
                """[{"lang":"ru-RU","digestHour":19,"timeZone":"Asia/Tbilisi"}]""",
                requests[2]
            )
            assertEquals(
                """[{"lang":"ru-RU","cursor":"older","digestHour":19,"timeZone":"Asia/Tbilisi"}]""",
                requests.last()
            )
        }

    @Test
    fun newDigestScheduleDropsTheOldDigestsAndTheirPagesAndKeepsTheNews() = runBlocking {
        var schedule = SCHEDULE
        val evening = digest("en:2026-11-08T18:00:00.000Z")
        val morning = digest("en:2026-11-08T06:00:00.000Z")
        val news = item(1, "2026-11-08T19:00:00Z")
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient().apply {
            onGetFeed =
                { _, _ -> AgentV2NewsFeedPage("en", listOf(news), "older", listOf(evening)) }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { schedule }
        )
        model.refresh()
        assertEquals(
            listOf(AgentNewsFeedEntry.Digest(evening), AgentNewsFeedEntry.News(news)),
            model.entries
        )

        schedule = AgentNewsDigestSchedule(9, "Europe/Moscow")
        client.onGetFeed = { _, _ -> pending.await() }
        model.refresh()

        assertEquals(listOf(AgentNewsFeedEntry.News(news)), model.entries)
        assertNull(model.nextCursor)
        pending.complete(AgentV2NewsFeedPage("en", listOf(news), "older", listOf(morning)))
        assertEquals(
            listOf(AgentNewsFeedEntry.Digest(morning), AgentNewsFeedEntry.News(news)),
            model.entries
        )
        assertEquals(listOf(SCHEDULE, schedule), client.schedules)
    }

    @Test
    fun requestedDigestLoadsOlderPagesUntilItComesAlsoAfterTheFeedsOwnPagination() = runBlocking {
        val requested = digest("en:2026-10-20T10:01:30.000Z")
        val firstOlderPage = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                when (cursor) {
                    null -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-10-20T13:00:00Z")),
                        "older1"
                    )

                    "older1" -> firstOlderPage.await()

                    else -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(1, "2026-10-20T10:00:00Z")),
                        "older3",
                        listOf(requested)
                    )
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            requestedDigestId = requested.id,
            digestSchedule = { SCHEDULE }
        )

        model.refresh()
        // The feed's own pagination waits for the page the search asked for, and the search goes on from it
        model.loadMore()
        assertTrue(model.isLoadingMore)
        firstOlderPage.complete(
            AgentV2NewsFeedPage("en", listOf(item(2, "2026-10-20T12:00:00Z")), "older2")
        )
        repeat(2) { yield() }

        assertEquals(listOf(null, "older1", "older2"), client.cursors)
        assertTrue(model.hasRequestedDigest)
        assertTrue(model.isSeekingRequestedDigest)
        assertEquals("older3", model.nextCursor)
        assertFalse(model.canLoadRequestedDigest)

        // The feed scrolls to it and ends the search
        model.stopSeekingRequestedDigest()
        model.refresh()
        assertFalse(model.isSeekingRequestedDigest)
        assertEquals(listOf(null, "older1", "older2", null), client.cursors)
    }

    @Test
    fun requestedDigestSearchStopsPastTheDigestAtTheLastPageAfterAFailureOrForAnUnreadableId() =
        runBlocking {
            val id = "en:2026-10-20T11:00:00.000Z"
            suspend fun search(
                requestedDigestId: String,
                page: suspend (String?) -> AgentV2NewsFeedPage
            ): Pair<AgentNewsFeedModel, FakeClient> {
                val client = FakeClient().apply { onGetFeed = { _, cursor -> page(cursor) } }
                val model = AgentNewsFeedModel(
                    createFeedScope(this),
                    client,
                    AgentNewsReadState({ null }, {}),
                    language = { "en" },
                    requestedDigestId = requestedDigestId,
                    digestSchedule = { SCHEDULE }
                )
                model.refresh()
                return model to client
            }
            val afterTheDigest =
                AgentV2NewsFeedPage("en", listOf(item(2, "2026-10-20T12:00:00Z")), "older")

            // The loaded news reach back past the digest's window
            val (past, pastClient) = search(id) {
                AgentV2NewsFeedPage(
                    "en",
                    listOf(item(2, "2026-10-20T12:00:00Z"), item(1, "2026-10-20T10:00:00Z")),
                    "older"
                )
            }
            assertFalse(past.isSeekingRequestedDigest)
            assertEquals(listOf<String?>(null), pastClient.cursors)

            // The feed has no older pages
            val (last, _) = search(id) {
                AgentV2NewsFeedPage("en", listOf(item(2, "2026-10-20T12:00:00Z")))
            }
            assertFalse(last.isSeekingRequestedDigest)

            // An older page that fails ends the search and keeps its cursor for the feed's own pagination
            val (failed, failedClient) = search(id) { cursor ->
                if (cursor == null) afterTheDigest else error("Offline")
            }
            assertFalse(failed.isSeekingRequestedDigest)
            assertEquals(listOf(null, "older"), failedClient.cursors)
            assertEquals("older", failed.nextCursor)

            // A time the id doesn't carry readably can't be placed among the pages
            val (unreadable, unreadableClient) = search("en:yesterday") { afterTheDigest }
            assertFalse(unreadable.isSeekingRequestedDigest)
            assertEquals(listOf<String?>(null), unreadableClient.cursors)
            assertEquals("older", unreadable.nextCursor)
        }

    @Test
    fun digestsMergeBetweenNewsByDeliveryTimeAndRequestedDigestSurvivesReload() = runBlocking {
        val digest = AgentV2NewsFeedDigest(
            "ru:2026-11-08T18:00:00.000Z",
            "2026-11-08T18:00:00.000Z",
            listOf(AgentV2NewsDigestHeadline(42, "Headline")),
            7
        )
        val olderDigest = digest.copy(
            id = "ru:2026-11-07T18:00:00.000Z",
            deliveredAt = "2026-11-07T18:00:00.000Z"
        )
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage(
                        "ru",
                        listOf(item(2, "2026-11-08T19:00:00Z")),
                        "older",
                        listOf(digest)
                    )
                } else {
                    AgentV2NewsFeedPage(
                        "ru",
                        listOf(item(1, "2026-11-08T17:00:00Z")),
                        digests = listOf(olderDigest)
                    )
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "ru" },
            requestedDigestId = digest.id,
            digestSchedule = { SCHEDULE }
        )
        model.refresh()
        model.loadMore()
        assertEquals(
            listOf(
                AgentNewsFeedEntry.Digest(olderDigest),
                AgentNewsFeedEntry.News(model.items.first()),
                AgentNewsFeedEntry.Digest(digest),
                AgentNewsFeedEntry.News(model.items.last())
            ),
            model.entries
        )
        model.refresh()
        assertEquals(4, model.entries.size)
        assertEquals(digest.id, model.requestedDigestId)
        client.onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", emptyList()) }
        model.refresh()
        assertTrue(model.entries.isEmpty())
        assertEquals(digest.id, model.requestedDigestId)
    }

    @Test
    fun digestCardShowsHowManyNewsItCoversItsHeadlinesAndTheNewsItLeavesOut() = withEnglishCopy {
        val headlines = listOf(
            AgentV2NewsDigestHeadline(1, "Binance restored its tokens"),
            AgentV2NewsDigestHeadline(2, "BlackRock sold Bitcoin")
        )
        val digest = AgentV2NewsFeedDigest(
            "en:2026-11-08T18:00:00.000Z",
            "2026-11-08T18:00:00.000Z",
            headlines,
            26
        )

        val card = AgentNewsDigestCardContent(digest, "21:00")

        assertEquals("Top stories of the day", card.title)
        assertEquals("26 stories · 21:00", card.meta)
        assertEquals(headlines, card.headlines)
        assertEquals("and 24 more — they're above in the feed", card.remainder)
        val single =
            AgentNewsDigestCardContent(digest.copy(top = headlines.take(1), total = 1), "9:00")
        assertEquals("1 story · 9:00", single.meta)
        assertNull(single.remainder)
    }

    @Test
    fun digestOpensItsHeadlinesNewsAndItsDiscussionOneChatAtATime() {
        val loaded = item(1, "2026-11-08T17:00:00Z")
        val inFeed = AgentV2NewsDigestHeadline(1, "News 1")
        val elsewhere = AgentV2NewsDigestHeadline(42, "Elsewhere")
        assertEquals(
            AgentNewsChatTarget.FeedNews(loaded),
            resolveAgentDigestHeadlineTarget(inFeed, listOf(loaded))
        )
        assertEquals(
            AgentNewsChatTarget.News(elsewhere),
            resolveAgentDigestHeadlineTarget(elsewhere, listOf(loaded))
        )

        val thread = AgentV2ThreadSummary("digest-thread", revision = 1, messageCount = 2)
        val discussed = digest("en:2026-11-08T18:00:00.000Z")
            .copy(discussion = AgentV2NewsFeedItem.Discussion(thread.id))
        val fresh = digest("en:2026-11-07T18:00:00.000Z")
        assertEquals(
            AgentNewsChatTarget.Discussion(thread),
            resolveAgentDigestDiscussionTarget(discussed) { id -> thread.takeIf { it.id == id } }
        )
        // A discussion the user hasn't written in opens as a visit, as one without a thread does
        assertEquals(
            AgentNewsChatTarget.Digest(discussed.id),
            resolveAgentDigestDiscussionTarget(discussed) { null }
        )
        assertEquals(
            AgentNewsChatTarget.Digest(fresh.id),
            resolveAgentDigestDiscussionTarget(fresh) { error("Nothing to find") }
        )

        val gate = AgentNewsChatGate()
        var openings = 0
        repeat(3) {
            gate.open {
                openings++
                true
            }
        }
        assertEquals(1, openings)
        // The feed shows again after the chat, and an opening that could not push its chat lets a tap retry
        gate.release()
        gate.open {
            openings++
            false
        }
        gate.open {
            openings++
            true
        }
        gate.open { error("A chat is opening") }
        assertEquals(3, openings)
        // An opening that threw releases the tap too
        gate.release()
        assertThrows(IllegalStateException::class.java) { gate.open { error("No chat") } }
        gate.open {
            openings++
            true
        }
        assertEquals(4, openings)
    }

    @Test
    fun digestSheetAppliesChoicesAndHourAndKeepsThePreviousChoiceWhenOneFails() = runBlocking {
        withEnglishCopy {
            val settings = DigestSettingsStub()
            var errors = 0
            val sheet = AgentDigestSettingsModel(settings) { errors++ }
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertEquals(
                "At 21:00, the top news in one notification",
                sheet.hint(AgentNewsNotificationMode.Digest)
            )

            sheet.selectMode(AgentNewsNotificationMode.Digest)
            sheet.selectMode(AgentNewsNotificationMode.News)
            sheet.selectMode(AgentNewsNotificationMode.Off)
            sheet.selectHour(7)
            assertEquals(
                listOf(
                    AgentNewsNotificationMode.Digest,
                    AgentNewsNotificationMode.News,
                    AgentNewsNotificationMode.Off
                ),
                settings.modes
            )
            assertEquals(listOf(7), settings.hours)
            assertEquals(
                "At 07:00, the top news in one notification",
                sheet.hint(AgentNewsNotificationMode.Digest)
            )

            settings.outcome = AgentNewsNotificationOutcome.PermissionDenied
            sheet.selectMode(AgentNewsNotificationMode.News)
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertTrue(sheet.isPermissionDenied)
            assertEquals(0, errors)

            settings.outcome = AgentNewsNotificationOutcome.Failed
            sheet.selectMode(AgentNewsNotificationMode.Digest)
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertFalse(sheet.isPermissionDenied)
            assertEquals(1, errors)

            // While a choice is applied no other is taken
            settings.outcome = AgentNewsNotificationOutcome.Ok
            val choice = CompletableDeferred<Unit>().also { settings.pending = it }
            val applying = launch(Dispatchers.Unconfined) {
                sheet.selectMode(AgentNewsNotificationMode.Digest)
            }
            assertEquals(AgentNewsNotificationMode.Digest, sheet.pendingMode)
            sheet.selectMode(AgentNewsNotificationMode.News)
            choice.complete(Unit)
            applying.join()
            assertEquals(AgentNewsNotificationMode.Digest, settings.modes.last())
            assertEquals(6, settings.modes.size)
            assertEquals(AgentNewsNotificationMode.Digest, sheet.mode)
            assertNull(sheet.pendingMode)

            // While an hour is applied no other is taken; one that fails to apply stays, as the settings keep it
            settings.outcome = AgentNewsNotificationOutcome.Failed
            val hour = CompletableDeferred<Unit>().also { settings.pending = it }
            val applyingHour = launch(Dispatchers.Unconfined) { sheet.selectHour(8) }
            assertTrue(sheet.isApplyingHour)
            sheet.selectHour(10)
            hour.complete(Unit)
            applyingHour.join()
            assertEquals(listOf(7, 8), settings.hours)
            assertEquals(8, sheet.digestHour)
            assertFalse(sheet.isApplyingHour)
            assertEquals(2, errors)
        }
    }

    @Test
    fun prefetchLoadsOnlyUntilTwoDigestsAndRechecksAfterFirstPageRefresh() = runBlocking {
        val recent = digest("en:2026-11-10T18:00:00.000Z")
        val previous = digest("en:2026-11-09T18:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                when (cursor) {
                    null -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(4, "2026-11-10T20:00:00Z")),
                        "older1"
                    )

                    "older1" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-11-10T17:00:00Z")),
                        "older2",
                        listOf(recent)
                    )

                    "older2" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-11-10T17:00:00Z")),
                        "older3",
                        listOf(recent, previous)
                    )

                    else -> AgentV2NewsFeedPage("en", listOf(item(1, "2026-11-09T16:00:00Z")))
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { SCHEDULE }
        )

        model.refresh()
        repeat(4) { yield() }

        assertEquals(listOf(null, "older1", "older2"), client.cursors)
        assertEquals(2, model.entries.count { it is AgentNewsFeedEntry.Digest })
        assertEquals("older3", model.nextCursor)
        assertFalse(model.isLoadingMore)

        client.onGetFeed = { _, _ ->
            AgentV2NewsFeedPage("ru", listOf(item(5, "2026-11-10T21:00:00Z")), "refreshed")
        }
        model.refresh()
        repeat(3) { yield() }

        assertEquals(listOf(null, "older1", "older2", null, "refreshed"), client.cursors)
        assertEquals(listOf(5), model.items.map { it.eventId })
    }

    @Test
    fun prefetchKeepsHistoryEndAcrossRefreshUntilFeedReset() = runBlocking {
        var language = "en"
        var schedule = SCHEDULE
        val summary = digest("en:2026-11-10T18:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { lang, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage(
                        lang,
                        listOf(item(2, "2026-11-10T19:00:00Z")),
                        "p2",
                        listOf(digest("$lang:2026-11-10T18:00:00.000Z"))
                    )
                } else {
                    AgentV2NewsFeedPage(lang, listOf(item(1, "2026-11-10T17:00:00Z")))
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { language },
            digestSchedule = { schedule }
        )
        model.refresh()
        repeat(2) { yield() }

        model.refresh()
        model.markDigestReached(summary.id)
        repeat(3) { yield() }
        model.refresh()
        repeat(3) { yield() }

        assertEquals(listOf(null, "p2", null, null), client.cursors)
        assertEquals(1, client.cursors.count { it == "p2" })
        assertEquals(listOf(1, 2), model.items.map { it.eventId })
        assertEquals("p2", model.nextCursor)

        model.loadMore()
        repeat(2) { yield() }
        assertEquals(2, client.cursors.count { it == "p2" })
        assertNull(model.nextCursor)

        schedule = schedule.copy(hour = 9)
        model.refresh()
        repeat(3) { yield() }
        assertEquals(3, client.cursors.count { it == "p2" })

        language = "ru"
        model.refresh()
        repeat(3) { yield() }
        assertEquals(4, client.cursors.count { it == "p2" })
    }

    @Test
    fun prefetchStopsAtExactlyFortyEightHoursWithoutDigests() = runBlocking {
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                when (cursor) {
                    null -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(4, "2026-11-10T20:00:00Z")),
                        "older1"
                    )

                    "older1" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-11-09T20:00:00Z")),
                        "older2"
                    )

                    "older2" -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(2, "2026-11-08T20:00:00Z")),
                        "older3"
                    )

                    else -> AgentV2NewsFeedPage("en", listOf(item(1, "2026-11-07T20:00:00Z")))
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { SCHEDULE }
        )

        model.refresh()
        repeat(4) { yield() }

        assertEquals(listOf(null, "older1", "older2"), client.cursors)
        assertEquals("older3", model.nextCursor)
        assertEquals("2026-11-08T20:00:00Z", model.items.first().deliveredAt)
    }

    @Test
    fun reachingAnOlderDigestKeepsTwoOlderDigestsReadyAndNeverMovesTheReferenceForward() =
        runBlocking {
            val recent = digest("en:2026-11-10T18:00:00.000Z")
            val previous = digest("en:2026-11-09T18:00:00.000Z")
            val pending = CompletableDeferred<AgentV2NewsFeedPage>()
            val client = FakeClient().apply {
                onGetFeed = { _, cursor ->
                    when (cursor) {
                        null -> AgentV2NewsFeedPage(
                            "en",
                            listOf(item(4, "2026-11-10T20:00:00Z")),
                            "older1",
                            listOf(recent, previous)
                        )

                        "older1" -> AgentV2NewsFeedPage(
                            "en",
                            listOf(item(3, "2026-11-08T19:00:00Z")),
                            "older2",
                            listOf(digest("en:2026-11-08T18:00:00.000Z"))
                        )

                        "older2" -> pending.await()

                        "older3" -> AgentV2NewsFeedPage(
                            "en",
                            listOf(item(1, "2026-11-07T19:00:00Z")),
                            "older4",
                            listOf(digest("en:2026-11-07T18:00:00.000Z"))
                        )

                        else -> AgentV2NewsFeedPage("en", listOf(item(1, "2026-11-06T19:00:00Z")))
                    }
                }
            }
            val model = AgentNewsFeedModel(
                createFeedScope(this),
                client,
                AgentNewsReadState({ null }, {}),
                language = { "en" },
                digestSchedule = { SCHEDULE }
            )
            model.refresh()
            repeat(2) { yield() }
            assertEquals(listOf<String?>(null), client.cursors)

            model.markDigestReached(recent.id)
            repeat(3) { yield() }
            assertEquals(listOf(null, "older1"), client.cursors)

            model.markDigestReached(previous.id)
            yield()
            assertEquals(listOf(null, "older1", "older2"), client.cursors)

            model.markDigestReached(recent.id)
            pending.complete(
                AgentV2NewsFeedPage("en", listOf(item(2, "2026-11-08T17:00:00Z")), "older3")
            )
            repeat(3) { yield() }
            assertEquals(listOf(null, "older1", "older2", "older3"), client.cursors)

            model.markDigestReached(recent.id)
            model.markDigestReached(previous.id)
            repeat(2) { yield() }
            assertEquals(listOf(null, "older1", "older2", "older3"), client.cursors)
            assertEquals("older4", model.nextCursor)
        }

    @Test
    fun failedPrefetchKeepsTheFeedAndCursorAndWaitsForLoadMoreToRetry() = runBlocking {
        val recent = digest("en:2026-11-10T18:00:00.000Z")
        val previous = digest("en:2026-11-09T18:00:00.000Z")
        var shouldFail = true
        val news = item(2, "2026-11-10T20:00:00Z")
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage("en", listOf(news), "older", listOf(recent))
                } else {
                    if (shouldFail) {
                        shouldFail = false
                        error("Offline")
                    }
                    AgentV2NewsFeedPage(
                        "en",
                        listOf(item(1, "2026-11-09T17:00:00Z")),
                        "oldest",
                        listOf(previous)
                    )
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { SCHEDULE }
        )

        model.refresh()
        repeat(4) { yield() }

        assertEquals(listOf(null, "older"), client.cursors)
        assertEquals(listOf(news), model.items)
        assertEquals("older", model.nextCursor)
        assertNull(model.error)
        assertNull(model.refreshError)
        assertFalse(model.isEmpty)
        assertFalse(model.isLoadingMore)

        model.loadMore()
        repeat(3) { yield() }

        assertEquals(listOf(null, "older", "older"), client.cursors)
        assertEquals("oldest", model.nextCursor)
        assertEquals(2, model.entries.count { it is AgentNewsFeedEntry.Digest })
    }

    @Test
    fun scheduleAndLanguageResetsDiscardInFlightPrefetchAndItsReachedDigest() = runBlocking {
        for (change in listOf("hour", "timeZone", "language")) {
            var schedule = SCHEDULE
            var language = "en"
            val pending = CompletableDeferred<AgentV2NewsFeedPage>()
            val refreshed = CompletableDeferred<AgentV2NewsFeedPage>()
            val recent = digest("en:2026-11-09T18:00:00.000Z")
            val news = item(2, "2026-11-10T20:00:00Z")
            val client = FakeClient().apply {
                onGetFeed = { _, cursor ->
                    if (cursor == null) {
                        AgentV2NewsFeedPage("en", listOf(news), "older", listOf(recent))
                    } else {
                        withContext(NonCancellable) { pending.await() }
                    }
                }
            }
            val model = AgentNewsFeedModel(
                createFeedScope(this),
                client,
                AgentNewsReadState({ null }, {}),
                language = { language },
                digestSchedule = { schedule }
            )
            model.refresh()
            model.markDigestReached(recent.id)
            yield()
            assertEquals(listOf(null, "older"), client.cursors)
            assertTrue(model.isLoadingMore)

            when (change) {
                "hour" -> schedule = schedule.copy(hour = 9)
                "timeZone" -> schedule = schedule.copy(timeZone = "Asia/Tbilisi")
                "language" -> language = "ru"
            }
            client.onGetFeed = { _, cursor ->
                if (cursor ==
                    null
                ) {
                    refreshed.await()
                } else {
                    AgentV2NewsFeedPage(language, emptyList())
                }
            }
            model.refresh()
            pending.complete(
                AgentV2NewsFeedPage(
                    "en",
                    listOf(item(99, "2026-11-01T00:00:00Z")),
                    "stale",
                    listOf(digest("en:2026-11-01T18:00:00.000Z"))
                )
            )
            yield()

            assertEquals(listOf(news), model.items)
            assertTrue(model.isLoading)
            assertFalse(model.isLoadingMore)
            refreshed.complete(
                AgentV2NewsFeedPage(
                    language,
                    listOf(news),
                    "fresh-older",
                    listOf(
                        digest("$language:2026-11-10T06:00:00.000Z"),
                        digest("$language:2026-11-09T06:00:00.000Z")
                    )
                )
            )
            repeat(3) { yield() }

            assertEquals(listOf(null, "older", null), client.cursors)
            assertEquals(listOf(news), model.items)
            assertEquals(2, model.entries.count { it is AgentNewsFeedEntry.Digest })
            assertEquals("fresh-older", model.nextCursor)
            assertFalse(model.isLoading)
            assertEquals(schedule, client.schedules.last())
        }
    }

    @Test
    fun prefetchScrollAndReachedDigestShareOneInFlightPageAndNeverRepeatASuccessfulCursor() =
        runBlocking {
            val first = CompletableDeferred<AgentV2NewsFeedPage>()
            val second = CompletableDeferred<AgentV2NewsFeedPage>()
            val recent = digest("en:2026-11-10T18:00:00.000Z")
            val client = FakeClient().apply {
                onGetFeed = { _, cursor ->
                    when (cursor) {
                        null -> AgentV2NewsFeedPage(
                            "en",
                            listOf(item(3, "2026-11-10T20:00:00Z")),
                            "older1",
                            listOf(recent)
                        )

                        "older1" -> first.await()

                        else -> {
                            check(cursors.count { it == "older2" } == 1)
                            second.await()
                        }
                    }
                }
            }
            val model = AgentNewsFeedModel(
                createFeedScope(this),
                client,
                AgentNewsReadState({ null }, {}),
                language = { "en" },
                digestSchedule = { SCHEDULE }
            )
            model.refresh()
            yield()
            model.loadMore()
            model.markDigestReached(recent.id)
            model.loadMore()
            yield()
            assertEquals(listOf(null, "older1"), client.cursors)

            first.complete(
                AgentV2NewsFeedPage("en", listOf(item(2, "2026-11-10T17:00:00Z")), "older2")
            )
            yield()
            model.loadMore()
            yield()
            assertEquals(listOf(null, "older1", "older2"), client.cursors)

            second.complete(
                AgentV2NewsFeedPage("en", listOf(item(1, "2026-11-10T16:00:00Z")), "older2")
            )
            repeat(3) { yield() }
            model.loadMore()
            yield()
            assertEquals(listOf(null, "older1", "older2"), client.cursors)
            assertNull(model.nextCursor)
            assertFalse(model.isLoadingMore)
        }

    @Test
    fun requestedDigestUsesTheSamePaginationBeyondThePrefetchLimit() = runBlocking {
        val requested = digest("en:2026-11-01T18:00:00.000Z")
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                when (cursor) {
                    null -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(3, "2026-11-10T20:00:00Z")),
                        "older1",
                        listOf(
                            digest("en:2026-11-10T18:00:00.000Z"),
                            digest("en:2026-11-09T18:00:00.000Z")
                        )
                    )

                    "older1" -> pending.await()

                    else -> AgentV2NewsFeedPage(
                        "en",
                        listOf(item(1, "2026-11-01T17:00:00Z")),
                        "older3",
                        listOf(requested)
                    )
                }
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            requestedDigestId = requested.id,
            digestSchedule = { SCHEDULE }
        )
        model.refresh()
        model.loadMore()
        yield()
        assertEquals(listOf(null, "older1"), client.cursors)
        pending.complete(
            AgentV2NewsFeedPage("en", listOf(item(2, "2026-11-08T17:00:00Z")), "older2")
        )
        repeat(3) { yield() }

        assertEquals(listOf(null, "older1", "older2"), client.cursors)
        assertTrue(model.hasRequestedDigest)
        assertTrue(model.isSeekingRequestedDigest)
        assertFalse(model.canLoadRequestedDigest)
        model.stopSeekingRequestedDigest()
        model.markDigestReached(requested.id)
        repeat(3) { yield() }
        assertEquals(listOf(null, "older1", "older2", "older3"), client.cursors)
    }

    private fun createFeedScope(parent: CoroutineScope): CoroutineScope {
        val dispatcher = parent.coroutineContext[ContinuationInterceptor] as CoroutineDispatcher
        // Requests start immediately; background prefetch yields to the test's event loop
        return CoroutineScope(
            parent.coroutineContext + object : CoroutineDispatcher() {
                override fun isDispatchNeeded(context: CoroutineContext) = false

                override fun dispatch(context: CoroutineContext, block: Runnable) {
                    dispatcher.dispatch(context, block)
                }
            }
        )
    }

    private fun digest(id: String) = AgentV2NewsFeedDigest(
        id,
        id.substringAfter(':'),
        listOf(AgentV2NewsDigestHeadline(42, "Headline")),
        7
    )

    private fun item(id: Int, deliveredAt: String) = AgentV2NewsFeedItem(
        eventId = id,
        deliveredAt = deliveredAt,
        headline = "News $id",
        body = "Body $id",
        sources = emptyList()
    )

    private class FakeClient : AgentNewsFeedClient {
        val cursors = mutableListOf<String?>()
        val schedules = mutableListOf<AgentNewsDigestSchedule>()
        var onGetFeed: suspend (String, String?) -> AgentV2NewsFeedPage = { _, _ ->
            AgentV2NewsFeedPage("en", emptyList())
        }

        override suspend fun getNewsFeed(
            lang: String,
            cursor: String?,
            schedule: AgentNewsDigestSchedule
        ): AgentV2NewsFeedPage {
            cursors.add(cursor)
            schedules.add(schedule)
            return onGetFeed(lang, cursor)
        }
    }

    private class DigestSettingsStub : AgentDigestNotificationSettings {
        override var mode = AgentNewsNotificationMode.Off
            private set
        override var digestHour = 21
            private set
        var outcome = AgentNewsNotificationOutcome.Ok
        var pending: CompletableDeferred<Unit>? = null
        val modes = mutableListOf<AgentNewsNotificationMode>()
        val hours = mutableListOf<Int>()

        override suspend fun setMode(
            mode: AgentNewsNotificationMode
        ): AgentNewsNotificationOutcome {
            modes += mode
            pending?.await()
            pending = null
            if (outcome == AgentNewsNotificationOutcome.Ok) this.mode = mode
            return outcome
        }

        override suspend fun setDigestHour(hour: Int): AgentNewsNotificationOutcome {
            hours += hour
            digestHour = hour
            pending?.await()
            pending = null
            return outcome
        }
    }

    companion object {
        private val SCHEDULE = AgentNewsDigestSchedule(21, "Europe/Moscow")

        /** The live client's requests encode their arguments with the SDK's adapters, which read the app's storage */
        @JvmStatic
        @BeforeClass
        fun initializeEmptyWalletStorage() {
            val storage = Proxy.newProxyInstance(
                IGlobalStorageProvider::class.java.classLoader,
                arrayOf(IGlobalStorageProvider::class.java)
            ) { _, method, _ ->
                when (method.name) {
                    "contains" -> false

                    "keysIn" -> emptyArray<String>()

                    "getInt", "getString", "getBool", "getDict", "getArray",
                    "incrementDoNotSynchronize", "decrementDoNotSynchronize",
                    "set", "setEmptyObject", "setEmptyObjects", "remove" -> null

                    else -> error("Unexpected wallet storage call: ${method.name}")
                }
            } as IGlobalStorageProvider
            WGlobalStorage.init(storage)
        }

        // The digest's English copy from `src/i18n/en.yaml`, as the app reads it
        private val ENGLISH_COPY = mapOf(
            "\$agent_digest_title" to "Top stories of the day",
            "\$agent_digest_meta.oneValue" to "%count% story · %time%",
            "\$agent_digest_meta.otherValue" to "%count% stories · %time%",
            "\$agent_digest_more.oneValue" to "and %count% more — it's above in the feed",
            "\$agent_digest_more.otherValue" to "and %count% more — they're above in the feed",
            "\$agent_digest_notifications_daily_hint" to
                "At %time%, the top news in one notification"
        )

        /** Runs [block] with the app's copy in English, then restores the copy and language it had */
        private inline fun <T> withEnglishCopy(block: () -> T): T {
            val language = LocaleController::class.java.getDeclaredField("_activeLanguage")
                .apply { isAccessible = true }
            val dictionary = LocaleController::class.java.getDeclaredField("dictionary")
                .apply { isAccessible = true }
            val previousLanguage = language.get(null)
            val previousDictionary = dictionary.get(null)
            language.set(null, WLanguage.ENGLISH)
            dictionary.set(null, ENGLISH_COPY)
            try {
                return block()
            } finally {
                language.set(null, previousLanguage)
                dictionary.set(null, previousDictionary)
            }
        }
    }
}
