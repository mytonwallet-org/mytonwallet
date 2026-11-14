package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import java.lang.reflect.Proxy
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentCachedHistories
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportLabelStyle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.getAgentSupportLabelStyle
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

class AgentThreadListModelTest {
    @Test
    fun labelsAChatWithSupportBrightWithAnOperatorAndMutedWhileItWaits() {
        assertEquals(
            AgentSupportLabelStyle.ACTIVE,
            getAgentSupportLabelStyle(AgentV2ThreadSupport("operator"))
        )
        assertEquals(
            AgentSupportLabelStyle.MUTED,
            getAgentSupportLabelStyle(AgentV2ThreadSupport("waiting"))
        )
        assertNull(getAgentSupportLabelStyle(AgentV2ThreadSupport("closed")))
        assertNull(getAgentSupportLabelStyle(null))
    }

    @Test
    fun paginationReplacesOverlappingThreadsAndStopsAtRepeatedCursor() = runBlocking {
        val first = item("first", "2026-10-19T08:00:00Z")
        val second = item("second", "2026-10-18T08:00:00Z")
        val updatedSecond = second.copy(preview = "Updated answer")
        val client = FakeClient().apply {
            onList = { cursor ->
                if (cursor == null) {
                    AgentV2ThreadListResponse(listOf(first, second), "next")
                } else {
                    AgentV2ThreadListResponse(listOf(updatedSecond, item("third")), "next")
                }
            }
        }
        val model = makeModel(client)

        model.refresh()
        model.loadMore()
        model.loadMore()

        assertEquals(listOf(null, "next"), client.listCalls)
        assertEquals(listOf("first", "second", "third"), model.items.map { it.thread.id })
        assertEquals("Updated answer", model.items[1].preview)
        assertNull(model.nextCursor)
        assertFalse(model.isLoading)
    }

    @Test
    fun failedRefreshAndPageKeepRowsWithoutToastsAndMarkOnlyThePage() = runBlocking {
        val initial = item("chat")
        val errors = mutableListOf<Throwable>()
        val loadingStates = mutableListOf<Boolean>()
        val client = FakeClient().apply {
            onList = { AgentV2ThreadListResponse(listOf(initial), "next") }
        }
        val model = makeModel(client)
        model.refresh()
        model.onError = { errors.add(it) }
        model.onChange = { loadingStates.add(model.isLoading) }

        listOf(model::refresh, model::loadMore).forEach { load ->
            val result = CompletableDeferred<AgentV2ThreadListResponse>()
            client.onList = { result.await() }
            loadingStates.clear()

            load()

            assertTrue(model.isLoading)
            assertEquals(listOf(initial), model.items)
            assertEquals("next", model.nextCursor)
            assertEquals(listOf(true), loadingStates)

            result.completeExceptionally(IllegalStateException("Connection interrupted"))

            assertEquals(listOf(initial), model.items)
            assertEquals("next", model.nextCursor)
            assertFalse(model.isLoading)
            assertEquals(listOf(true, false), loadingStates)
            assertTrue(errors.isEmpty())
        }

        assertEquals(listOf(null, null, "next"), client.listCalls)
        assertFalse(model.hasLoadFailed)
        assertTrue(model.hasPageLoadFailed)
    }

    @Test
    fun failedLoadWithoutChatsMarksTheListFailedUntilALoadBringsThem() = runBlocking {
        val chat = item("chat")
        val client = FakeClient().apply { onList = { error("Offline") } }
        val model = makeModel(client)

        model.refresh()

        assertTrue(model.hasLoaded)
        assertTrue(model.hasLoadFailed)
        assertTrue(model.items.isEmpty())

        // The failure stays while the list loads again
        val result = CompletableDeferred<AgentV2ThreadListResponse>()
        client.onList = { result.await() }
        model.refresh()

        assertTrue(model.isLoading)
        assertTrue(model.hasLoadFailed)

        result.complete(AgentV2ThreadListResponse(listOf(chat), "next"))

        assertFalse(model.hasLoadFailed)
        assertEquals(listOf(chat), model.items)

        // A page that fails marks the list's end until the page loads
        client.onList = { error("Offline") }
        model.loadMore()

        assertTrue(model.hasPageLoadFailed)
        assertFalse(model.hasLoadFailed)
        assertEquals(listOf(chat), model.items)

        client.onList = { AgentV2ThreadListResponse(listOf(item("older", "2025-12-31T00:00:00Z"))) }
        model.loadMore()

        assertFalse(model.hasPageLoadFailed)
        assertEquals(listOf("chat", "older"), model.items.map { it.thread.id })
        assertEquals(listOf(null, null, "next", "next"), client.listCalls)
    }

    @Test
    fun cachedChatsShowUntilTheFirstPageReplacesThem() = runBlocking {
        val shared = item("shared", "2026-01-02T00:00:00Z")
        val cached = listOf(item("removed"), shared)
        val fresh = listOf(shared.copy(preview = "New answer"), item("new", "2026-01-03T00:00:00Z"))
        val page = CompletableDeferred<AgentV2ThreadListResponse>()
        var readStateWrites = 0
        val client = FakeClient().apply {
            onCached = { cached }
            onList = { page.await() }
        }
        val model = makeModel(
            client,
            readState = AgentThreadReadState(read = { null }, write = { readStateWrites++ })
        )

        model.refresh()

        assertEquals(listOf("shared", "removed"), model.items.map { it.thread.id })
        assertTrue(model.hasLoaded)
        assertTrue(model.isLoading)
        assertFalse(model.hasLoadFailed)
        assertNull(model.nextCursor)
        assertEquals(0, readStateWrites)
        model.loadMore()
        assertEquals(listOf<String?>(null), client.listCalls)

        page.complete(AgentV2ThreadListResponse(fresh, "next"))

        assertEquals(listOf("new", "shared"), model.items.map { it.thread.id })
        assertEquals("New answer", model.items[1].preview)
        assertEquals("next", model.nextCursor)
        assertTrue(readStateWrites > 0)
    }

    @Test
    fun cachedChatsShowOnlyBeforeTheirPageEndsAndWhileTheLoadIsCurrent() = runBlocking {
        // The page ends first, as it loads or fails, or the list starts over
        val endings = listOf<
            Pair<
                String,
                suspend (
                    CompletableDeferred<AgentV2ThreadListResponse>,
                    AgentThreadListModel
                ) -> Unit
                >
            >(
            "loaded" to { page, _ -> page.complete(AgentV2ThreadListResponse(emptyList())) },
            "failed" to { page, _ -> page.completeExceptionally(IllegalStateException("Offline")) },
            "reset" to { _, model -> model.reset() }
        )
        for ((case, end) in endings) {
            val page = CompletableDeferred<AgentV2ThreadListResponse>()
            val cache = CompletableDeferred<List<AgentV2ThreadListItem>?>()
            val client = FakeClient().apply {
                onCached = { cache.await() }
                onList = { page.await() }
            }
            val model = makeModel(client)
            model.refresh()

            end(page, model)
            cache.complete(listOf(item("cached")))

            assertTrue(case, model.items.isEmpty())
            assertEquals(case, case == "failed", model.hasLoadFailed)
        }

        // A missing, empty or unreadable copy leaves the placeholder and the failure as they are
        val copies = listOf<suspend () -> List<AgentV2ThreadListItem>?>(
            { null },
            { emptyList() },
            { throw IllegalStateException("Bridge failed") }
        )
        for (copy in copies) {
            val page = CompletableDeferred<AgentV2ThreadListResponse>()
            val client = FakeClient().apply {
                onCached = copy
                onList = { page.await() }
            }
            val model = makeModel(client)
            model.refresh()

            assertFalse(model.hasLoaded)

            page.completeExceptionally(IllegalStateException("Offline"))

            assertTrue(model.hasLoadFailed)
            assertTrue(model.items.isEmpty())
        }
    }

    @Test
    fun cachedChatsArrivingAfterADeletionLeaveTheDeletedChatOut() = runBlocking {
        val cache = CompletableDeferred<List<AgentV2ThreadListItem>?>()
        val page = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onCached = { cache.await() }
            onList = { page.await() }
        }
        val model = makeModel(client)
        model.refresh()

        model.removeDeletedThread("deleted")
        cache.complete(listOf(item("deleted"), item("kept")))
        page.completeExceptionally(IllegalStateException("Offline"))

        assertEquals(listOf("kept"), model.items.map { it.thread.id })
    }

    @Test
    fun failedFirstPageKeepsTheCachedChatsUntilARefreshReplacesThem() = runBlocking {
        val cached = listOf(item("first"), item("second"), item("third"))
        val page = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onCached = { cached }
            onList = { page.await() }
        }
        val model = makeModel(client)

        model.refresh()
        page.completeExceptionally(IllegalStateException("Offline"))

        assertEquals(cached.map { it.thread.id }, model.items.map { it.thread.id })
        assertFalse(model.hasLoadFailed)
        assertFalse(model.isLoading)

        // The refresh replaces the copy with the first page rather than loading as many chats as it shows
        client.onList = { AgentV2ThreadListResponse(listOf(item("fresh")), "next") }
        model.refresh()

        assertEquals(listOf("fresh"), model.items.map { it.thread.id })
        assertEquals(listOf<String?>(null, null), client.listCalls)
        assertEquals(1, client.cachedCalls)
    }

    @Test
    fun firstPageReadsTheCopiesOfItsLatestChatsAndRereadsOnlyChangedOnes() = runBlocking {
        val chats = (0..11).map { index ->
            item("c$index", "2026-01-${(28 - index).toString().padStart(2, '0')}T00:00:00Z")
                .let { it.copy(thread = it.thread.copy(messageCount = 1)) }
        }
        val news = item("news", "2026-02-01T00:00:00Z").let {
            it.copy(
                thread = it.thread.copy(
                    messageCount = 1,
                    news = AgentV2ThreadNewsCard(1, "News", publishedAt = "2026-02-01T00:00:00Z")
                )
            )
        }
        val page = listOf(news, item("empty", "2026-01-30T00:00:00Z")) + chats
        val reads = mutableListOf<String>()
        val histories = AgentCachedHistories(this) { threadId ->
            reads += threadId
            if (threadId == "c3") {
                null
            } else {
                AgentV2CachedMessages(AgentV2ThreadSummary(threadId, 1), emptyList(), false)
            }
        }
        suspend fun awaitReads(count: Int) = withTimeout(1_000) {
            while (reads.size < count) yield()
        }
        val freshPage = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onCached = { page }
            onList = { freshPage.await() }
        }
        val model = makeModel(client, cachedHistories = histories)

        // The cached first page starts the reads, and the same fresh page reads nothing again
        model.refresh()
        awaitReads(10)
        freshPage.complete(AgentV2ThreadListResponse(page))
        yield()
        yield()

        // The top chat is read last, so it is the most recent in the SDK's cache and in memory
        assertEquals((9 downTo 0).map { "c$it" }, reads)
        assertNull(histories.get("c3"))
        assertNull(histories.get("c10"))
        assertNull(histories.get("news"))
        assertTrue(histories.get("c9") != null)

        val changed = chats[1].copy(thread = chats[1].thread.copy(messageCount = 2))
        client.onList = {
            AgentV2ThreadListResponse(listOf(news, changed) + chats.filterNot { it == chats[1] })
        }
        model.refresh()
        awaitReads(11)
        yield()
        assertEquals("c1", reads.last())
        assertEquals(11, reads.size)

        // At most ten chats: the least recently stored makes way, which is the lowest chat rather than the top one
        histories.storeLoadedPage(chats[10].thread, listOf(message("c10")), hasOlder = false)
        histories.storeLoadedPage(chats[11].thread, listOf(message("c11")), hasOlder = false)
        assertTrue(histories.get("c0") != null)
        assertNull(histories.get("c9"))
        assertTrue(histories.get("c11") != null)

        // The evicted chat is read again although its summary did not change, and the top chats stay
        model.refresh()
        awaitReads(12)
        yield()
        assertEquals("c9", reads[11])
        assertTrue(histories.get("c9") != null)
        assertTrue(histories.get("c0") != null)

        model.delete(chats[2].thread)
        assertNull(histories.get("c2"))
    }

    @Test
    fun lateCacheReadRestoresNoReplacedOrRemovedHistory() = runBlocking {
        val thread = AgentV2ThreadSummary("chat", 1, messageCount = 2)
        val other = AgentV2ThreadSummary("other", 1, messageCount = 1)
        fun copyOf(summary: AgentV2ThreadSummary) =
            AgentV2CachedMessages(summary, listOf(message(summary.id)), hasOlder = false)

        // The chat's copy changes while the SDK reads it
        val changes = listOf<Pair<String, (AgentCachedHistories) -> Unit>>(
            "fresh page" to {
                it.storeLoadedPage(thread.copy(revision = 2), listOf(message("chat")), false)
            },
            "empty page" to {
                it.storeLoadedPage(thread.copy(revision = 2, messageCount = 0), emptyList(), false)
            },
            "removal" to { it.remove("chat") },
            "reset" to { it.clear() }
        )
        for ((case, change) in changes) {
            val requested = CompletableDeferred<Unit>()
            val read = CompletableDeferred<AgentV2CachedMessages?>()
            val histories = AgentCachedHistories(this) {
                requested.complete(Unit)
                read.await()
            }
            histories.prefetch(listOf(thread))
            withTimeout(1_000) { requested.await() }

            change(histories)
            read.complete(copyOf(thread))
            yield()
            yield()

            val expectedRevision = 2.takeIf { case == "fresh page" }
            assertEquals(case, expectedRevision, histories.get("chat")?.thread?.revision)
        }

        // A removal before its queued read starts
        val reads = mutableListOf<String>()
        val firstRead = CompletableDeferred<AgentV2CachedMessages?>()
        val histories = AgentCachedHistories(this) { threadId ->
            reads += threadId
            if (threadId == other.id) firstRead.await() else copyOf(thread)
        }
        // The lower chat is read first
        histories.prefetch(listOf(thread, other))
        withTimeout(1_000) {
            while (reads.isEmpty()) yield()
        }

        histories.remove("chat")
        firstRead.complete(copyOf(other))
        yield()
        yield()

        assertNull(histories.get("chat"))
        assertEquals(listOf("other"), reads)
        assertTrue(histories.get("other") != null)
    }

    @Test
    fun failedDeletionStillReportsTheErrorAndKeepsTheThread() = runBlocking {
        val initial = item("chat")
        val error = IllegalStateException("Deletion failed")
        val errors = mutableListOf<Throwable>()
        val client = FakeClient().apply {
            onList = { AgentV2ThreadListResponse(listOf(initial), "next") }
            onDelete = { throw error }
        }
        val model = makeModel(client)
        model.onError = { errors.add(it) }
        model.refresh()

        model.delete(initial.thread)

        assertSame(error, errors.single())
        assertEquals(1, client.deleteCalls)
        assertEquals(listOf(initial), model.items)
        assertEquals("next", model.nextCursor)
        assertFalse(model.isLoading)
    }

    @Test
    fun pinAndRenamePreservePreviewAndCannotBeOverwrittenByOlderListResponse() = runBlocking {
        val initial = item("chat", "2026-10-19T08:00:00Z")
        val oldResult = CompletableDeferred<AgentV2ThreadListResponse>()
        val updates = mutableListOf<AgentV2ThreadUpdate>()
        val client = FakeClient().apply {
            onList = { AgentV2ThreadListResponse(listOf(initial)) }
            onUpdate = { id, update ->
                updates.add(update)
                val updated = initial.thread.copy(
                    id = id,
                    isPinned = update.isPinned,
                    title = update.title
                )
                onList =
                    { AgentV2ThreadListResponse(listOf(initial.copy(thread = updated))) }
                AgentV2ThreadResponse(updated)
            }
        }
        val model = makeModel(client)
        model.refresh()
        client.onList = { withContext(NonCancellable) { oldResult.await() } }
        model.refresh()

        model.setPinned(initial.thread, true)
        oldResult.complete(AgentV2ThreadListResponse(listOf(initial)))

        assertEquals(true, model.items.single().thread.isPinned)
        assertEquals(initial.preview, model.items.single().preview)
        model.rename(model.items.single().thread, "  Custom title  ")
        assertEquals("Custom title", updates.last().title)
        model.rename(model.items.single().thread, " \n ")
        assertNull(updates.last().title)
        assertNull(updates.last().isPinned)
        assertEquals(initial.preview, model.items.single().preview)
    }

    @Test
    fun failedPinPreservesThreadChangesReceivedWhileTheRequestWasPending() = runBlocking {
        val initial = item("chat")
        val pendingPin = CompletableDeferred<AgentV2ThreadResponse>()
        val client = FakeClient().apply {
            onList = { AgentV2ThreadListResponse(listOf(initial)) }
            onUpdate = { _, _ -> pendingPin.await() }
        }
        val model = makeModel(client)
        model.refresh()
        model.setPinned(initial.thread, true)
        val changed = initial.thread.copy(revision = 2, title = "Generated title", isPinned = true)
        model.applyThreadChange(changed)

        pendingPin.completeExceptionally(IllegalStateException("Pin refused"))

        assertEquals(changed.copy(isPinned = initial.thread.isPinned), model.items.single().thread)
        assertEquals(initial.preview, model.items.single().preview)
    }

    @Test
    fun deletionCannotBeDuplicatedOrOverwrittenByAnInflightLoad() = runBlocking {
        val initial = item("chat")
        val pendingDelete = CompletableDeferred<AgentV2ThreadDeleteResponse>()
        val oldResult = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onList = { AgentV2ThreadListResponse(listOf(initial)) }
            onDelete = {
                pendingDelete.await().also {
                    onList = { AgentV2ThreadListResponse(emptyList()) }
                }
            }
        }
        val model = makeModel(client)
        model.refresh()
        client.onList = { withContext(NonCancellable) { oldResult.await() } }
        model.refresh()

        model.delete(initial.thread)
        model.delete(initial.thread)
        assertEquals(1, client.deleteCalls)
        pendingDelete.complete(AgentV2ThreadDeleteResponse(initial.thread.id, false))
        oldResult.complete(AgentV2ThreadListResponse(listOf(initial)))

        assertTrue(model.items.isEmpty())
        assertFalse(model.isLoading)
    }

    @Test
    fun mutationsAndThreadChangesKeepLoadedPagesAndOnlyUnknownThreadsRefresh() = runBlocking {
        val first = item("first", "2026-10-19T08:00:00Z")
        val second = item("second", "2026-10-18T08:00:00Z")
        val client = FakeClient().apply {
            onList = { cursor ->
                if (cursor == null) {
                    AgentV2ThreadListResponse(listOf(first), "next")
                } else {
                    AgentV2ThreadListResponse(listOf(second), "more")
                }
            }
            onUpdate = { id, update ->
                val thread = if (id == first.thread.id) first.thread else second.thread
                AgentV2ThreadResponse(thread.copy(title = update.title, isPinned = update.isPinned))
            }
        }
        val model = makeModel(client)
        model.refresh()
        model.loadMore()
        val changed = second.thread.copy(
            revision = 2,
            title = "Generated title",
            icon = "💡",
            isPinned = true,
            lastActivityAt = "2026-10-19T09:00:00Z"
        )

        model.applyThreadChange(changed)

        assertEquals(listOf(changed, first.thread), model.items.map { it.thread })
        assertEquals(second.preview, model.items.first().preview)
        assertEquals("more", model.nextCursor)
        assertEquals(2, client.listCalls.size)

        model.rename(changed, "Custom title")
        model.setPinned(first.thread, true)
        assertEquals(2, model.items.size)
        assertEquals("more", model.nextCursor)
        assertEquals(2, client.listCalls.size)
        model.delete(second.thread)
        assertEquals(listOf("first"), model.items.map { it.thread.id })
        assertEquals("more", model.nextCursor)
        assertEquals(2, client.listCalls.size)

        model.applyThreadChange(item("unknown").thread)

        assertEquals(3, client.listCalls.size)
        assertNull(client.listCalls.last())
        assertEquals("next", model.nextCursor)
    }

    @Test
    fun resetDiscardsRequestsAndMutationsFromThePreviousWalletSession() = runBlocking {
        val pending = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onList = { withContext(NonCancellable) { pending.await() } }
        }
        val model = makeModel(client)
        model.refresh()
        model.reset()
        pending.complete(AgentV2ThreadListResponse(listOf(item("previous-wallet")), "old-cursor"))

        assertTrue(model.items.isEmpty())
        assertNull(model.nextCursor)
        assertFalse(model.isLoading)
        assertFalse(model.hasLoaded)
    }

    @Test
    fun pinningTakesPrecedenceOverActivityAndDaySectionsUseLastActivity() {
        val yesterday = item("yesterday", "2026-10-18T10:00:00Z")
        val today = item("today", "2026-10-19T10:00:00Z")
        val oldPinned = item("pinned", "2026-09-01T10:00:00Z", isPinned = true)

        val sections =
            groupAgentThreads(listOf(yesterday, today, oldPinned), TimeZone.getTimeZone("UTC"))

        assertEquals(
            listOf("pinned", "today", "yesterday"),
            sections.flatMap { section ->
                section.items.map { it.thread.id }
            }
        )
        assertNull(sections.first().day)
        assertEquals(date("2026-10-19T00:00:00Z").time, sections[1].day)
        assertEquals(date("2026-10-18T00:00:00Z").time, sections[2].day)
    }

    @Test
    fun calendarDayGroupsSurviveDaylightSavingAndTimestampUsesTheSameLocalDay() {
        val zone = TimeZone.getTimeZone("America/New_York")
        val now = date("2026-03-09T00:30:00-04:00")
        val yesterday = date("2026-03-08T00:30:00-05:00")

        assertEquals(
            AgentThreadDateFormatting.DayGroup.YESTERDAY,
            AgentThreadDateFormatting.dayGroup(yesterday, now, zone)
        )
        assertEquals(
            AgentThreadDateFormatting.DayGroup.WEEKDAY,
            AgentThreadDateFormatting.dayGroup(date("2026-03-03T22:00:00-05:00"), now, zone)
        )
        assertEquals(
            AgentThreadDateFormatting.DayGroup.DATE,
            AgentThreadDateFormatting.dayGroup(date("2026-03-02T22:00:00-05:00"), now, zone)
        )
        assertEquals(
            "Sun",
            AgentThreadDateFormatting.formatDate(yesterday, now, false, Locale.US, zone)
        )
    }

    @Test
    fun topRowsShowTheTimeTodayTheWeekdayWithinAWeekTheDayThisYearAndTheNumericDateBefore() {
        val now = date("2026-10-28T00:57:00Z")
        val russian = Locale.forLanguageTag("ru")

        assertEquals("00:00", formatTopRowTime("2026-10-28T00:00:00Z", now))
        assertEquals("Tue", formatTopRowTime("2026-10-27T23:57:00Z", now))
        assertEquals("Thu", formatTopRowTime("2026-10-22T23:59:00Z", now))
        assertEquals("пн", formatTopRowTime("2026-10-26T12:00:00Z", now, russian))
        assertEquals("Oct 21", formatTopRowTime("2026-10-21T23:59:00Z", now))
        assertEquals("21 окт", formatTopRowTime("2026-10-21T23:59:00Z", now, russian))
        // Every Russian month is cut to three letters
        assertEquals("4 сен", formatTopRowTime("2026-09-04T10:00:00Z", now, russian))
        assertEquals("4 фев", formatTopRowTime("2026-02-04T10:00:00Z", now, russian))

        // The last week reaches into the year before, and the rest of that year is numeric
        val newYear = date("2027-01-01T00:30:00Z")
        assertEquals("Thu", formatTopRowTime("2026-12-31T23:00:00Z", newYear))
        assertEquals("Wed", formatTopRowTime("2026-12-30T23:00:00Z", newYear))
        assertEquals("12/20/26", formatTopRowTime("2026-12-20T23:00:00Z", newYear))
        assertEquals("20.12.26", formatTopRowTime("2026-12-20T23:00:00Z", newYear, russian))

        // A row under its day's header shows the time
        assertEquals(
            "12:57",
            AgentThreadDateFormatting.formatRowTimestamp(
                date("2026-10-27T12:57:00Z"),
                now,
                shouldShowDateWhenNotToday = false,
                is24HourFormat = true,
                locale = Locale.US,
                timeZone = TimeZone.getTimeZone("UTC")
            )
        )
    }

    @Test
    fun dateCapsulesNameTodayAndYesterdayThenTheDateWithTheYearForAnotherYear() {
        val now = date("2026-11-07T12:00:00Z")

        assertEquals("Today", formatCapsuleDay("2026-11-07T00:10:00Z", now))
        assertEquals("Yesterday", formatCapsuleDay("2026-11-06T22:47:00Z", now))
        // The rest of the week takes the date, not the weekday
        assertEquals("November 3", formatCapsuleDay("2026-11-03T10:00:00Z", now))
        assertEquals("3 ноября", formatCapsuleDay("2026-11-03T10:00:00Z", now, "ru"))
        assertEquals("November 7, 2025", formatCapsuleDay("2025-11-07T10:00:00Z", now))
        assertEquals("7 ноября 2025", formatCapsuleDay("2025-11-07T10:00:00Z", now, "ru"))

        // A month abbreviated with a single dot loses it, and one with dots inside keeps them all
        val october = date("2026-10-07T10:00:00Z")
        fun formatShortDay(langCode: String) = AgentThreadDateFormatting
            .makeShortMonthFormat("d MMM", Locale.forLanguageTag(langCode))
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(october)
        assertEquals("7 Okt", formatShortDay("de"))
        assertEquals("7 ต.ค.", formatShortDay("th"))

        // The platform's Russian and Ukrainian dates end the year with "г." and "р.", which Telegram's leave out
        assertEquals("d MMMM y", AgentThreadDateFormatting.removeYearSuffix("d MMMM y 'г'."))
        assertEquals("d MMMM y", AgentThreadDateFormatting.removeYearSuffix("d MMMM y 'р'."))
        assertEquals(
            "d 'de' MMMM 'de' y",
            AgentThreadDateFormatting.removeYearSuffix("d 'de' MMMM 'de' y")
        )
    }

    @Test
    fun answeringStatusHoldsUntilALaterLoadBringsTheAnswersPreview() = runBlocking {
        val question = item("chat").copy(preview = "Question")
        val client = FakeClient().apply { onList = { AgentV2ThreadListResponse(listOf(question)) } }
        val readState = AgentThreadReadState(read = { null }, write = {})
        val model = makeModel(client, readState)
        model.refresh()
        val changes = mutableListOf<Set<String>>()
        model.onActivityChange = { changes.add(it) }

        model.handleUpdate(
            AgentV2Update.RunStarted("client-run", "run", "chat", threadRevision = 2)
        )
        assertEquals("Analyzing", model.getActivityText("chat"))
        model.handleUpdate(AgentV2Update.TextDelta("client-run", "run", "chat", "answer", "Hi"))
        assertEquals("Writing", model.getActivityText("chat"))
        model.handleUpdate(
            AgentV2Update.MessageCompleted("client-run", "run", "chat", "answer", "complete")
        )

        // The row keeps the status rather than showing the question again
        assertEquals("Writing", model.getActivityText("chat"))
        assertTrue(readState.isUnread(question.thread))
        client.onList = {
            AgentV2ThreadListResponse(
                listOf(
                    AgentV2ThreadListItem(
                        question.thread.copy(revision = 3, messageCount = 2),
                        preview = "Answer"
                    )
                )
            )
        }
        model.refresh()

        assertNull(model.getActivityText("chat"))
        assertEquals("Answer", model.items.single().preview)
        assertEquals(setOf("chat"), changes.last())
    }

    @Test
    fun unreadStatePersistsAndClearsWhenTheChatShows() {
        var stored: String? = null
        val thread = AgentV2ThreadSummary("chat", revision = 1, messageCount = 2)
        val readState = AgentThreadReadState(read = { stored }, write = { stored = it })

        // A chat the device has never shown counts as read
        assertFalse(readState.isUnread(thread.copy(messageCount = 9)))
        readState.observe(listOf(thread), answeringThreadIds = emptySet())
        assertTrue(readState.isUnread(thread.copy(messageCount = 4)))

        readState.onChatAppeared("chat")
        readState.onAnswerCompleted("chat")
        assertFalse(readState.isUnread(thread.copy(messageCount = 4)))
        readState.onChatDisappeared("chat")
        readState.observe(listOf(thread.copy(messageCount = 4)), answeringThreadIds = emptySet())
        assertFalse(readState.isUnread(thread.copy(messageCount = 4)))

        readState.onAnswerCompleted("chat")
        val restored = AgentThreadReadState(read = { stored }, write = { stored = it })
        assertTrue(restored.isUnread(thread.copy(messageCount = 4)))
    }

    @Test
    fun operatorRepliesStayUnreadUntilTheirLoadedHistoryShowsAndPersistAcrossVisibility() {
        var stored: String? = "chat\t4\t0\t0"
        val readState = AgentThreadReadState(read = { stored }, write = { stored = it })
        val thread = AgentV2ThreadSummary(
            "chat",
            revision = 4,
            messageCount = 4,
            support = AgentV2ThreadSupport("operator", "2026-11-08T12:00:00.100Z")
        )
        assertFalse(readState.isUnread(thread.copy(support = null)))
        readState.observe(listOf(thread), answeringThreadIds = emptySet())
        assertTrue(readState.isUnread(thread))

        readState.onChatAppeared(thread.id)
        assertTrue(readState.isUnread(thread))
        readState.markSupportSeen(thread.id, "2026-11-08T12:00:00.000Z")
        assertTrue(readState.isUnread(thread))
        readState.markSupportSeen(thread.id, thread.support?.lastOperatorMessageAt)
        assertFalse(readState.isUnread(thread))
        readState.onChatDisappeared(thread.id, seenMessageCount = thread.messageCount)

        val restored = AgentThreadReadState(read = { stored }, write = { stored = it })
        assertFalse(restored.isUnread(thread))
        val newer = thread.copy(
            support = AgentV2ThreadSupport("operator", "2026-11-08T12:00:01.100Z")
        )
        restored.onChatAppeared(thread.id)
        restored.observe(listOf(newer), answeringThreadIds = emptySet())
        assertTrue(restored.isUnread(newer))
        restored.markSupportSeen(thread.id, newer.support?.lastOperatorMessageAt)
        restored.markSupportSeen(thread.id, thread.support?.lastOperatorMessageAt)
        assertFalse(restored.isUnread(newer))
        restored.onChatDisappeared(thread.id, seenMessageCount = newer.messageCount)
        assertFalse(restored.isUnread(newer))
    }

    @Test
    fun loadedOperatorHistoryAcknowledgedBeforeItsSummaryKeepsTheChatRead() {
        val readState = AgentThreadReadState(read = { null }, write = {})
        val thread = AgentV2ThreadSummary("chat", revision = 2, messageCount = 2)
        readState.observe(listOf(thread), answeringThreadIds = emptySet())
        readState.onChatAppeared(thread.id)
        val loadedOperatorMessageAt = "2026-11-08T12:00:00.100Z"
        readState.markSupportSeen(thread.id, loadedOperatorMessageAt)
        readState.onChatDisappeared(thread.id, seenMessageCount = thread.messageCount)

        val summary = thread.copy(
            support = AgentV2ThreadSupport("closed", loadedOperatorMessageAt)
        )
        readState.observe(listOf(summary), answeringThreadIds = emptySet())
        assertFalse(readState.isUnread(summary))
    }

    @Test
    fun supportDeliveryDoesNotMarkAnAgentAnswerUnread() = runBlocking {
        val thread = item("chat")
        val client = FakeClient().apply { onList = { AgentV2ThreadListResponse(listOf(thread)) } }
        val readState = AgentThreadReadState(read = { null }, write = {})
        val model = makeModel(client, readState)
        model.refresh()
        model.handleUpdate(AgentV2Update.RunStarted("client-run", "run", "chat", 2))
        model.handleUpdate(
            AgentV2Update.MessageCompleted(
                "client-run",
                "run",
                "chat",
                "question",
                "delivered_to_support"
            )
        )

        assertFalse(model.isUnread(thread.thread))
        model.reset()
    }

    @Test
    fun chatLeftWhileAnsweringOpensAtTheAnswerItHadNotShown() {
        var stored: String? = null
        val thread = AgentV2ThreadSummary("chat", revision = 1, messageCount = 4)
        val readState = AgentThreadReadState(read = { stored }, write = { stored = it })

        readState.onChatAppeared("chat")
        // The chat showed three settled messages; the answer still streamed as the user left
        readState.onChatDisappeared("chat", seenMessageCount = 3)
        readState.onAnswerCompleted("chat")
        readState.observe(listOf(thread), answeringThreadIds = emptySet())

        val restored = AgentThreadReadState(read = { stored }, write = { stored = it })
        assertTrue(restored.isUnread(thread))
        assertEquals(3, restored.getSeenMessageCountIfUnread(thread))
        restored.onChatAppeared("chat")
        assertNull(restored.getSeenMessageCountIfUnread(thread))
    }

    @Test
    fun discussionShowsItsNewsPictureOnlyWhileThePostIsItsLatestMessage() {
        val news = AgentV2ThreadNewsCard(
            eventId = 12,
            headline = "Stablecoin supply reaches a new record",
            imageUrl = "https://example.com/news.png",
            publishedAt = "2026-10-19T09:00:00Z"
        )
        val discussion = AgentV2ThreadSummary("news", revision = 1, messageCount = 1, news = news)

        assertEquals(news.imageUrl, agentThreadPreviewImageUrl(discussion))
        assertNull(agentThreadPreviewImageUrl(discussion.copy(messageCount = 3)))
        assertNull(agentThreadPreviewImageUrl(discussion.copy(news = news.copy(imageUrl = " "))))
        assertNull(agentThreadPreviewImageUrl(discussion.copy(news = null)))
    }

    @Test
    fun contactSupportWaitsForTheServerChatsAndOpensTheLatestOneSupportHas() = runBlocking {
        val page = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onCached = { listOf(supportItem("cached", "operator")) }
            onList = { page.await() }
        }
        val model = makeModel(client)
        val opened = mutableListOf<AgentV2ThreadSummary?>()
        model.refresh()
        assertTrue(model.isCacheShown)

        model.requestSupportThread { opened += it }
        yield()
        assertTrue(opened.isEmpty())
        page.complete(
            AgentV2ThreadListResponse(
                listOf(
                    item("plain", "2026-01-05T00:00:00Z"),
                    supportItem("closed", "closed", "2026-01-04T00:00:00Z"),
                    supportItem("operator", "operator", "2026-01-01T00:00:00Z"),
                    supportItem("waiting", "waiting", "2026-01-02T00:00:00Z")
                )
            )
        )
        withTimeout(1_000) { while (opened.isEmpty()) yield() }
        assertEquals(listOf("waiting"), opened.map { it?.id })

        // The server's chats at hand answer at once, without a chat support has with a new one
        client.onList = { AgentV2ThreadListResponse(listOf(item("plain"))) }
        model.refresh()
        model.requestSupportThread { opened += it }
        assertEquals(listOf("waiting", null), opened.map { it?.id })
    }

    @Test
    fun contactSupportIsDroppedWhenTheChatsFailToLoad() = runBlocking {
        val client = FakeClient().apply { onList = { error("Unavailable") } }
        val model = makeModel(client)
        val opened = mutableListOf<AgentV2ThreadSummary?>()
        model.requestSupportThread { opened += it }
        assertTrue(model.hasLoadFailed)

        client.onList = { AgentV2ThreadListResponse(listOf(supportItem("waiting", "waiting"))) }
        model.refresh()
        assertTrue(opened.isEmpty())
    }

    @Test
    fun contactSupportNeverChoosesFromTheCachedChatsAPageFailedBehind() = runBlocking {
        val page = CompletableDeferred<AgentV2ThreadListResponse>()
        val client = FakeClient().apply {
            onCached = { listOf(supportItem("cached", "operator")) }
            onList = { page.await() }
        }
        val model = makeModel(client)
        val opened = mutableListOf<AgentV2ThreadSummary?>()
        model.refresh()
        page.completeExceptionally(IllegalStateException("Offline"))
        assertTrue(model.isCacheShown)
        assertFalse(model.isLoading)

        model.requestSupportThread { opened += it }
        assertTrue(opened.isEmpty())
    }

    private fun supportItem(id: String, state: String, timestamp: String = "2026-01-01T00:00:00Z") =
        item(id, timestamp).let {
            it.copy(thread = it.thread.copy(support = AgentV2ThreadSupport(state)))
        }

    private fun item(
        id: String,
        timestamp: String = "2026-01-01T00:00:00Z",
        isPinned: Boolean = false
    ) = AgentV2ThreadListItem(
        AgentV2ThreadSummary(id, revision = 1, lastActivityAt = timestamp, isPinned = isPinned),
        preview = "Answer in $id"
    )

    private fun date(timestamp: String): Date = requireNotNull(parseAgentV2Timestamp(timestamp))

    private fun formatTopRowTime(timestamp: String, now: Date, locale: Locale = Locale.US): String =
        AgentThreadDateFormatting.formatRowTimestamp(
            date(timestamp),
            now,
            shouldShowDateWhenNotToday = true,
            is24HourFormat = true,
            locale = locale,
            timeZone = TimeZone.getTimeZone("UTC")
        )

    private fun formatCapsuleDay(timestamp: String, now: Date, langCode: String = "en"): String =
        AgentThreadDateFormatting.formatDayText(
            date(timestamp),
            now,
            today = "Today",
            yesterday = "Yesterday",
            langCode = langCode,
            timeZone = TimeZone.getTimeZone("UTC")
        )

    private fun message(threadId: String) = AgentV2PersistedMessage(
        "$threadId-question",
        threadId,
        "user",
        "complete",
        content = AgentV2MessageContent.Markdown("Question"),
        createdAt = "2026-01-01T00:00:00Z"
    )

    private fun CoroutineScope.makeModel(
        client: FakeClient,
        readState: AgentThreadReadState = AgentThreadReadState(read = { null }, write = {}),
        cachedHistories: AgentCachedHistories = AgentCachedHistories(this) { null }
    ) = AgentThreadListModel(
        CoroutineScope(coroutineContext + Dispatchers.Unconfined),
        client,
        readState = readState,
        activityTracker = AgentThreadActivityTracker(
            analyzingText = { "Analyzing" },
            writingText = { "Writing" },
            stepText = { it.code }
        ),
        cachedHistories = cachedHistories,
        activityHoldMillis = Long.MAX_VALUE
    )

    private class FakeClient : AgentThreadListClient {
        val listCalls = mutableListOf<String?>()
        var cachedCalls = 0
        var onCached: suspend () -> List<AgentV2ThreadListItem>? = { null }
        var deleteCalls = 0
        var onList: suspend (String?) -> AgentV2ThreadListResponse = {
            AgentV2ThreadListResponse(emptyList())
        }
        var onUpdate: suspend (String, AgentV2ThreadUpdate) -> AgentV2ThreadResponse = { id, _ ->
            AgentV2ThreadResponse(AgentV2ThreadSummary(id, 1))
        }
        var onDelete: suspend (String) -> AgentV2ThreadDeleteResponse = {
            AgentV2ThreadDeleteResponse(it, false)
        }

        override suspend fun list(cursor: String?): AgentV2ThreadListResponse {
            listCalls.add(cursor)
            return onList(cursor)
        }

        override suspend fun getCached(): List<AgentV2ThreadListItem>? {
            cachedCalls += 1
            return onCached()
        }

        override suspend fun update(id: String, update: AgentV2ThreadUpdate) = onUpdate(id, update)

        override suspend fun delete(id: String): AgentV2ThreadDeleteResponse {
            deleteCalls += 1
            return onDelete(id)
        }
    }

    companion object {
        // The chats' cached histories observe wallet events through `WalletCore`, which reads the wallet storage
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
    }
}
