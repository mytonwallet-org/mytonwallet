package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

class AgentThreadListModelTest {
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
    fun failedRefreshAndLoadMoreKeepLoadedRowsAndStopLoadingSilently() = runBlocking {
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
    fun topRowsShowTheTimeForTheLastTwelveHoursOfYesterdayThenYesterday() {
        val now = date("2026-10-28T00:57:00Z")
        val midnight = date("2026-10-28T00:00:00Z")

        assertEquals("23:57", formatTopRowTime("2026-10-27T23:57:00Z", now))
        assertEquals("12:57", formatTopRowTime("2026-10-27T12:57:01Z", now))
        assertEquals("Yesterday", formatTopRowTime("2026-10-27T12:57:00Z", now))
        assertEquals("Yesterday", formatTopRowTime("2026-10-27T00:00:00Z", now))

        assertEquals("00:00", formatTopRowTime("2026-10-28T00:00:00Z", now))
        assertEquals("23:59", formatTopRowTime("2026-10-27T23:59:59Z", midnight))
        assertEquals("12:00", formatTopRowTime("2026-10-27T12:00:01Z", midnight))
        assertEquals("Yesterday", formatTopRowTime("2026-10-27T12:00:00Z", midnight))

        assertEquals("Thu", formatTopRowTime("2026-10-22T23:59:00Z", now))
        assertEquals("10/21", formatTopRowTime("2026-10-21T23:59:00Z", now))

        val newYear = date("2027-01-01T00:30:00Z")
        assertEquals("23:00", formatTopRowTime("2026-12-31T23:00:00Z", newYear))
        assertEquals("Yesterday", formatTopRowTime("2026-12-31T08:00:00Z", newYear))
        assertEquals("12/30/26", formatTopRowTime("2026-12-30T23:00:00Z", newYear))

        assertEquals(
            "12:57",
            AgentThreadDateFormatting.formatRowTimestamp(
                date("2026-10-27T12:57:00Z"),
                now,
                shouldShowDateWhenNotToday = false,
                is24HourFormat = true,
                yesterday = "Yesterday",
                locale = Locale.US,
                timeZone = TimeZone.getTimeZone("UTC")
            )
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

    private fun item(
        id: String,
        timestamp: String = "2026-01-01T00:00:00Z",
        isPinned: Boolean = false
    ) = AgentV2ThreadListItem(
        AgentV2ThreadSummary(id, revision = 1, lastActivityAt = timestamp, isPinned = isPinned),
        preview = "Answer in $id"
    )

    private fun date(timestamp: String): Date = requireNotNull(parseAgentV2Timestamp(timestamp))

    private fun formatTopRowTime(timestamp: String, now: Date): String =
        AgentThreadDateFormatting.formatRowTimestamp(
            date(timestamp),
            now,
            shouldShowDateWhenNotToday = true,
            is24HourFormat = true,
            yesterday = "Yesterday",
            locale = Locale.US,
            timeZone = TimeZone.getTimeZone("UTC")
        )

    private fun CoroutineScope.makeModel(
        client: FakeClient,
        readState: AgentThreadReadState = AgentThreadReadState(read = { null }, write = {})
    ) = AgentThreadListModel(
        CoroutineScope(coroutineContext + Dispatchers.Unconfined),
        client,
        readState = readState,
        activityTracker = AgentThreadActivityTracker(
            analyzingText = { "Analyzing" },
            writingText = { "Writing" },
            stepText = { it.code }
        ),
        activityHoldMillis = Long.MAX_VALUE
    )

    private class FakeClient : AgentThreadListClient {
        val listCalls = mutableListOf<String?>()
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

        override suspend fun update(id: String, update: AgentV2ThreadUpdate) = onUpdate(id, update)

        override suspend fun delete(id: String): AgentV2ThreadDeleteResponse {
            deleteCalls += 1
            return onDelete(id)
        }
    }
}
