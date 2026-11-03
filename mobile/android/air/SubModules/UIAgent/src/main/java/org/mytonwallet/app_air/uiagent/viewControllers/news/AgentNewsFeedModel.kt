package org.mytonwallet.app_air.uiagent.viewControllers.news

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.callAgentV2Mutation
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.insertGroupingSeparator
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedPage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

private const val AGENT_NEWS_UNREAD_COUNT_CAP = 30

internal interface AgentNewsFeedClient {
    suspend fun getNewsFeed(lang: String, cursor: String?): AgentV2NewsFeedPage
}

internal class LiveAgentNewsFeedClient : AgentNewsFeedClient {
    override suspend fun getNewsFeed(lang: String, cursor: String?) =
        callAgentV2Mutation(ApiMethod.AgentV2.GetNewsFeed(lang, cursor))
}

internal class AgentNewsReadState(
    private val read: () -> String? = WGlobalStorage::getAgentNewsReadThrough,
    private val write: (String) -> Unit = WGlobalStorage::setAgentNewsReadThrough
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
}

/** The count covers only the loaded page, so a full page reads "30+". */
internal fun formatAgentNewsUnreadCount(count: Int): String? = when {
    count <= 0 -> null
    count >= AGENT_NEWS_UNREAD_COUNT_CAP -> "$AGENT_NEWS_UNREAD_COUNT_CAP+"
    else -> count.toString().insertGroupingSeparator()
}

internal class AgentNewsPreviewModel(
    private val scope: CoroutineScope,
    private val client: AgentNewsFeedClient = LiveAgentNewsFeedClient(),
    private val readState: AgentNewsReadState = AgentNewsReadState(),
    private val language: () -> String = { LocaleController.activeLanguage.langCode }
) {
    var items: List<AgentV2NewsFeedItem> = emptyList()
        private set

    /** The language [items] were loaded in */
    var itemsLanguage: String? = null
        private set
    val latestItem: AgentV2NewsFeedItem? get() = items.lastOrNull()
    val unreadCount: Int get() = readState.unreadCount(items)
    var onChange: (() -> Unit)? = null

    private var loadJob: Job? = null

    fun refresh() {
        loadJob?.cancel()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            try {
                val requestLanguage = language()
                val page = client.getNewsFeed(requestLanguage, null)
                currentCoroutineContext().ensureActive()
                if (loadJob !== owner) return@launch
                items = mergeAgentNewsItems(page.items)
                itemsLanguage = requestLanguage
                readState.initializeIfNeeded(items)
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
    private val scope: CoroutineScope,
    private val client: AgentNewsFeedClient = LiveAgentNewsFeedClient(),
    private val readState: AgentNewsReadState = AgentNewsReadState(),
    private val language: () -> String = { LocaleController.activeLanguage.langCode }
) {
    var items: List<AgentV2NewsFeedItem> = emptyList()
        private set
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
    var unreadEventId: Int? = null
        private set
    var onChange: (() -> Unit)? = null
    var onReset: (() -> Unit)? = null

    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private var hasOpened = false
    private var unreadCutoff: Long? = null
    private var feedLanguage: String? = null
    private val requestedCursors = mutableSetOf<String>()
    private val localDiscussions = mutableMapOf<Int, AgentV2NewsFeedItem.Discussion>()

    /**
     * Shows the first page the list's News row has loaded at once, as the feed's own first page would, while the
     * feed loads it again
     */
    fun seed(pageItems: List<AgentV2NewsFeedItem>) {
        if (pageItems.isEmpty() || items.isNotEmpty() || hasOpened) return
        mergePageItems(pageItems)
        readState.initializeIfNeeded(pageItems)
        unreadCutoff = readState.readThrough?.let(::agentNewsTimestamp)
        hasOpened = true
        updateUnreadBoundary()
        readState.markRead(items)
    }

    fun refresh() {
        cancel()
        isLoading = true
        error = null
        refreshError = null
        onChange?.invoke()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            try {
                val requestLanguage = language()
                val page = client.getNewsFeed(requestLanguage, null)
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
                if ((locale != null && locale != page.locale) || hasGap) {
                    resetFeed()
                }
                locale = page.locale
                feedLanguage = requestLanguage
                mergePageItems(page.items)
                if (!hasOpened) {
                    readState.initializeIfNeeded(page.items)
                    unreadCutoff = readState.readThrough?.let(::agentNewsTimestamp)
                    hasOpened = true
                }
                updateUnreadBoundary()
                readState.markRead(items)
                nextCursor = page.nextCursor
                requestedCursors.clear()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (loadJob === owner) {
                    if (items.isEmpty()) {
                        this@AgentNewsFeedModel.error = error
                    } else {
                        refreshError = error
                    }
                }
            } finally {
                if (loadJob === owner) {
                    loadJob = null
                    isLoading = false
                    onChange?.invoke()
                }
            }
        }
        loadJob = request
        request.start()
    }

    fun loadMore() {
        if (isLoading || isLoadingMore || nextCursor == null) return
        isLoadingMore = true
        onChange?.invoke()
        val request = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            val originalCount = items.size
            try {
                do {
                    val cursor = nextCursor?.takeUnless { it in requestedCursors } ?: break
                    val page = client.getNewsFeed(feedLanguage ?: language(), cursor)
                    currentCoroutineContext().ensureActive()
                    if (loadMoreJob !== owner) return@launch
                    if (page.locale != locale) {
                        resetFeed()
                        refresh()
                        return@launch
                    }
                    requestedCursors.add(cursor)
                    mergePageItems(page.items)
                    updateUnreadBoundary()
                    readState.markRead(items)
                    nextCursor = page.nextCursor?.takeUnless { it in requestedCursors }
                } while (items.size == originalCount && nextCursor != null)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Keep the cursor so another scroll can retry the older page.
            } finally {
                if (loadMoreJob === owner) {
                    loadMoreJob = null
                    isLoadingMore = false
                    onChange?.invoke()
                }
            }
        }
        loadMoreJob = request
        request.start()
    }

    fun cancel() {
        loadJob?.cancel()
        loadJob = null
        loadMoreJob?.cancel()
        loadMoreJob = null
        isLoading = false
        isLoadingMore = false
    }

    fun markDiscussion(eventId: Int, thread: AgentV2ThreadSummary) {
        localDiscussions[eventId] = AgentV2NewsFeedItem.Discussion(thread.id, thread.icon)
        items = applyingLocalDiscussions(items)
        onChange?.invoke()
    }

    fun removeDiscussion(threadId: String) {
        localDiscussions.entries.removeAll { it.value.threadId == threadId }
        items = items.map { item ->
            if (item.discussion?.threadId == threadId) item.copy(discussion = null) else item
        }
        onChange?.invoke()
    }

    private fun mergePageItems(pageItems: List<AgentV2NewsFeedItem>) {
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

    private fun resetFeed() {
        items = emptyList()
        nextCursor = null
        locale = null
        feedLanguage = null
        hasOpened = false
        unreadCutoff = null
        unreadEventId = null
        refreshError = null
        requestedCursors.clear()
        onReset?.invoke()
    }

    private fun updateUnreadBoundary() {
        unreadEventId = unreadCutoff?.let { cutoff ->
            items.firstOrNull { agentNewsTimestamp(it.deliveredAt) > cutoff }?.eventId
        }
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
