package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import java.text.DateFormat
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentCachedHistories
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSession
import org.mytonwallet.app_air.uiagent.viewControllers.agent.findAgentSupportThread
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.utils.WDateFormatter
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

internal interface AgentThreadListClient {
    suspend fun list(cursor: String?): AgentV2ThreadListResponse
    suspend fun getCached(): List<AgentV2ThreadListItem>?
    suspend fun update(id: String, update: AgentV2ThreadUpdate): AgentV2ThreadResponse
    suspend fun delete(id: String): AgentV2ThreadDeleteResponse
}

internal class LiveAgentThreadListClient : AgentThreadListClient {
    private val client = LiveAgentV2Client()

    override suspend fun list(cursor: String?) =
        client.listThreads(cursor = cursor, limit = PAGE_SIZE)

    override suspend fun getCached() = client.getCachedThreads()

    override suspend fun update(id: String, update: AgentV2ThreadUpdate) =
        client.updateThread(id, update)

    override suspend fun delete(id: String) = client.deleteThread(id)

    private companion object {
        const val PAGE_SIZE = 30
    }
}

/** How the list should show a change of its rows */
internal enum class AgentThreadListChange {
    // Rows came or moved with the data itself, such as a chat moving up with a new message
    DATA,

    // The user pinned, unpinned or deleted a chat: the rows make way on a spring
    USER
}

internal class AgentThreadListModel(
    private val scope: CoroutineScope,
    private val client: AgentThreadListClient = LiveAgentThreadListClient(),
    private val readState: AgentThreadReadState = AgentThreadReadState.shared,
    private val activityTracker: AgentThreadActivityTracker = AgentThreadActivityTracker(),
    private val cachedHistories: AgentCachedHistories = AgentSession.cachedHistories,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val activityHoldMillis: Long = ACTIVITY_HOLD_MS
) {
    var items: List<AgentV2ThreadListItem> = emptyList()
        private set
    var nextCursor: String? = null
        private set
    var isLoading = false
        private set

    /**
     * The first page of chats, or the device's copy of it, has loaded, or the page failed to: until then the list has
     * nothing to say about them
     */
    var hasLoaded = false
        private set

    /** The latest load of the first page failed while the list had no chats to show */
    var hasLoadFailed = false
        private set

    /** The next page failed to load: the list ends with a line that loads it again */
    var hasPageLoadFailed = false
        private set
    var onChange: ((AgentThreadListChange) -> Unit)? = null
    var onError: ((Throwable) -> Unit)? = null

    /** The threads whose answering status changed */
    var onActivityChange: ((Set<String>) -> Unit)? = null

    /** The chats are the device's copy of the first page, shown until the page itself loads */
    var isCacheShown = false
        private set
    private var loadJob: Job? = null
    private var loadChanges: MutableMap<String, AgentV2ThreadSummary?>? = null

    // Contact Support waiting for the server's chats, to open the one support has or a new one
    private var supportRequest: ((AgentV2ThreadSummary?) -> Unit)? = null
    private val mutations = mutableMapOf<String, Job>()

    /**
     * Threads whose answer completed while their row's preview still is the question: the row keeps the answer's
     * last status until a list load brings the answer's preview, so the question doesn't show again in between. A
     * load brings it when it started after the completion, or when it has the thread past the revision its run
     * started at.
     */
    private class HeldActivity(val text: String, val runRevision: Int?) {
        lateinit var expiry: Job

        // The latest load started after the answer completed
        var releasingLoad: Job? = null
    }

    private val heldActivities = mutableMapOf<String, HeldActivity>()

    // The thread's revision when its latest run started, with the question; the answer moves it further
    private val runRevisions = mutableMapOf<String, Int>()

    fun reset() {
        supportRequest = null
        invalidateLoad()
        mutations.values.toList().forEach { it.cancel() }
        mutations.clear()
        items = emptyList()
        nextCursor = null
        isCacheShown = false
        hasLoaded = false
        hasLoadFailed = false
        hasPageLoadFailed = false
        removeAllActivities()
        onChange?.invoke(AgentThreadListChange.DATA)
    }

    /** Reloads at least as many chats as the list shows, following cursors */
    fun refresh() {
        load(cursor = null, minimumCount = if (isCacheShown) 0 else items.size)
    }

    /**
     * Hands [open] the most recently active chat that support has, or null for a new chat, from the server's chats. The
     * request waits for them behind the device's copy and is dropped when they fail to load.
     */
    fun requestSupportThread(open: (AgentV2ThreadSummary?) -> Unit) {
        if (hasLoaded && !isCacheShown && !hasLoadFailed && !isLoading) {
            open(findAgentSupportThread(items))
            return
        }
        supportRequest = open
        refresh()
    }

    fun loadMore() {
        if (isLoading) return
        nextCursor?.let { load(cursor = it, minimumCount = 0) }
    }

    /** Moves the thread at once, and back if the server refuses */
    fun setPinned(thread: AgentV2ThreadSummary, isPinned: Boolean) {
        if (mutations.containsKey(thread.id)) return
        replaceLoadedThread(thread.copy(isPinned = isPinned), AgentThreadListChange.USER)
        mutate(
            thread.id,
            onFailure = {
                val current = items.firstOrNull { it.thread.id == thread.id }?.thread
                if (current != null && current.isPinned == isPinned) {
                    replaceLoadedThread(
                        current.copy(isPinned = thread.isPinned),
                        AgentThreadListChange.USER
                    )
                }
            }
        ) {
            val response = client.update(thread.id, AgentV2ThreadUpdate(isPinned = isPinned))
            currentCoroutineContext().ensureActive()
            replaceLoadedThread(response.thread, AgentThreadListChange.USER)
        }
    }

    fun rename(thread: AgentV2ThreadSummary, title: String) {
        mutate(thread.id) {
            val update = AgentV2ThreadUpdate(title = title.trim().takeIf { it.isNotEmpty() })
            val response = client.update(thread.id, update)
            currentCoroutineContext().ensureActive()
            replaceLoadedThread(response.thread, AgentThreadListChange.DATA)
        }
    }

    /** Deletes the thread unless a change of it is under way, and returns whether it does */
    fun delete(thread: AgentV2ThreadSummary, onFailure: (() -> Unit)? = null): Boolean =
        mutate(thread.id, onFailure) {
            val loadedModel = AgentSession.findLoadedModel(thread.id)
            loadedModel?.holdQueueForDeletion()
            try {
                val response = client.delete(thread.id)
                currentCoroutineContext().ensureActive()
                AgentSession.dropDeletedChat(response.threadId)
                removeLoadedThread(response.threadId)
            } catch (error: CancellationException) {
                AgentSession.dropDeletedChat(thread.id)
                throw error
            } catch (error: Throwable) {
                loadedModel?.resumeQueueAfterFailedDeletion()
                throw error
            }
        }

    /** Drops a thread deleted elsewhere, such as from its chat. The list's own deletions remove their rows. */
    fun removeDeletedThread(threadId: String) {
        if (mutations.containsKey(threadId)) return
        removeLoadedThread(threadId)
    }

    private fun removeLoadedThread(threadId: String) {
        loadChanges?.set(threadId, null)
        val hasBeenLoaded = items.any { it.thread.id == threadId }
        items = items.filterNot { it.thread.id == threadId }
        readState.remove(threadId)
        cachedHistories.remove(threadId)
        val changed = removeActivity(threadId)
        if (hasBeenLoaded) onChange?.invoke(AgentThreadListChange.USER)
        notifyActivityChange(changed)
    }

    fun applyThreadChange(thread: AgentV2ThreadSummary) {
        if (items.none { it.thread.id == thread.id }) {
            refresh()
            return
        }
        replaceLoadedThread(thread, AgentThreadListChange.DATA)
    }

    // Answering status

    /** What the Agent is doing in the thread while it answers, or null when it is not answering there */
    fun getActivityText(threadId: String): String? =
        activityTracker.getText(threadId) ?: heldActivities[threadId]?.text

    /** Whether the thread holds an answer the user hasn't seen */
    fun isUnread(thread: AgentV2ThreadSummary): Boolean = readState.isUnread(thread)

    fun handleUpdate(update: AgentV2Update) {
        when (update) {
            is AgentV2Update.MessageCompleted -> holdActivity(update.threadId)

            is AgentV2Update.RunStarted -> {
                heldActivities.remove(update.threadId)?.expiry?.cancel()
                runRevisions[update.threadId] = update.threadRevision
            }

            else -> Unit
        }
        notifyActivityChange(activityTracker.handle(update, nowMs()))
        if (update is AgentV2Update.MessageCompleted &&
            update.finishReason != "delivered_to_support"
        ) {
            readState.onAnswerCompleted(update.threadId)
        }
    }

    /**
     * Loaded chats know whether they are answering, so they show runs that began before the list saw their updates
     * and end runs whose last update the list missed
     */
    fun syncActivities(chats: List<AgentThreadActivityTracker.LoadedChat>) {
        notifyActivityChange(activityTracker.sync(chats, nowMs()))
    }

    private fun holdActivity(threadId: String) {
        val text = activityTracker.getText(threadId) ?: return
        heldActivities.remove(threadId)?.expiry?.cancel()
        val hold = HeldActivity(text, runRevisions[threadId])
        hold.expiry = scope.launch(start = CoroutineStart.LAZY) {
            delay(activityHoldMillis)
            if (heldActivities[threadId] === hold) {
                notifyActivityChange(takeHeldActivities(setOf(threadId)))
            }
        }
        heldActivities[threadId] = hold
        hold.expiry.start()
    }

    /** Ends the held statuses of the threads, returning those whose status changed */
    private fun takeHeldActivities(threadIds: Set<String>): Set<String> {
        val released = threadIds.filterTo(mutableSetOf()) { threadId ->
            heldActivities.remove(threadId)?.also { it.expiry.cancel() } != null
        }
        return released.filterTo(mutableSetOf()) { activityTracker.getText(it) == null }
    }

    private fun removeActivity(threadId: String): Set<String> {
        runRevisions.remove(threadId)
        val hasBeenHeld = heldActivities.remove(threadId)?.also { it.expiry.cancel() } != null
        return activityTracker.remove(threadId) + if (hasBeenHeld) setOf(threadId) else emptySet()
    }

    private fun removeAllActivities() {
        runRevisions.clear()
        heldActivities.values.forEach { it.expiry.cancel() }
        val held = heldActivities.keys.toSet()
        heldActivities.clear()
        notifyActivityChange(activityTracker.removeAll() + held)
    }

    private fun notifyActivityChange(threadIds: Set<String>) {
        if (threadIds.isNotEmpty()) onActivityChange?.invoke(threadIds)
    }

    // Loading and mutations

    private fun replaceLoadedThread(thread: AgentV2ThreadSummary, change: AgentThreadListChange) {
        loadChanges?.set(thread.id, thread)
        items = sortAgentThreads(
            items.map { if (it.thread.id == thread.id) it.copy(thread = thread) else it }
        )
        AgentSession.findLoadedModel(thread.id)
            ?.takeIf { it.isChatWithSupport || thread.support != it.currentThread.support }
            ?.refreshThreadIfNeeded(thread)
        onChange?.invoke(change)
    }

    private fun mutate(
        id: String,
        onFailure: (() -> Unit)? = null,
        operation: suspend () -> Unit
    ): Boolean {
        if (mutations.containsKey(id)) return false
        val operationJob = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            try {
                operation()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                onFailure?.invoke()
                onError?.invoke(error)
            } finally {
                if (mutations[id] === owner) mutations.remove(id)
            }
        }
        mutations[id] = operationJob
        operationJob.start()
        return true
    }

    private fun invalidateLoad() {
        loadJob?.cancel()
        loadJob = null
        loadChanges = null
        isLoading = false
    }

    private fun load(cursor: String?, minimumCount: Int) {
        invalidateLoad()
        isLoading = true
        if (cursor != null) hasPageLoadFailed = false
        onChange?.invoke(AgentThreadListChange.DATA)
        val changes = mutableMapOf<String, AgentV2ThreadSummary?>()
        loadChanges = changes
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            // The device's copy of the first page goes with this load
            val cacheJob = if (cursor == null && items.isEmpty()) {
                launch { showCachedThreads() }
            } else {
                null
            }
            var released = emptySet<String>()
            var hasLoadedFirstPage = false
            try {
                val merged = if (cursor == null) {
                    linkedMapOf<String, AgentV2ThreadListItem>()
                } else {
                    items.associateByTo(linkedMapOf()) { it.thread.id }
                }
                var pageCursor = cursor
                val requestedCursors = mutableSetOf<String>()
                do {
                    pageCursor?.let(requestedCursors::add)
                    // Any end of the first page's request makes the device's copy outdated
                    val response = try {
                        client.list(pageCursor)
                    } finally {
                        cacheJob?.cancel()
                    }
                    currentCoroutineContext().ensureActive()
                    if (loadJob !== owner) return@launch
                    response.threads.forEach { item ->
                        val id = item.thread.id
                        if (!changes.containsKey(id)) {
                            merged[id] = item
                        } else {
                            changes[id]?.let { merged[id] = item.copy(thread = it) }
                        }
                    }
                    pageCursor = response.nextCursor?.takeUnless { it in requestedCursors }
                } while (merged.size < minimumCount && pageCursor != null)
                items = sortAgentThreads(merged.values.toList())
                hasLoadedFirstPage = cursor == null
                nextCursor = pageCursor
                isCacheShown = false
                hasLoadFailed = false
                hasPageLoadFailed = false
                readState.observe(items.map { it.thread }, activityTracker.answeringThreadIds)
                items.forEach { item ->
                    AgentSession.findLoadedModel(item.thread.id)
                        ?.takeIf {
                            it.isChatWithSupport ||
                                item.thread.support != it.currentThread.support
                        }
                        ?.refreshThreadIfNeeded(item.thread)
                }
                if (cursor == null) cachedHistories.prefetch(items.map { it.thread })
                // The rows now have the previews of the answers that completed before this load started, and of
                // those the load has past their run's revision. Their statuses end in the change that brings the
                // previews, which also moves the rows.
                val revisions = items.associate { it.thread.id to it.thread.revision }
                val answered = heldActivities.filter { (threadId, hold) ->
                    val runRevision = hold.runRevision
                    hold.releasingLoad === owner ||
                        (runRevision != null && (revisions[threadId] ?: 0) > runRevision)
                }
                released = takeHeldActivities(answered.keys)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // A failed refresh keeps the chats shown without a word
                if (loadJob === owner) {
                    if (cursor == null) {
                        hasLoadFailed = items.isEmpty()
                    } else {
                        hasPageLoadFailed = true
                    }
                }
            } finally {
                if (loadJob === owner) {
                    loadJob = null
                    loadChanges = null
                    isLoading = false
                    hasLoaded = true
                    onChange?.invoke(AgentThreadListChange.DATA)
                    notifyActivityChange(released)
                    // A load the next one cancelled leaves the request to it
                    if (cursor == null && owner.isActive) settleSupportRequest(hasLoadedFirstPage)
                }
            }
        }
        loadJob = request
        heldActivities.values.forEach { it.releasingLoad = request }
        request.start()
    }

    private fun settleSupportRequest(hasLoadedFirstPage: Boolean) {
        val open = supportRequest ?: return
        supportRequest = null
        if (hasLoadedFirstPage) open(findAgentSupportThread(items))
    }

    /**
     * Shows the device's copy of the first page while the page loads. Its chats change no read state or answering
     * status, and it has no cursor to load further pages with.
     */
    private suspend fun showCachedThreads() {
        val cached = try {
            client.getCached()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
        }
        currentCoroutineContext().ensureActive()
        // The copy takes the changes made while it was read, as the page does
        val changes = loadChanges.orEmpty()
        val shown = cached.orEmpty().mapNotNull { item ->
            if (changes.containsKey(item.thread.id)) {
                changes[item.thread.id]?.let { item.copy(thread = it) }
            } else {
                item
            }
        }
        if (shown.isEmpty()) return
        items = sortAgentThreads(shown)
        nextCursor = null
        isCacheShown = true
        hasLoaded = true
        hasLoadFailed = false
        onChange?.invoke(AgentThreadListChange.DATA)
        cachedHistories.prefetch(items.map { it.thread })
    }

    private companion object {
        const val ACTIVITY_HOLD_MS = 5_000L
    }
}

internal fun agentThreadActivityDate(thread: AgentV2ThreadSummary): Date =
    (thread.lastActivityAt ?: thread.updatedAt ?: thread.createdAt)
        ?.let(::parseAgentV2Timestamp) ?: Date(0)

/**
 * The picture of a thread's latest message, which its row shows before the preview, as Telegram's chat list does. Only
 * a news post has one, and it is a discussion's latest message while it is the thread's only one.
 */
internal fun agentThreadPreviewImageUrl(thread: AgentV2ThreadSummary): String? =
    thread.news?.imageUrl?.takeIf { it.isNotBlank() && thread.messageCount <= 1 }

internal fun sortAgentThreads(items: List<AgentV2ThreadListItem>): List<AgentV2ThreadListItem> =
    items.sortedWith(
        compareByDescending<AgentV2ThreadListItem> { it.thread.isPinned == true }
            .thenByDescending { agentThreadActivityDate(it.thread) }
            .thenBy { it.thread.id }
    )

internal data class AgentThreadListSection(val day: Long?, val items: List<AgentV2ThreadListItem>)

internal fun groupAgentThreads(
    items: List<AgentV2ThreadListItem>,
    timeZone: TimeZone = TimeZone.getDefault()
): List<AgentThreadListSection> = sortAgentThreads(items).groupBy {
    if (it.thread.isPinned == true) {
        null
    } else {
        AgentThreadDateFormatting.startOfDay(agentThreadActivityDate(it.thread), timeZone)
    }
}.map { AgentThreadListSection(it.key, it.value) }

internal object AgentThreadDateFormatting {
    enum class DayGroup { TODAY, YESTERDAY, WEEKDAY, DATE }

    private const val DAYS_IN_WEEK = 7

    // A month abbreviated with a single dot at its end, as "июл." and "Okt.", but not "ต.ค.", whose dot Telegram's
    // dates leave out
    private val ABBREVIATION_DOT = Regex("^([^.]+)\\.$")

    // Russian abbreviates every month to three letters, as Telegram does: "7 ноя", "4 сен"
    private val RUSSIAN_SHORT_MONTHS = arrayOf(
        "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"
    )

    // A word after the year, as Russian's "г.", which Telegram's dates leave out
    private val YEAR_SUFFIX = Regex("(?<=y)\\s*'[^']*'\\.?$")

    fun startOfDay(date: Date, timeZone: TimeZone): Long = Calendar.getInstance(timeZone).apply {
        time = date
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    fun dayGroup(date: Date, now: Date, timeZone: TimeZone = TimeZone.getDefault()): DayGroup {
        val daysAgo = countDaysAgo(date, now, timeZone)
        return when {
            daysAgo == 0 -> DayGroup.TODAY
            daysAgo == 1 -> DayGroup.YESTERDAY
            daysAgo < DAYS_IN_WEEK -> DayGroup.WEEKDAY
            else -> DayGroup.DATE
        }
    }

    /**
     * A day header: Today and Yesterday, then the weekday within the week, then the date, with the year for another
     * year. It starts with a capital, as Today and Yesterday do, though the weekday's name may be lowercase.
     */
    fun formatHeaderText(
        date: Date,
        now: Date,
        today: String,
        yesterday: String,
        locale: Locale = Locale.getDefault(),
        timeZone: TimeZone = TimeZone.getDefault()
    ): String {
        val pattern = when (dayGroup(date, now, timeZone)) {
            DayGroup.TODAY -> return today

            DayGroup.YESTERDAY -> return yesterday

            DayGroup.WEEKDAY -> "EEEE"

            DayGroup.DATE -> getLocalizedPattern(
                locale,
                if (isSameYear(date, now, timeZone)) "MMMMd" else "yMMMMd"
            )
        }
        return format(date, pattern, locale, timeZone).replaceFirstChar { it.titlecase(locale) }
    }

    /**
     * A day as the date capsules of a chat and of the News feed name it: Today, Yesterday, then the date, with the
     * year for another year, as "7 ноября" or "7 ноября 2025". Persian dates take the Persian calendar, as the app's
     * other dates do.
     */
    fun formatDayText(
        date: Date,
        now: Date,
        today: String,
        yesterday: String,
        langCode: String,
        timeZone: TimeZone = TimeZone.getDefault()
    ): String {
        val group = dayGroup(date, now, timeZone)
        if (group == DayGroup.TODAY) return today
        if (group == DayGroup.YESTERDAY) return yesterday
        return formatDayText(date, now, langCode, timeZone)
    }

    /**
     * The day and month of [date], with the year when it isn't [now]'s, as "November 10" or "7 ноября 2025", without
     * Today and Yesterday. Persian dates take the Persian calendar, as the app's other dates do.
     */
    fun formatDayText(
        date: Date,
        now: Date,
        langCode: String,
        timeZone: TimeZone = TimeZone.getDefault()
    ): String {
        val locale = Locale.forLanguageTag(langCode)
        val skeleton = if (isSameYear(date, now, timeZone)) "MMMMd" else "yMMMMd"
        val pattern = removeYearSuffix(getLocalizedPattern(locale, skeleton))
        val text = if (langCode == WLanguage.PERSIAN.langCode) {
            WDateFormatter.of(pattern, langCode).format(date)
        } else {
            format(date, pattern, locale, timeZone)
        }
        return text.replaceFirstChar { it.titlecase(locale) }
    }

    /**
     * The time label of a list row, in Telegram's chat list format. Rows under day headers show the time. Rows that
     * stay at the top regardless of their date (pinned chats and News) show the time for today, the short weekday
     * within the last week, then the day and the short month this year, as "7 ноя", and the numeric date with the
     * year before, as "07.11.25".
     */
    fun formatRowTimestamp(
        date: Date,
        now: Date,
        shouldShowDateWhenNotToday: Boolean,
        is24HourFormat: Boolean,
        locale: Locale = Locale.getDefault(),
        timeZone: TimeZone = TimeZone.getDefault()
    ): String {
        val time = format(date, if (is24HourFormat) "HH:mm" else "h:mm\u00A0a", Locale.US, timeZone)
        if (!shouldShowDateWhenNotToday) return time
        val daysAgo = countDaysAgo(date, now, timeZone)
        return when {
            daysAgo == 0 -> time
            daysAgo < DAYS_IN_WEEK -> format(date, "EEE", locale, timeZone)
            isSameYear(date, now, timeZone) -> formatShortDay(date, locale, timeZone)
            else -> format(date, getNumericDatePattern(locale), locale, timeZone)
        }
    }

    /** Leaves out a word after the year, as Russian's "г.", from a platform date pattern */
    fun removeYearSuffix(pattern: String): String = pattern.replace(YEAR_SUFFIX, "")

    /** The short date and time of a message or post, used outside the list */
    fun formatDate(
        date: Date,
        now: Date,
        isHeader: Boolean,
        locale: Locale = Locale.getDefault(),
        timeZone: TimeZone = TimeZone.getDefault()
    ): String {
        val group = dayGroup(date, now, timeZone)
        val formatter = when {
            !isHeader && group == DayGroup.TODAY -> DateFormat.getTimeInstance(
                DateFormat.SHORT,
                locale
            )

            group != DayGroup.DATE -> SimpleDateFormat(if (isHeader) "EEEE" else "EEE", locale)

            else -> DateFormat.getDateInstance(
                if (isHeader) DateFormat.LONG else DateFormat.SHORT,
                locale
            )
        }
        formatter.timeZone = timeZone
        return formatter.format(date)
    }

    // The day and the short month in the locale's order, without the abbreviation's dot
    private fun formatShortDay(date: Date, locale: Locale, timeZone: TimeZone): String =
        makeShortMonthFormat(getLocalizedPattern(locale, "MMMd"), locale)
            .apply { this.timeZone = timeZone }
            .format(date)

    /**
     * A format of `pattern` whose short months go without their dot, as Telegram writes dates: "Nov 7", "7 ноя".
     * Russian months are cut to three letters, where the platform writes "нояб." and "сент.".
     */
    fun makeShortMonthFormat(pattern: String, locale: Locale): SimpleDateFormat {
        val symbols = DateFormatSymbols.getInstance(locale)
        symbols.shortMonths = if (locale.language == "ru") {
            RUSSIAN_SHORT_MONTHS + symbols.shortMonths.drop(RUSSIAN_SHORT_MONTHS.size)
        } else {
            symbols.shortMonths.map { it.replace(ABBREVIATION_DOT, "$1") }.toTypedArray()
        }
        // The locale gives the calendar and the digits, which a format made from the symbols alone takes from the device
        return SimpleDateFormat(pattern, locale).apply { dateFormatSymbols = symbols }
    }

    // The day, month and year in the locale's order and with its separator, as `dd.MM.yy` or `MM/dd/yy`
    private fun getNumericDatePattern(locale: Locale): String {
        val shortPattern = getShortDatePattern(locale)
        val separator = listOf('.', '/', '-').firstOrNull { it in shortPattern } ?: '.'
        val dayMonth = if (isMonthFirst(shortPattern)) "MM${separator}dd" else "dd${separator}MM"
        return "$dayMonth${separator}yy"
    }

    private fun getLocalizedPattern(locale: Locale, skeleton: String): String =
        android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton)
            ?: buildFallbackPattern(locale, skeleton)

    // Where the platform gives no pattern, as in unit tests: the day and the month in the locale's numeric order
    private fun buildFallbackPattern(locale: Locale, skeleton: String): String {
        val month = skeleton.filter { it == 'M' }
        val hasYear = skeleton.startsWith("y")
        return if (isMonthFirst(getShortDatePattern(locale))) {
            if (hasYear) "$month d, y" else "$month d"
        } else {
            if (hasYear) "d $month y" else "d $month"
        }
    }

    private fun getShortDatePattern(locale: Locale): String {
        val shortFormat = DateFormat.getDateInstance(DateFormat.SHORT, locale)
        return (shortFormat as? SimpleDateFormat)?.toPattern().orEmpty()
    }

    private fun isMonthFirst(shortPattern: String): Boolean {
        val monthIndex = shortPattern.indexOf('M')
        return monthIndex >= 0 && monthIndex < shortPattern.indexOf('d')
    }

    private fun format(date: Date, pattern: String, locale: Locale, timeZone: TimeZone): String =
        SimpleDateFormat(pattern, locale).apply { this.timeZone = timeZone }.format(date)

    // Whole calendar days from the date to now, at most a week; zero for today and for later dates
    private fun countDaysAgo(date: Date, now: Date, timeZone: TimeZone): Int {
        val day = Calendar.getInstance(timeZone).apply { timeInMillis = startOfDay(date, timeZone) }
        val today = startOfDay(now, timeZone)
        var count = 0
        while (day.timeInMillis < today && count < DAYS_IN_WEEK) {
            day.add(Calendar.DAY_OF_YEAR, 1)
            count++
        }
        return count
    }

    private fun isSameYear(date: Date, now: Date, timeZone: TimeZone): Boolean {
        val calendar = Calendar.getInstance(timeZone)
        calendar.time = date
        val year = calendar.get(Calendar.YEAR)
        calendar.time = now
        return year == calendar.get(Calendar.YEAR)
    }
}
