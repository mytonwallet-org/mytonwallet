package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.content.ContextWrapper
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
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentNewsShareText
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationOutcome
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationState

class AgentNewsFeedModelTest {
    @Test
    fun shareNewsInTheFeedLocaleWhenTheAppLanguageDiffers() {
        val news = item(307, "2026-10-19T00:00:00Z")
        val language = LocaleController::class.java.getDeclaredField("_activeLanguage")
            .apply { isAccessible = true }
        val previousLanguage = language.get(null)
        try {
            language.set(null, WLanguage.ENGLISH)
            assertTrue(
                buildAgentNewsShareText(news.toNewsPost("ru"))!!
                    .endsWith("lang=ru&utm_source=pulse_share")
            )
            language.set(null, WLanguage.RUSSIAN)
            assertTrue(
                buildAgentNewsShareText(news.toNewsPost("en"))!!
                    .endsWith("lang=en&utm_source=pulse_share")
            )
        } finally {
            language.set(null, previousLanguage)
        }
    }

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
    fun digestsViewMarksTheFirstNewDigestAndReadsTheDigests() = runBlocking {
        val read = digest("en:2026-10-18T06:00:00Z")
        val first = digest("en:2026-10-19T06:00:00Z")
        val latest = digest("en:2026-10-20T06:00:00Z")
        var digestsMark: String? = read.deliveredAt
        val readState = AgentNewsReadState({ null }, {}, { digestsMark }, { digestsMark = it })
        val client = FakeClient().apply {
            onGetFeed = { _, _ ->
                AgentV2NewsFeedPage("en", emptyList(), digests = listOf(latest, first, read))
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            readState,
            language = { "en" },
            digestSchedule = { SCHEDULE },
            initialView = AgentNewsFeedView.Digests
        )

        model.refresh()

        assertEquals(AgentNewsFeedView.Digests, client.views.last())
        assertEquals(first.id, model.unreadDigestId)
        assertNull(model.unreadEventId)
        assertEquals(latest.deliveredAt, digestsMark)
        // The line stays while the feed is open
        model.refresh()
        assertEquals(first.id, model.unreadDigestId)
        model.setView(AgentNewsFeedView.All, shouldDeferRefresh = true)
        assertNull(model.unreadDigestId)
    }

    @Test
    fun digestsTheAllViewShowedAreNotNew() = runBlocking {
        val read = digest("en:2026-10-18T06:00:00Z")
        val shown = digest("en:2026-10-19T06:00:00Z")
        var digestsMark: String? = read.deliveredAt
        val readState = AgentNewsReadState({ null }, {}, { digestsMark }, { digestsMark = it })
        val client = FakeClient().apply {
            onGetFeed = { _, _ ->
                if (views.last() == AgentNewsFeedView.All) {
                    AgentV2NewsFeedPage(
                        "en",
                        listOf(item(1, "2026-10-19T10:00:00Z")),
                        digests = listOf(shown)
                    )
                } else {
                    AgentV2NewsFeedPage("en", emptyList(), digests = listOf(shown, read))
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
        assertEquals(shown.deliveredAt, digestsMark)
        model.setView(AgentNewsFeedView.Digests)

        assertNull(model.unreadDigestId)
    }

    @Test
    fun newsRowFollowsTheDigestsView() = runBlocking {
        var mark: String? = null
        var digestsMark: String? = null
        val readState = AgentNewsReadState(
            read = { mark },
            write = { mark = it },
            readDigests = { digestsMark },
            writeDigests = { digestsMark = it }
        )
        var view = AgentNewsFeedView.All
        val news = item(1, "2026-10-19T10:00:00Z")
        val read = digest("en:2026-10-19T06:00:00Z")
        val latest = digest("en:2026-10-21T06:00:00Z")
        val client = FakeClient().apply {
            onGetFeed = { _, _ ->
                if (views.last() == AgentNewsFeedView.All) {
                    AgentV2NewsFeedPage("en", listOf(news), digests = listOf(read))
                } else {
                    AgentV2NewsFeedPage(
                        "en",
                        emptyList(),
                        digests = listOf(latest, digest("en:2026-10-20T06:00:00Z"), read)
                    )
                }
            }
        }
        val model = AgentNewsPreviewModel(
            CoroutineScope(coroutineContext + Dispatchers.Unconfined),
            client,
            readState,
            language = { "en" },
            digestSchedule = { SCHEDULE },
            view = { view }
        )

        model.refresh()
        assertEquals(read.deliveredAt, digestsMark)

        view = AgentNewsFeedView.Digests
        model.refresh()

        assertEquals(AgentNewsFeedView.Digests, client.views.last())
        assertEquals(latest, model.latestDigest)
        assertEquals(2, model.unreadCount)
        assertEquals(news, model.latestItem)
        assertEquals(listOf(read), model.currentDigests)
        view = AgentNewsFeedView.All
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
        val daily = digest("en:2026-10-20T18:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { _, cursor ->
                if (cursor == null) {
                    AgentV2NewsFeedPage("en", listOf(recent), "older", listOf(daily))
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
        val digestThread = AgentV2ThreadSummary("digest-thread", revision = 1, messageCount = 1)

        model.refresh()
        model.markDiscussion(older.eventId, olderThread)
        model.markDiscussion(recent.eventId, recentThread)
        model.markDiscussion(daily.id, digestThread)
        model.loadMore()

        fun findCurrentDigest() = model.entries.filterIsInstance<AgentNewsFeedEntry.Digest>()
            .single().digest
        assertEquals(
            AgentNewsChatTarget.Discussion(digestThread),
            resolveAgentDigestDiscussionTarget(findCurrentDigest()) { id ->
                digestThread.takeIf { it.id == id }
            }
        )

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
        assertEquals(digestThread.id, findCurrentDigest().discussion?.threadId)

        model.setView(AgentNewsFeedView.Digests)
        assertEquals(digestThread.id, findCurrentDigest().discussion?.threadId)
        model.removeDiscussion(digestThread.id)
        model.refresh()
        assertNull(findCurrentDigest().discussion)
        model.setView(AgentNewsFeedView.All)
        assertNull(findCurrentDigest().discussion)
        assertEquals(recentThread.id, model.items.last().discussion?.threadId)
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
            schedule = AgentNewsDigestSchedule(19, 45, "Asia/Tbilisi")
            model.loadMore()
            kotlinx.coroutines.yield()
            assertEquals(3, requests.size)
            model.loadMore()
            kotlinx.coroutines.yield()

            assertEquals(4, requests.size)
            assertEquals(
                """[{"lang":"ru-RU","digestHour":21,"digestMinute":0,"timeZone":"Europe/Moscow"}]""",
                requests.first()
            )
            assertEquals(requests.first(), requests[1])
            assertEquals(
                """[{"lang":"ru-RU","digestHour":19,"digestMinute":45,"timeZone":"Asia/Tbilisi"}]""",
                requests[2]
            )
            assertEquals(
                """[{"lang":"ru-RU","cursor":"older","digestHour":19,"digestMinute":45,"timeZone":"Asia/Tbilisi"}]""",
                requests.last()
            )
            client.getNewsFeed("ru-RU", null, schedule, AgentNewsFeedView.Digests)
            assertEquals(
                """[{"lang":"ru-RU","digestHour":19,"digestMinute":45,"timeZone":"Asia/Tbilisi","view":"digests"}]""",
                requests.last()
            )
        }

    @Test
    fun newDigestScheduleReplacesTheOldDigestsAsItsPageComesAndKeepsTheNews() = runBlocking {
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

        // Another minute of the same hour is another schedule
        schedule = SCHEDULE.copy(minute = 30)
        client.onGetFeed = { _, _ -> pending.await() }
        model.refresh()

        // The old digests stay while the new schedule's page loads, so the cards and the pinned bar don't blink
        assertEquals(
            listOf(AgentNewsFeedEntry.Digest(evening), AgentNewsFeedEntry.News(news)),
            model.entries
        )
        assertNull(model.nextCursor)
        pending.complete(AgentV2NewsFeedPage("en", listOf(news), "older", listOf(morning)))
        assertEquals(
            listOf(AgentNewsFeedEntry.Digest(morning), AgentNewsFeedEntry.News(news)),
            model.entries
        )
        assertEquals(listOf(SCHEDULE, schedule), client.schedules)

        // A failed page of another schedule takes its digests away
        schedule = AgentNewsDigestSchedule(10, 15, "Europe/Moscow")
        client.onGetFeed = { _, _ -> error("Offline") }
        model.refresh()
        assertEquals(listOf(AgentNewsFeedEntry.News(news)), model.entries)
    }

    @Test
    fun currentDigestScheduleTakesTheMinuteTheSettingsKeep() = runBlocking {
        val settings = AgentNewsNotificationSettings.shared
        val previous = settings.state.value
        try {
            settings.setDigestTime(9, 45)
            val schedule = AgentNewsDigestSchedule.current()
            assertEquals(9, schedule.hour)
            assertEquals(45, schedule.minute)
        } finally {
            settings.setDigestTime(previous.digestHour, previous.digestMinute)
        }
    }

    @Test
    fun openFeedReloadsForANewDigestMinuteAlone() {
        val state = AgentNewsNotificationState(digestHour = 21, digestMinute = 0)
        val key = makeAgentNewsFeedSettingsKey(AgentNewsFeedView.All, state)
        assertNotEquals(
            key,
            makeAgentNewsFeedSettingsKey(AgentNewsFeedView.All, state.copy(digestMinute = 45))
        )
        assertEquals(
            key,
            makeAgentNewsFeedSettingsKey(
                AgentNewsFeedView.All,
                state.copy(mode = AgentNewsNotificationMode.Digest)
            )
        )
    }

    @Test
    fun newsRowPageOpensTheFeedWithItsDigestsWhileTheirScheduleHolds() = runBlocking {
        var schedule = SCHEDULE
        val evening = digest("en:2026-11-08T18:00:00.000Z")
        val news = item(1, "2026-11-08T19:00:00Z")
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient().apply {
            onGetFeed =
                { _, _ -> AgentV2NewsFeedPage("en", listOf(news), "older", listOf(evening)) }
        }
        val scope = CoroutineScope(coroutineContext + Dispatchers.Unconfined)
        val readState = AgentNewsReadState({ null }, {})
        val preview = AgentNewsPreviewModel(
            scope,
            client,
            readState,
            language = { "en" },
            digestSchedule = { schedule }
        )
        preview.refresh()
        val model = AgentNewsFeedModel(
            scope,
            client,
            readState,
            language = { "en" },
            digestSchedule = { schedule }
        )
        client.onGetFeed = { _, _ -> pending.await() }

        model.seed(preview.items, preview.currentDigests)
        model.refresh()

        val seeded = listOf(AgentNewsFeedEntry.Digest(evening), AgentNewsFeedEntry.News(news))
        assertEquals(seeded, model.entries)
        pending.complete(AgentV2NewsFeedPage("en", listOf(news), "older", listOf(evening)))
        assertEquals(seeded, model.entries)

        schedule = SCHEDULE.copy(minute = 15)
        assertEquals(listOf(news), preview.items)
        assertTrue(preview.currentDigests.isEmpty())
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

        assertEquals("Top news of the day", card.title)
        assertEquals("26 news items", card.meta)
        assertEquals("21:00", card.time)
        assertEquals(headlines, card.headlines)
        assertEquals("and 24 more — they're above in the feed", card.remainder)
        // The digests view lists no news above the digest to point at
        val inDigestsView = AgentNewsDigestCardContent(digest, "21:00", isInDigestsView = true)
        assertEquals("and 24 more", inDigestsView.remainder)
        val single =
            AgentNewsDigestCardContent(digest.copy(top = headlines.take(1), total = 1), "9:00")
        assertEquals("1 news item", single.meta)
        assertEquals("9:00", single.time)
        assertNull(single.remainder)
    }

    @Test
    fun digestHeadlinesLeadWithPicturesThatOpenTheViewerApartFromTheirRows() {
        val rows = AgentNewsDigestRows()
        val views = List(5) { FakeDigestRow() }
        views.forEachIndexed { index, row -> rows.bindRow(row, index) }
        rows.update(
            listOf(AgentV2NewsDigestHeadline(1, "One"), AgentV2NewsDigestHeadline(2, "Two", " "))
        )
        assertFalse(rows.hasPictures)
        assertEquals(List(2) { AgentNewsDigestLead.BULLET }, rows.leads)

        val headlines = listOf(
            AgentV2NewsDigestHeadline(1, "One", "https://example.com/1.jpg"),
            AgentV2NewsDigestHeadline(2, "Two"),
            AgentV2NewsDigestHeadline(3, "Three", "https://example.com/3.jpg"),
            AgentV2NewsDigestHeadline(4, "Four", "https://example.com/4.jpg"),
            AgentV2NewsDigestHeadline(5, "Five", "https://example.com/5.jpg")
        )
        rows.update(headlines)
        rows.setPictureLoaded(0, isLoaded = true)
        rows.setPictureLoaded(2, isLoaded = true)
        rows.setPictureLoaded(3, isLoaded = false)
        views.forEachIndexed { index, row -> rows.updateRow(row, index) }
        assertEquals(
            listOf(
                AgentNewsDigestLead.PICTURE,
                AgentNewsDigestLead.NEWS_MARK,
                AgentNewsDigestLead.PICTURE,
                AgentNewsDigestLead.PICTURE,
                AgentNewsDigestLead.PICTURE
            ),
            views.map { it.lead }
        )
        // The News mark, a failed picture and one still loading leave the tap to their rows
        assertEquals(listOf(true, false, true, false, false), views.map { it.isPictureClickable })

        val openedRows = mutableListOf<Int>()
        val openedPictures = mutableListOf<AgentNewsDigestPictures>()
        rows.onHeadlineClick = { openedRows.add(it.eventId) }
        rows.onPictureClick = { openedPictures.add(it) }
        views[2].clickPicture()
        assertTrue(openedRows.isEmpty())
        val pictures = openedPictures.single()
        assertEquals(listOf(1, 3), pictures.headlines.map { it.eventId })
        assertEquals(1, pictures.index)
        views[1].clickRow()
        views[3].clickRow()
        assertEquals(listOf(2, 4), openedRows)
        assertEquals(1, openedPictures.size)

        val items = pictures.headlines.map {
            agentNewsDigestMediaViewerItem(ContextWrapper(null), it, null) { text ->
                "styled:$text"
            }
        }
        assertEquals(
            listOf("https://example.com/1.jpg", "https://example.com/3.jpg"),
            items.map {
                it.url
            }
        )
        assertEquals(listOf("One", "Three"), items.map { it.accessibilityLabel })
        // The caption is the headline alone, without a post's body, sources or menu
        assertEquals(
            listOf("styled:One", "styled:Three"),
            items.map {
                it.caption!!(16f).toString()
            }
        )
        assertTrue(items.all { it.menuItems == null })

        // A picture that stays keeps its state; a changed one loads again
        rows.update(headlines.take(2) + headlines[2].copy(imageUrl = "https://example.com/3b.jpg"))
        (0..2).forEach { rows.updateRow(views[it], it) }
        assertEquals(
            listOf(
                AgentNewsDigestPictureState.SHOWN,
                AgentNewsDigestPictureState.NONE,
                AgentNewsDigestPictureState.LOADING
            ),
            views.take(3).map { it.state }
        )
        assertEquals(listOf(true, false, false), views.take(3).map { it.isPictureClickable })
    }

    @Test
    fun digestPostOpensItsPicturesFromTalkBackActionsOnlyOnceTheyShow() {
        val rows = AgentNewsDigestRows()
        rows.update(
            listOf(
                AgentV2NewsDigestHeadline(1, "One", "https://example.com/1.jpg"),
                AgentV2NewsDigestHeadline(2, "Two"),
                AgentV2NewsDigestHeadline(3, "Three", "https://example.com/3.jpg"),
                AgentV2NewsDigestHeadline(4, "Four", "https://example.com/4.jpg")
            )
        )
        assertTrue(rows.buildPictureActions("Picture").isEmpty())

        rows.setPictureLoaded(0, isLoaded = true)
        rows.setPictureLoaded(2, isLoaded = true)
        rows.setPictureLoaded(3, isLoaded = false)
        val actions = rows.buildPictureActions("Picture")
        assertEquals(listOf("Picture, One", "Picture, Three"), actions.map { it.label })

        val openedRows = mutableListOf<Int>()
        val openedPictures = mutableListOf<AgentNewsDigestPictures>()
        rows.onHeadlineClick = { openedRows.add(it.eventId) }
        rows.onPictureClick = { openedPictures.add(it) }
        actions[1].open()
        actions[0].open()
        assertEquals(listOf(1, 0), openedPictures.map { it.index })
        assertTrue(
            openedPictures.all { pictures ->
                pictures.headlines.map { it.eventId } ==
                    listOf(1, 3)
            }
        )
        assertTrue(openedRows.isEmpty())
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
        val naming = AgentV2NewsFeedItem.DiscussionNaming(
            "Digest discussion",
            "📰",
            listOf("Explain the impact")
        )
        val fresh = digest("en:2026-11-07T18:00:00.000Z").copy(discussionNaming = naming)
        assertEquals(
            AgentNewsChatTarget.Discussion(thread),
            resolveAgentDigestDiscussionTarget(discussed) { id -> thread.takeIf { it.id == id } }
        )
        // A discussion the user hasn't written in opens as a visit, as one without a thread does, with the feed's copy
        // of the digest for its post until its thread comes
        fun preview(digest: AgentV2NewsFeedDigest) =
            AgentV2ThreadDigestCard(digest.id, digest.deliveredAt, digest.total, digest.top)
        assertEquals(
            AgentNewsChatTarget.Digest(discussed.id, preview(discussed)),
            resolveAgentDigestDiscussionTarget(discussed) { null }
        )
        assertEquals(
            AgentNewsChatTarget.Digest(
                fresh.id,
                preview(fresh),
                naming,
                shouldDeferCreation = true
            ),
            resolveAgentDigestDiscussionTarget(fresh) { error("Nothing to find") }
        )
        assertEquals(
            AgentNewsChatTarget.Digest(fresh.id, preview(fresh), shouldDeferCreation = true),
            resolveAgentDigestDiscussionTarget(fresh.copy(discussionNaming = null)) {
                error("Nothing to find")
            }
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
    fun digestSheetAppliesChoicesAndTimeAndKeepsThePreviousChoiceWhenOneFails() = runBlocking {
        withEnglishCopy {
            val settings = DigestSettingsStub()
            var errors = 0
            val pendingState = AgentDigestSettingsModel.PendingState()
            val sheet = AgentDigestSettingsModel(settings, pendingState)
                .apply { onError = { errors++ } }
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertEquals(
                "One notification at 21:00 with the day's top news.",
                sheet.hint(AgentNewsNotificationMode.Digest)
            )

            sheet.selectMode(AgentNewsNotificationMode.Digest)
            sheet.selectMode(AgentNewsNotificationMode.News)
            sheet.selectMode(AgentNewsNotificationMode.Off)
            sheet.selectTime(AgentDigestTime(7, 0))
            assertEquals(
                listOf(
                    AgentNewsNotificationMode.Digest,
                    AgentNewsNotificationMode.News,
                    AgentNewsNotificationMode.Off
                ),
                settings.modes
            )
            assertEquals(listOf(AgentDigestTime(7, 0)), settings.times)
            assertEquals(
                "One notification at 07:00 with the day's top news.",
                sheet.hint(AgentNewsNotificationMode.Digest)
            )
            sheet.selectTime(AgentDigestTime(7, 45))
            assertEquals(AgentDigestTime(7, 45), settings.times.last())
            assertEquals(
                "One notification at 07:45 with the day's top news.",
                sheet.hint(AgentNewsNotificationMode.Digest)
            )

            settings.outcome = AgentNewsNotificationOutcome.PermissionDenied
            sheet.selectMode(AgentNewsNotificationMode.News)
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertTrue(sheet.isPermissionDenied)
            assertEquals(0, errors)
            assertFalse(AgentDigestSettingsModel(settings, pendingState).isPermissionDenied)

            settings.outcome = AgentNewsNotificationOutcome.Failed
            sheet.selectMode(AgentNewsNotificationMode.Digest)
            assertEquals(AgentNewsNotificationMode.Off, sheet.mode)
            assertFalse(sheet.isPermissionDenied)
            assertEquals(1, errors)

            // A choice shows at once, and so do the next ones picked while it is applied, the last of which goes next
            settings.outcome = AgentNewsNotificationOutcome.Ok
            val choice = CompletableDeferred<Unit>().also { settings.pending = it }
            val applying = launch(Dispatchers.Unconfined) {
                sheet.selectMode(AgentNewsNotificationMode.Digest)
            }
            assertEquals(AgentNewsNotificationMode.Digest, sheet.pendingMode)
            assertEquals(AgentNewsNotificationMode.Digest, sheet.mode)
            sheet.selectMode(AgentNewsNotificationMode.Off)
            sheet.selectMode(AgentNewsNotificationMode.News)
            assertEquals(AgentNewsNotificationMode.News, sheet.mode)
            choice.complete(Unit)
            applying.join()
            assertEquals(
                listOf(AgentNewsNotificationMode.Digest, AgentNewsNotificationMode.News),
                settings.modes.takeLast(2)
            )
            assertEquals(7, settings.modes.size)
            assertEquals(AgentNewsNotificationMode.News, sheet.mode)
            assertNull(sheet.pendingMode)

            // Times picked while one is applied show at once and the last of them goes next; one that fails to apply
            // stays, as the settings keep it
            settings.outcome = AgentNewsNotificationOutcome.Failed
            val time = CompletableDeferred<Unit>().also { settings.pending = it }
            val applyingTime = launch(Dispatchers.Unconfined) {
                sheet.selectTime(AgentDigestTime(8, 45))
            }
            assertTrue(sheet.isApplyingTime)
            sheet.selectTime(AgentDigestTime(9, 45))
            sheet.selectTime(AgentDigestTime(10, 15))
            assertEquals(AgentDigestTime(10, 15), sheet.digestTime)
            time.complete(Unit)
            applyingTime.join()
            assertEquals(
                listOf(
                    AgentDigestTime(7, 0),
                    AgentDigestTime(7, 45),
                    AgentDigestTime(8, 45),
                    AgentDigestTime(10, 15)
                ),
                settings.times
            )
            assertEquals(AgentDigestTime(10, 15), sheet.digestTime)
            assertFalse(sheet.isApplyingTime)
            assertEquals(3, errors)
        }
    }

    @Test
    fun showPendingModeAndApplyLastChoiceAcrossDigestSheets() = runBlocking {
        val settings = DigestSettingsStub()
        val pendingState = AgentDigestSettingsModel.PendingState()
        val model = AgentDigestSettingsModel(settings, pendingState)
        val pending = CompletableDeferred<Unit>().also { settings.pending = it }
        val applying = launch(Dispatchers.Unconfined) {
            model.selectMode(AgentNewsNotificationMode.Digest)
        }

        val reopenedWhileApplying = AgentDigestSettingsModel(settings, pendingState)
        var visibleMode = reopenedWhileApplying.mode
        assertEquals(AgentNewsNotificationMode.Digest, visibleMode)
        model.onChange = { visibleMode = model.mode }
        model.selectMode(AgentNewsNotificationMode.News)
        assertEquals(AgentNewsNotificationMode.News, visibleMode)
        model.onChange = null

        val reopened = AgentDigestSettingsModel(settings, pendingState)
        visibleMode = reopened.mode
        reopened.onChange = { visibleMode = reopened.mode }
        assertEquals(AgentNewsNotificationMode.Off, settings.mode)
        assertEquals(AgentNewsNotificationMode.News, visibleMode)
        reopened.selectMode(AgentNewsNotificationMode.Off)
        assertEquals(AgentNewsNotificationMode.Off, visibleMode)
        pending.complete(Unit)
        applying.join()

        assertEquals(
            listOf(AgentNewsNotificationMode.Digest, AgentNewsNotificationMode.Off),
            settings.modes
        )
        assertEquals(AgentNewsNotificationMode.Off, settings.mode)
        assertEquals(AgentNewsNotificationMode.Off, visibleMode)
        assertNull(model.pendingMode)
    }

    @Test
    fun showPendingTimeAndApplyLastChoiceAcrossDigestSheets() = runBlocking {
        val settings = DigestSettingsStub()
        val pendingState = AgentDigestSettingsModel.PendingState()
        val model = AgentDigestSettingsModel(settings, pendingState)
        val pending = CompletableDeferred<Unit>().also { settings.pending = it }
        val applying = launch(Dispatchers.Unconfined) { model.selectTime(AgentDigestTime(8, 0)) }

        val reopenedWhileApplying = AgentDigestSettingsModel(settings, pendingState)
        var visibleTime = reopenedWhileApplying.digestTime
        assertEquals(AgentDigestTime(8, 0), visibleTime)
        model.onChange = { visibleTime = model.digestTime }
        model.selectTime(AgentDigestTime(8, 30))
        assertEquals(AgentDigestTime(8, 30), visibleTime)
        model.onChange = null

        val reopened = AgentDigestSettingsModel(settings, pendingState)
        visibleTime = reopened.digestTime
        reopened.onChange = { visibleTime = reopened.digestTime }
        assertEquals(AgentDigestTime(8, 0), settings.digestTime)
        assertEquals(AgentDigestTime(8, 30), visibleTime)
        reopened.selectTime(AgentDigestTime(10, 30))
        assertEquals(AgentDigestTime(10, 30), visibleTime)
        pending.complete(Unit)
        applying.join()

        assertEquals(listOf(AgentDigestTime(8, 0), AgentDigestTime(10, 30)), settings.times)
        assertEquals(AgentDigestTime(10, 30), settings.digestTime)
        assertEquals(AgentDigestTime(10, 30), visibleTime)
        assertFalse(model.isApplyingTime)
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

    @Test
    fun digestsLoadFirstPageAndOlderCursorWithoutNewsPrefetchAndStopAtHistoryEnd() = runBlocking {
        val recent = digest("en:2026-11-10T18:00:00.000Z")
        val older = digest("en:2026-11-09T18:00:00.000Z")
        val firstPage = CompletableDeferred<AgentV2NewsFeedPage>()
        val olderPage = CompletableDeferred<AgentV2NewsFeedPage>()
        val client = FakeClient().apply {
            onGetFeed =
                { _, cursor -> if (cursor == null) firstPage.await() else olderPage.await() }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({
                null
            }, { error("Unexpected read mark") }),
            language = {
                "en"
            },
            digestSchedule = { SCHEDULE },
            initialView = AgentNewsFeedView.Digests
        )
        model.refresh()
        assertTrue(model.isLoading)
        firstPage.complete(AgentV2NewsFeedPage("en", emptyList(), "older", listOf(recent)))
        repeat(3) { yield() }
        assertFalse(model.isLoading)
        assertTrue(model.hasLoaded)
        assertEquals(listOf(AgentNewsFeedEntry.Digest(recent)), model.entries)
        assertNull(model.unreadEventId)
        assertEquals(listOf<String?>(null), client.cursors)

        model.loadMore()
        assertTrue(model.isLoadingMore)
        olderPage.complete(AgentV2NewsFeedPage("en", emptyList(), digests = listOf(older)))
        repeat(3) { yield() }
        model.loadMore()
        assertEquals(
            listOf(older, recent),
            model.entries.map {
                (it as AgentNewsFeedEntry.Digest).digest
            }
        )
        assertEquals(listOf(null, "older"), client.cursors)
        assertEquals(List(2) { AgentNewsFeedView.Digests }, client.views)
        assertEquals(List(2) { SCHEDULE }, client.schedules)
        assertNull(model.nextCursor)
        assertFalse(model.isLoadingMore)
    }

    @Test
    fun digestsKeepCardsOnFailedRefreshAndReplaceThemForANewHourOrTimeZone() = runBlocking {
        var schedule = SCHEDULE
        val evening = digest("en:2026-11-10T18:00:00.000Z")
        val morning = digest("en:2026-11-10T06:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", emptyList(), "older", listOf(evening)) }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = {
                "en"
            },
            digestSchedule = { schedule },
            initialView = AgentNewsFeedView.Digests
        )
        model.refresh()
        val failure = IllegalStateException("Offline")
        client.onGetFeed = { _, _ -> throw failure }
        model.refresh()
        assertEquals(listOf(AgentNewsFeedEntry.Digest(evening)), model.entries)
        assertEquals(failure, model.refreshError)
        assertNull(model.error)

        schedule = schedule.copy(hour = 9)
        model.refresh()
        assertEquals(listOf(AgentNewsFeedEntry.Digest(evening)), model.entries)
        assertEquals(failure, model.refreshError)
        val pending = CompletableDeferred<AgentV2NewsFeedPage>()
        client.onGetFeed = { _, _ -> pending.await() }
        model.refresh()
        assertTrue(model.isLoading)
        assertEquals(listOf(AgentNewsFeedEntry.Digest(evening)), model.entries)
        pending.complete(AgentV2NewsFeedPage("en", emptyList(), "morning-older", listOf(morning)))
        assertEquals(listOf(AgentNewsFeedEntry.Digest(morning)), model.entries)
        assertNull(model.refreshError)
        assertEquals(schedule, client.schedules.last())
        assertNull(client.cursors.last())

        schedule = schedule.copy(timeZone = "Asia/Tbilisi")
        model.loadMore()
        assertEquals(schedule, client.schedules.last())
        assertNull(client.cursors.last())
        assertEquals(5, client.cursors.size)
    }

    @Test
    fun digestsRefreshWithoutOverlapReplacesHistoryAndCursorOnTheSameSchedule() = runBlocking {
        val older = digest("en:2026-11-09T18:00:00.000Z")
        val recent = digest("en:2026-11-10T18:00:00.000Z")
        val newest = digest("en:2026-11-11T18:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { _, _ ->
                AgentV2NewsFeedPage("en", emptyList(), "older", listOf(older, recent))
            }
        }
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            AgentNewsReadState({ null }, {}),
            language = { "en" },
            digestSchedule = { SCHEDULE },
            initialView = AgentNewsFeedView.Digests
        )
        model.refresh()
        assertEquals(
            listOf(AgentNewsFeedEntry.Digest(older), AgentNewsFeedEntry.Digest(recent)),
            model.entries
        )
        assertEquals("older", model.nextCursor)
        client.onGetFeed = { _, _ ->
            AgentV2NewsFeedPage("en", emptyList(), "new-older", listOf(newest))
        }
        model.refresh()
        assertEquals(listOf(AgentNewsFeedEntry.Digest(newest)), model.entries)
        assertEquals("new-older", model.nextCursor)
        assertEquals(listOf<String?>(null, null), client.cursors)
        assertEquals(List(2) { SCHEDULE }, client.schedules)
    }

    @Test
    fun switchingViewsRestoresListsWhileRefreshingAndDigestsKeepNewsUnread() = runBlocking {
        var mark: String? = "2026-11-09T00:00:00Z"
        val readState = AgentNewsReadState({ mark }, { mark = it })
        val news = item(42, "2026-11-10T20:00:00Z")
        val unread = item(43, "2026-11-11T20:00:00Z")
        val recent = digest("en:2026-11-10T18:00:00.000Z")
        val client = FakeClient().apply {
            onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", listOf(news)) }
        }
        val preview = AgentNewsPreviewModel(
            createFeedScope(this),
            client,
            readState,
            language = {
                "en"
            },
            digestSchedule = { SCHEDULE }
        )
        preview.refresh()
        val model = AgentNewsFeedModel(
            createFeedScope(this),
            client,
            readState,
            language = { "en" },
            digestSchedule = { SCHEDULE },
            initialView = AgentNewsFeedView.Digests
        )
        model.seed(preview.items)
        client.onGetFeed = { _, cursor ->
            if (cursor == null) {
                AgentV2NewsFeedPage("en", listOf(news), "older", listOf(recent))
            } else {
                AgentV2NewsFeedPage("en", listOf(unread))
            }
        }
        model.refresh()
        assertEquals("2026-11-09T00:00:00Z", mark)
        model.refresh()
        assertEquals(1, preview.unreadCount)
        assertEquals("2026-11-09T00:00:00Z", mark)
        assertNull(model.unreadEventId)
        model.loadMore()
        assertEquals("2026-11-09T00:00:00Z", mark)
        assertEquals(1, preview.unreadCount)
        val digestEntries = listOf(
            AgentNewsFeedEntry.Digest(recent),
            AgentNewsFeedEntry.News(news),
            AgentNewsFeedEntry.News(unread)
        )
        assertEquals(digestEntries, model.entries)

        val pendingAll = CompletableDeferred<AgentV2NewsFeedPage>()
        client.onGetFeed = { _, _ -> pendingAll.await() }
        model.setView(AgentNewsFeedView.All)
        assertEquals(listOf(AgentNewsFeedEntry.News(news)), model.entries)
        assertTrue(model.isLoading)
        assertEquals(news.deliveredAt, mark)
        assertEquals(42, model.unreadEventId)
        pendingAll.complete(AgentV2NewsFeedPage("en", listOf(news)))
        assertEquals(news.deliveredAt, mark)
        assertEquals(42, model.unreadEventId)
        assertEquals(0, preview.unreadCount)

        val pendingDigests = CompletableDeferred<AgentV2NewsFeedPage>()
        client.onGetFeed = { _, _ -> pendingDigests.await() }
        model.setView(AgentNewsFeedView.Digests)
        assertEquals(digestEntries, model.entries)
        assertTrue(model.isLoading)
        pendingDigests.complete(
            AgentV2NewsFeedPage("en", listOf(news, unread), digests = listOf(recent))
        )
        client.onGetFeed = { _, _ -> AgentV2NewsFeedPage("en", listOf(news, unread)) }
        preview.refresh()
        repeat(3) { yield() }
        assertEquals(news.deliveredAt, mark)
        assertEquals(1, preview.unreadCount)
        assertEquals(digestEntries, model.entries)
        assertNull(model.unreadEventId)
        assertEquals(
            listOf(
                AgentNewsFeedView.All,
                AgentNewsFeedView.Digests,
                AgentNewsFeedView.Digests,
                AgentNewsFeedView.Digests,
                AgentNewsFeedView.All,
                AgentNewsFeedView.Digests,
                AgentNewsFeedView.All
            ),
            client.views
        )
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

    /** A headline row that keeps the taps the rows wire to it and the lead they show */
    private class FakeDigestRow : AgentNewsDigestRowTargets {
        private var onRowClick: (() -> Unit)? = null
        private var onPictureClick: (() -> Unit)? = null
        var lead: AgentNewsDigestLead? = null
        var state: AgentNewsDigestPictureState? = null
        var isPictureClickable = false

        override fun setOnRowClick(onClick: () -> Unit) {
            onRowClick = onClick
        }

        override fun setOnPictureClick(onClick: () -> Unit) {
            onPictureClick = onClick
        }

        override fun showLead(
            lead: AgentNewsDigestLead,
            state: AgentNewsDigestPictureState,
            isPictureClickable: Boolean
        ) {
            this.lead = lead
            this.state = state
            this.isPictureClickable = isPictureClickable
        }

        fun clickRow() = onRowClick!!()

        // As on a device, a picture that doesn't take taps leaves them to the row
        fun clickPicture() = if (isPictureClickable) onPictureClick!!() else clickRow()
    }

    private class FakeClient : AgentNewsFeedClient {
        val cursors = mutableListOf<String?>()
        val schedules = mutableListOf<AgentNewsDigestSchedule>()
        val views = mutableListOf<AgentNewsFeedView>()
        var onGetFeed: suspend (String, String?) -> AgentV2NewsFeedPage = { _, _ ->
            AgentV2NewsFeedPage("en", emptyList())
        }

        override suspend fun getNewsFeed(
            lang: String,
            cursor: String?,
            schedule: AgentNewsDigestSchedule,
            view: AgentNewsFeedView
        ): AgentV2NewsFeedPage {
            cursors.add(cursor)
            schedules.add(schedule)
            views.add(view)
            return onGetFeed(lang, cursor)
        }
    }

    private class DigestSettingsStub : AgentDigestNotificationSettings {
        override var mode = AgentNewsNotificationMode.Off
            private set
        override var digestTime = AgentDigestTime(21, 0)
            private set
        var outcome = AgentNewsNotificationOutcome.Ok
        var pending: CompletableDeferred<Unit>? = null
        val modes = mutableListOf<AgentNewsNotificationMode>()
        val times = mutableListOf<AgentDigestTime>()

        override suspend fun setMode(
            mode: AgentNewsNotificationMode
        ): AgentNewsNotificationOutcome {
            modes += mode
            pending?.await()
            pending = null
            if (outcome == AgentNewsNotificationOutcome.Ok) this.mode = mode
            return outcome
        }

        override suspend fun setDigestTime(time: AgentDigestTime): AgentNewsNotificationOutcome {
            times += time
            digestTime = time
            pending?.await()
            pending = null
            return outcome
        }
    }

    companion object {
        private val SCHEDULE = AgentNewsDigestSchedule(21, 0, "Europe/Moscow")

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
            "\$agent_digest_title" to "Top news of the day",
            "\$agent_digest_meta.oneValue" to "%count% news item",
            "\$agent_digest_meta.otherValue" to "%count% news items",
            "\$agent_digest_more.oneValue" to "and %count% more — it's above in the feed",
            "\$agent_digest_more.otherValue" to "and %count% more — they're above in the feed",
            "\$agent_digest_more_count.oneValue" to "and %count% more",
            "\$agent_digest_more_count.otherValue" to "and %count% more",
            "\$agent_digest_notifications_daily_hint" to
                "One notification at %time% with the day's top news."
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
