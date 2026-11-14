package org.mytonwallet.app_air.uiagent.viewControllers.news

import java.util.TimeZone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.callAgentV2Mutation
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationState

private const val AGENT_NEWS_UNREAD_COUNT_MAX = 10
private const val AGENT_NEWS_PREFETCH_WINDOW_MS = 48 * 60 * 60 * 1000L

/** The digest time and time zone a page of the feed is requested with, which the page's digests follow */
internal data class AgentNewsDigestSchedule(val hour: Int, val minute: Int, val timeZone: String) {
    companion object {
        /** The device's: the time the digest settings keep, in the phone's time zone */
        fun current() = AgentNewsDigestSchedule(
            AgentNewsNotificationSettings.shared.digestHour,
            AgentNewsNotificationSettings.shared.digestMinute,
            TimeZone.getDefault().id
        )
    }
}

/** What the open feed follows of the news settings: a change of it selects the view or reloads the feed */
internal fun makeAgentNewsFeedSettingsKey(
    view: AgentNewsFeedView,
    state: AgentNewsNotificationState
) = Triple(view, state.digestHour, state.digestMinute)

internal interface AgentNewsFeedClient {
    suspend fun getNewsFeed(
        lang: String,
        cursor: String?,
        schedule: AgentNewsDigestSchedule,
        view: AgentNewsFeedView = AgentNewsFeedView.All
    ): AgentV2NewsFeedPage
}

internal class LiveAgentNewsFeedClient(
    private val call: suspend (ApiMethod.AgentV2.GetNewsFeed) -> AgentV2NewsFeedPage = {
        callAgentV2Mutation(it)
    }
) : AgentNewsFeedClient {
    override suspend fun getNewsFeed(
        lang: String,
        cursor: String?,
        schedule: AgentNewsDigestSchedule,
        view: AgentNewsFeedView
    ) = call(
        ApiMethod.AgentV2.GetNewsFeed(
            lang,
            cursor,
            schedule.hour,
            schedule.minute,
            schedule.timeZone,
            view.value.takeIf { view == AgentNewsFeedView.Digests }
        )
    )
}

internal sealed interface AgentNewsFeedEntry {
    val deliveredAt: String

    data class News(val item: AgentV2NewsFeedItem) : AgentNewsFeedEntry {
        override val deliveredAt get() = item.deliveredAt
    }

    data class Digest(val digest: AgentV2NewsFeedDigest) : AgentNewsFeedEntry {
        override val deliveredAt get() = digest.deliveredAt
    }
}

internal class AgentNewsReadState(
    private val read: () -> String? = WGlobalStorage::getAgentNewsReadThrough,
    private val write: (String) -> Unit = WGlobalStorage::setAgentNewsReadThrough,
    private val readDigests: () -> String? = WGlobalStorage::getAgentNewsDigestsReadThrough,
    private val writeDigests: (String) -> Unit = WGlobalStorage::setAgentNewsDigestsReadThrough
) {
    val readThrough: String? get() = read()

    fun initializeIfNeeded(items: List<AgentV2NewsFeedItem>) {
        if (readThrough == null) markRead(items)
    }

    fun markRead(items: List<AgentV2NewsFeedItem>) {
        val newest = items.maxByOrNull { agentNewsTimestamp(it.deliveredAt) } ?: return
        val previous = readThrough
        if (previous == null ||
            agentNewsTimestamp(newest.deliveredAt) > agentNewsTimestamp(previous)
        ) {
            write(newest.deliveredAt)
        }
    }

    fun unreadCount(items: List<AgentV2NewsFeedItem>): Int {
        val cutoff = readThrough?.let(::agentNewsTimestamp) ?: return 0
        return mergeAgentNewsItems(items).count { agentNewsTimestamp(it.deliveredAt) > cutoff }
    }

    /** The delivery time of the latest digest the feed has shown, in either view */
    val digestsReadThrough: String? get() = readDigests()

    fun initializeDigestsIfNeeded(digests: List<AgentV2NewsFeedDigest>) {
        if (digestsReadThrough == null) markDigestsRead(digests)
    }

    fun markDigestsRead(digests: List<AgentV2NewsFeedDigest>) {
        val newest = digests.maxByOrNull { agentNewsTimestamp(it.deliveredAt) } ?: return
        val previous = digestsReadThrough
        if (previous == null ||
            agentNewsTimestamp(newest.deliveredAt) > agentNewsTimestamp(previous)
        ) {
            writeDigests(newest.deliveredAt)
        }
    }

    fun unreadDigestCount(digests: List<AgentV2NewsFeedDigest>): Int {
        val cutoff = digestsReadThrough?.let(::agentNewsTimestamp) ?: return 0
        return digests.count { agentNewsTimestamp(it.deliveredAt) > cutoff }
    }
}

/** The News row counts up to ten unread posts; with more, or none, it shows no number, and the unread dot alone */
internal fun formatAgentNewsUnreadCount(count: Int): String? =
    count.takeIf { it in 1..AGENT_NEWS_UNREAD_COUNT_MAX }?.toString()

internal class AgentNewsPreviewModel(
    private val scope: CoroutineScope,
    private val client: AgentNewsFeedClient = LiveAgentNewsFeedClient(),
    private val readState: AgentNewsReadState = AgentNewsReadState(),
    private val language: () -> String = { LocaleController.activeLanguage.langCode },
    private val digestSchedule: () -> AgentNewsDigestSchedule = {
        AgentNewsDigestSchedule.current()
    },
    private val view: () -> AgentNewsFeedView = { AgentNewsNotificationSettings.shared.newsView }
) {
    var items: List<AgentV2NewsFeedItem> = emptyList()
        private set

    /** The language [items] were loaded in */
    var itemsLanguage: String? = null
        private set

    /** The digests of the page [items] came on, and the schedule it was requested with, which they follow */
    private var digests: List<AgentV2NewsFeedDigest> = emptyList()
    private var digestsSchedule: AgentNewsDigestSchedule? = null

    /** The loaded page's digests while the digest time and time zone are still those they follow */
    val currentDigests: List<AgentV2NewsFeedDigest>
        get() = digests.takeIf { digestsSchedule == digestSchedule() }.orEmpty()
    val latestItem: AgentV2NewsFeedItem? get() = items.lastOrNull()

    /** The digests on the latest first page of the feed's view */
    private var viewDigests: List<AgentV2NewsFeedDigest> = emptyList()

    /** The feed's view, which the News row shows the latest of */
    val newsView: AgentNewsFeedView get() = view()
    val latestDigest: AgentV2NewsFeedDigest?
        get() = viewDigests.maxByOrNull { agentNewsTimestamp(it.deliveredAt) }
    val unreadCount: Int
        get() = if (newsView == AgentNewsFeedView.Digests) {
            readState.unreadDigestCount(viewDigests)
        } else {
            readState.unreadCount(items)
        }
    var onChange: (() -> Unit)? = null

    private var loadJob: Job? = null

    fun refresh() {
        loadJob?.cancel()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            try {
                val requestLanguage = language()
                val requestSchedule = digestSchedule()
                val requestView = view()
                val page = client.getNewsFeed(requestLanguage, null, requestSchedule, requestView)
                currentCoroutineContext().ensureActive()
                if (loadJob !== owner) return@launch
                if (requestView == AgentNewsFeedView.All) {
                    items = mergeAgentNewsItems(page.items)
                    itemsLanguage = requestLanguage
                    digests = page.digests.orEmpty()
                    digestsSchedule = requestSchedule
                    readState.initializeIfNeeded(items)
                }
                viewDigests = page.digests.orEmpty()
                readState.initializeDigestsIfNeeded(viewDigests)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Keep the latest successful preview when the refresh fails.
            } finally {
                if (loadJob === owner) {
                    loadJob = null
                    onChange?.invoke()
                }
            }
        }
        loadJob = request
        request.start()
    }
}

internal class AgentNewsFeedModel(
    scope: CoroutineScope,
    client: AgentNewsFeedClient = LiveAgentNewsFeedClient(),
    readState: AgentNewsReadState = AgentNewsReadState(),
    language: () -> String = { LocaleController.activeLanguage.langCode },
    val requestedDigestId: String? = null,
    digestSchedule: () -> AgentNewsDigestSchedule = { AgentNewsDigestSchedule.current() },
    initialView: AgentNewsFeedView = AgentNewsFeedView.All
) {
    var view = initialView
        private set
    private val feeds = AgentNewsFeedView.entries.associateWith { view ->
        val model = AgentNewsFeedPageModel(
            scope,
            client,
            readState,
            language,
            requestedDigestId,
            digestSchedule,
            view
        )
        model.onChange = { if (view == this.view) onChange?.invoke() }
        model.onReset = { if (view == this.view) onReset?.invoke() }
        model
    }
    private val current get() = feeds.getValue(view)
    private val all get() = feeds.getValue(AgentNewsFeedView.All)

    // Digest headlines can open the full news cards the all view has already loaded
    val items get() = all.items
    val entries get() = current.entries
    val isSeekingRequestedDigest get() = current.isSeekingRequestedDigest
    val hasRequestedDigest get() = current.hasRequestedDigest
    val canLoadRequestedDigest get() = current.canLoadRequestedDigest
    val nextCursor get() = current.nextCursor
    val locale get() = current.locale
    val isLoading get() = current.isLoading
    val isLoadingMore get() = current.isLoadingMore
    val error get() = current.error
    val refreshError get() = current.refreshError
    val hasLoaded get() = current.hasLoaded
    val isEmpty get() = current.isEmpty
    val unreadEventId get() = all.unreadEventId.takeIf { view == AgentNewsFeedView.All }
    val unreadDigestId
        get() = feeds.getValue(AgentNewsFeedView.Digests).unreadDigestId
            .takeIf { view == AgentNewsFeedView.Digests }
    var onChange: (() -> Unit)? = null
    var onReset: (() -> Unit)? = null

    fun setView(view: AgentNewsFeedView, shouldDeferRefresh: Boolean = false) {
        if (this.view == view) return
        current.cancel()
        this.view = view
        onReset?.invoke()
        if (shouldDeferRefresh) onChange?.invoke() else refresh()
    }

    fun seed(
        pageItems: List<AgentV2NewsFeedItem>,
        pageDigests: List<AgentV2NewsFeedDigest> = emptyList()
    ) = all.seed(pageItems, pageDigests, shouldSkipRead = view != AgentNewsFeedView.All)

    fun refresh() {
        current.openCachedNews()
        current.refresh()
    }

    fun loadMore() = current.loadMore()

    fun stopSeekingRequestedDigest() = current.stopSeekingRequestedDigest()

    fun markDigestReached(id: String) = current.markDigestReached(id)

    fun cancel() = current.cancel()

    fun markDiscussion(eventId: Int, thread: AgentV2ThreadSummary) {
        feeds.values.forEach { it.markDiscussion(eventId, thread) }
    }

    fun markDiscussion(digestId: String, thread: AgentV2ThreadSummary) {
        feeds.values.forEach { it.markDiscussion(digestId, thread) }
    }

    fun removeDiscussion(threadId: String) {
        feeds.values.forEach { it.removeDiscussion(threadId) }
    }
}

private class AgentNewsFeedPageModel(
    private val scope: CoroutineScope,
    private val client: AgentNewsFeedClient,
    private val readState: AgentNewsReadState,
    private val language: () -> String,
    val requestedDigestId: String?,
    private val digestSchedule: () -> AgentNewsDigestSchedule,
    private val view: AgentNewsFeedView
) {
    var items: List<AgentV2NewsFeedItem> = emptyList()
        private set
    private var digests: List<AgentV2NewsFeedDigest> = emptyList()
    val entries: List<AgentNewsFeedEntry>
        get() = (items.map(AgentNewsFeedEntry::News) + digests.map(AgentNewsFeedEntry::Digest))
            .sortedBy { agentNewsTimestamp(it.deliveredAt) }

    /**
     * The feed was opened for [requestedDigestId] and has neither shown it nor given up on it, and the user hasn't
     * scrolled it since: older pages load one after another until the digest comes
     */
    var isSeekingRequestedDigest = requestedDigestId != null
        private set

    val hasRequestedDigest: Boolean
        get() = requestedDigestId != null && digests.any { it.id == requestedDigestId }

    /**
     * Older pages may still bring the requested digest: it hasn't come, an older page remains that hasn't been asked
     * for, and the loaded entries reach back no further than its window's end, which its id carries after the locale.
     * An id without a readable time can't be placed among the pages, so the digest counts as not found.
     */
    val canLoadRequestedDigest: Boolean
        get() {
            val id = requestedDigestId ?: return false
            val cursor = nextCursor ?: return false
            if (cursor in requestedCursors || hasRequestedDigest) return false
            val windowEnd = parseAgentV2Timestamp(id.substringAfter(':', ""))?.time ?: return false
            val oldest = entries.firstOrNull() ?: return true
            return agentNewsTimestamp(oldest.deliveredAt) >= windowEnd
        }

    var nextCursor: String? = null
        private set
    var locale: String? = null
        private set
    var isLoading = false
        private set
    var isLoadingMore = false
        private set
    var error: Throwable? = null
        private set

    var refreshError: Throwable? = null
        private set

    /** A first page has come: until then a feed without news is still loading them */
    var hasLoaded = false
        private set

    /** The feed has loaded without news or digests and shows no failure */
    val isEmpty: Boolean get() = hasLoaded && items.isEmpty() && digests.isEmpty() && error == null
    var unreadEventId: Int? = null
        private set

    /** The first digest delivered after those read as the Digests view first showed its digests */
    var unreadDigestId: String? = null
        private set
    var onChange: (() -> Unit)? = null
    var onReset: (() -> Unit)? = null

    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private var prefetchJob: Job? = null
    private var reachedDigestTimestamp: Long? = null
    private var hasReachedHistoryEnd = false
    private var hasOpened = false
    private var unreadCutoff: Long? = null
    private var feedLanguage: String? = null

    /** The schedule the loaded digests, and the pages they came on, were requested with */
    private var loadedSchedule: AgentNewsDigestSchedule? = null

    /**
     * The digests shown are another schedule's: they stay until the new schedule's first page replaces them, so the
     * cards and the pinned bar don't blink out and back while it loads
     */
    private var isDigestResetPending = false
    private val requestedCursors = mutableSetOf<String>()
    private val localDiscussions = mutableMapOf<Int, AgentV2NewsFeedItem.Discussion>()
    private val localDigestDiscussions = mutableMapOf<String, AgentV2NewsFeedItem.Discussion>()

    /**
     * Shows the first page the list's News row has loaded at once, as the feed's own first page would, while the
     * feed loads it again. [pageDigests] follow the current digest time and time zone.
     */
    fun seed(
        pageItems: List<AgentV2NewsFeedItem>,
        pageDigests: List<AgentV2NewsFeedDigest> = emptyList(),
        shouldSkipRead: Boolean = false
    ) {
        val isEmptyPage = pageItems.isEmpty() && pageDigests.isEmpty()
        if (isEmptyPage || entries.isNotEmpty() || hasOpened) return
        if (pageDigests.isNotEmpty()) loadedSchedule = digestSchedule()
        mergePageItems(pageItems, pageDigests)
        if (!shouldSkipRead) openCachedNews()
    }

    fun openCachedNews() {
        if (view != AgentNewsFeedView.All || hasOpened || entries.isEmpty()) return
        open(items, digests)
        updateUnreadBoundary()
        markShownRead()
    }

    fun refresh() {
        cancel()
        val schedule = digestSchedule()
        dropDigestsOfAnotherSchedule(schedule)
        isLoading = true
        error = null
        refreshError = null
        onChange?.invoke()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            var hasLoadedPage = false
            try {
                val requestLanguage = language()
                val page = client.getNewsFeed(requestLanguage, null, schedule, view)
                currentCoroutineContext().ensureActive()
                if (loadJob !== owner) return@launch
                val oldestNewTimestamp = page.items.minOfOrNull {
                    agentNewsTimestamp(it.deliveredAt)
                }
                val newestLoadedTimestamp = items.lastOrNull()?.let {
                    agentNewsTimestamp(it.deliveredAt)
                }
                val hasGap = oldestNewTimestamp != null && newestLoadedTimestamp != null &&
                    oldestNewTimestamp > newestLoadedTimestamp && page.items.none { fresh ->
                        items.any { it.eventId == fresh.eventId }
                    }
                val hasDigestGap = view == AgentNewsFeedView.Digests && digests.isNotEmpty() &&
                    page.digests.orEmpty().none { fresh -> digests.any { it.id == fresh.id } }
                if ((locale != null && locale != page.locale) || hasGap || hasDigestGap) {
                    resetFeed()
                }
                dropPendingDigests()
                locale = page.locale
                feedLanguage = requestLanguage
                hasLoaded = true
                mergePageItems(page.items, page.digests.orEmpty())
                if (!hasOpened) open(page.items, page.digests.orEmpty())
                updateUnreadBoundary()
                markShownRead()
                nextCursor = page.nextCursor
                requestedCursors.clear()
                hasLoadedPage = true
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (loadJob === owner) {
                    if (view == AgentNewsFeedView.All) dropPendingDigests()
                    if (items.isEmpty() && digests.isEmpty()) {
                        this@AgentNewsFeedPageModel.error = error
                    } else {
                        refreshError = error
                    }
                }
            } finally {
                if (loadJob === owner) {
                    loadJob = null
                    isLoading = false
                    onChange?.invoke()
                    if (hasLoadedPage) continueLoadingOlderPages()
                }
            }
        }
        loadJob = request
        request.start()
    }

    fun loadMore() {
        if (isLoading || isLoadingMore || nextCursor == null) return
        prefetchJob?.cancel()
        prefetchJob = null
        val schedule = digestSchedule()
        // Older pages follow the schedule they were loaded with: a new digest time or time zone, such as a time zone
        // the phone changed while the feed was open, refreshes the feed instead
        if (schedule != loadedSchedule) {
            refresh()
            return
        }
        isLoadingMore = true
        onChange?.invoke()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            val originalCount = items.size + digests.size
            var hasLoadedPage = false
            try {
                do {
                    val cursor = nextCursor?.takeUnless { it in requestedCursors } ?: break
                    val page = client.getNewsFeed(
                        feedLanguage ?: language(),
                        cursor,
                        schedule,
                        view
                    )
                    currentCoroutineContext().ensureActive()
                    if (loadMoreJob !== owner) return@launch
                    if (page.locale != locale) {
                        resetFeed()
                        refresh()
                        return@launch
                    }
                    requestedCursors.add(cursor)
                    mergePageItems(page.items, page.digests.orEmpty())
                    updateUnreadBoundary()
                    markShownRead()
                    nextCursor = page.nextCursor?.takeUnless { it in requestedCursors }
                    if (page.nextCursor == null) hasReachedHistoryEnd = true
                } while (items.size + digests.size == originalCount && nextCursor != null)
                hasLoadedPage = true
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Keep the cursor for another trigger; a failed page pauses automatic pagination
                if (loadMoreJob === owner) isSeekingRequestedDigest = false
            } finally {
                if (loadMoreJob === owner) {
                    loadMoreJob = null
                    isLoadingMore = false
                    onChange?.invoke()
                    if (hasLoadedPage) continueLoadingOlderPages()
                }
            }
        }
        loadMoreJob = request
        request.start()
    }

    /** The feed has shown the requested digest, or the user has scrolled it, which ends the search */
    fun stopSeekingRequestedDigest() {
        val shouldResumePrefetch = isSeekingRequestedDigest && hasRequestedDigest
        isSeekingRequestedDigest = false
        if (shouldResumePrefetch) continueLoadingOlderPages()
    }

    fun markDigestReached(id: String) {
        val digest = digests.firstOrNull { it.id == id } ?: return
        val timestamp = agentNewsTimestamp(digest.deliveredAt)
        val previous = reachedDigestTimestamp
        if (previous != null && timestamp >= previous) return
        reachedDigestTimestamp = timestamp
        continueLoadingOlderPages()
    }

    private fun continueLoadingOlderPages() {
        if (!hasLoaded || isLoading || isLoadingMore) return
        if (isSeekingRequestedDigest) {
            if (hasRequestedDigest) return
            if (canLoadRequestedDigest) {
                loadMore()
                return
            }
            isSeekingRequestedDigest = false
        }
        if (view == AgentNewsFeedView.Digests || prefetchJob != null ||
            !shouldPrefetchOlderPage()
        ) {
            return
        }
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            // Yield between background pages so the feed can update its visible anchor
            yield()
            if (prefetchJob !== owner) return@launch
            prefetchJob = null
            if (shouldPrefetchOlderPage()) loadMore()
        }
        prefetchJob = request
        request.start()
    }

    private fun shouldPrefetchOlderPage(): Boolean {
        if (hasReachedHistoryEnd || nextCursor == null) return false
        val reached = reachedDigestTimestamp
        if (digests.count { reached == null || agentNewsTimestamp(it.deliveredAt) < reached } >=
            2
        ) {
            return false
        }
        val reference = reached ?: items.lastOrNull()?.let { agentNewsTimestamp(it.deliveredAt) }
        val oldest = items.firstOrNull()?.let { agentNewsTimestamp(it.deliveredAt) }
        return reference == null || oldest == null ||
            reference - oldest < AGENT_NEWS_PREFETCH_WINDOW_MS
    }

    /**
     * The pages of another digest time or time zone go at once. Its digests go as the refresh brings the new schedule's
     * first page; the news stay until the refresh brings the new schedule's.
     */
    private fun dropDigestsOfAnotherSchedule(schedule: AgentNewsDigestSchedule) {
        val previous = loadedSchedule
        loadedSchedule = schedule
        if (previous == null || previous == schedule) return
        isDigestResetPending = true
        reachedDigestTimestamp = null
        hasReachedHistoryEnd = false
        nextCursor = null
        requestedCursors.clear()
    }

    private fun dropPendingDigests() {
        if (!isDigestResetPending) return
        isDigestResetPending = false
        digests = emptyList()
        // A digest of the other schedule reached while they stayed tells nothing of the new one's
        reachedDigestTimestamp = null
    }

    fun cancel() {
        loadJob?.cancel()
        loadJob = null
        loadMoreJob?.cancel()
        loadMoreJob = null
        prefetchJob?.cancel()
        prefetchJob = null
        isLoading = false
        isLoadingMore = false
    }

    fun markDiscussion(eventId: Int, thread: AgentV2ThreadSummary) {
        localDiscussions[eventId] = AgentV2NewsFeedItem.Discussion(thread.id, thread.icon)
        items = applyingLocalDiscussions(items)
        onChange?.invoke()
    }

    fun markDiscussion(digestId: String, thread: AgentV2ThreadSummary) {
        localDigestDiscussions[digestId] = AgentV2NewsFeedItem.Discussion(thread.id, thread.icon)
        digests = applyLocalDigestDiscussions(digests)
        onChange?.invoke()
    }

    fun removeDiscussion(threadId: String) {
        localDiscussions.entries.removeAll { it.value.threadId == threadId }
        localDigestDiscussions.entries.removeAll { it.value.threadId == threadId }
        digests = digests.map { digest ->
            if (digest.discussion?.threadId == threadId) digest.copy(discussion = null) else digest
        }
        items = items.map { item ->
            if (item.discussion?.threadId == threadId) item.copy(discussion = null) else item
        }
        onChange?.invoke()
    }

    private fun mergePageItems(
        pageItems: List<AgentV2NewsFeedItem>,
        pageDigests: List<AgentV2NewsFeedDigest> = emptyList()
    ) {
        pageDigests.forEach { digest ->
            val discussion = localDigestDiscussions[digest.id] ?: return@forEach
            val icon = digest.discussion?.icon?.takeIf { it.isNotEmpty() }
            if (digest.discussion?.threadId == discussion.threadId && icon != null) {
                localDigestDiscussions[digest.id] = discussion.copy(icon = icon)
            }
        }
        digests = applyLocalDigestDiscussions(
            (digests + pageDigests).associateBy { it.id }.values.toList()
        )
        pageItems.forEach { item ->
            val discussion = localDiscussions[item.eventId] ?: return@forEach
            val icon = item.discussion?.icon?.takeIf { it.isNotEmpty() }
            if (item.discussion?.threadId == discussion.threadId && icon != null) {
                localDiscussions[item.eventId] = discussion.copy(icon = icon)
            }
        }
        items = applyingLocalDiscussions(mergeAgentNewsItems(items + pageItems))
    }

    private fun applyingLocalDiscussions(items: List<AgentV2NewsFeedItem>) = items.map { item ->
        localDiscussions[item.eventId]?.let { item.copy(discussion = it) } ?: item
    }

    private fun applyLocalDigestDiscussions(digests: List<AgentV2NewsFeedDigest>) =
        digests.map { digest ->
            localDigestDiscussions[digest.id]?.let { digest.copy(discussion = it) } ?: digest
        }

    private fun resetFeed() {
        items = emptyList()
        digests = emptyList()
        isDigestResetPending = false
        reachedDigestTimestamp = null
        hasReachedHistoryEnd = false
        nextCursor = null
        locale = null
        feedLanguage = null
        hasLoaded = false
        hasOpened = false
        unreadCutoff = null
        unreadEventId = null
        unreadDigestId = null
        refreshError = null
        requestedCursors.clear()
        onReset?.invoke()
    }

    /**
     * The news, or in the Digests view the digests, delivered after those read before the view first showed its
     * entries stay new while the feed is open
     */
    private fun open(
        pageItems: List<AgentV2NewsFeedItem>,
        pageDigests: List<AgentV2NewsFeedDigest>
    ) {
        unreadCutoff = if (view == AgentNewsFeedView.All) {
            readState.initializeIfNeeded(pageItems)
            readState.readThrough
        } else {
            readState.initializeDigestsIfNeeded(pageDigests)
            readState.digestsReadThrough
        }?.let(::agentNewsTimestamp)
        hasOpened = true
    }

    private fun updateUnreadBoundary() {
        val cutoff = unreadCutoff
        unreadEventId = cutoff?.takeIf { view == AgentNewsFeedView.All }?.let {
            items.firstOrNull { item -> agentNewsTimestamp(item.deliveredAt) > it }?.eventId
        }
        unreadDigestId = cutoff?.takeIf { view == AgentNewsFeedView.Digests }?.let {
            digests.map { digest -> digest to agentNewsTimestamp(digest.deliveredAt) }
                .filter { (_, deliveredAt) -> deliveredAt > it }
                .minByOrNull { (_, deliveredAt) -> deliveredAt }?.first?.id
        }
    }

    /** The news and digests the view has loaded are read */
    private fun markShownRead() {
        if (view == AgentNewsFeedView.All) readState.markRead(items)
        readState.markDigestsRead(digests)
    }
}

internal fun mergeAgentNewsItems(items: List<AgentV2NewsFeedItem>): List<AgentV2NewsFeedItem> {
    val byId = linkedMapOf<Int, AgentV2NewsFeedItem>()
    items.forEach { item ->
        val previous = byId[item.eventId]
        if (previous == null ||
            agentNewsTimestamp(item.deliveredAt) >= agentNewsTimestamp(previous.deliveredAt)
        ) {
            byId[item.eventId] = item
        }
    }
    return byId.values.sortedWith(
        compareBy<AgentV2NewsFeedItem> { agentNewsTimestamp(it.deliveredAt) }.thenBy { it.eventId }
    )
}

internal fun agentNewsErrorText(error: Throwable): String =
    if ((error as? AgentV2OperationException)?.error?.code == "news_unavailable") {
        LocaleController.getString("\$agent_news_unavailable")
    } else {
        agentUnavailableText()
    }

private fun agentNewsTimestamp(value: String): Long = parseAgentV2Timestamp(value)?.time ?: 0
