package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.os.Looper
import java.lang.ref.WeakReference
import java.util.Date
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.math.max
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.mytonwallet.app_air.uiagent.agentV2.AgentActionAvailability
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2ChatActivity
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2HostContextProvider
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.agentV2SemanticText
import org.mytonwallet.app_air.uiagent.agentV2.buildAgentActionUrl
import org.mytonwallet.app_air.uiagent.agentV2.getAgentAnalyzingRequestText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentV2RunActivityText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentWritingAnswerText
import org.mytonwallet.app_air.uiagent.agentV2.hasPost
import org.mytonwallet.app_air.uiagent.agentV2.hasVisibleFailure
import org.mytonwallet.app_air.uiagent.agentV2.isAgentV2ThreadStarted
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.agentV2.mapAgentV2Message
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.agentV2.requiresAgentV2ThreadResync
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_STOPPED_ANSWER_DURATION_MS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.isAgentStoppedAnswerAnimated
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadReadState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.loadExploreSites
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class AgentVM internal constructor(
    initialScrollPosition: ScrollPosition? = null,
    private val client: AgentV2Client = LiveAgentV2Client(),
    initialThread: AgentV2ThreadSummary,
    initialMessages: List<AgentMessage> = emptyList(),
    private var initialOpeningEntryPoint: AgentV2EntryPoint? = null,
    private val canShowCachedMessages: Boolean = false,
    private val cachedHistories: AgentCachedHistories = AgentSession.cachedHistories,
    private val scope: CoroutineScope,
    contextProvider: AgentV2HostContextProvider? = null,
    private val now: () -> Long = System::currentTimeMillis,
    // How long the row of an answer stopped before it showed stays, with the top stopping, before it goes
    private val stoppedAnswerDurationMs: () -> Long = { 0L },
    private val waitForSupportPoll: suspend () -> Unit = { delay(SUPPORT_POLLING_INTERVAL_MS) }
) : WalletCore.UpdatesObserver,
    WalletCore.EventObserver {
    constructor(
        initialScrollPosition: ScrollPosition? = null,
        client: AgentV2Client = LiveAgentV2Client(),
        initialThread: AgentV2ThreadSummary,
        initialMessages: List<AgentMessage> = emptyList(),
        initialOpeningEntryPoint: AgentV2EntryPoint? = null,
        canShowCachedMessages: Boolean = false
    ) : this(
        initialScrollPosition,
        client,
        initialThread,
        initialMessages,
        initialOpeningEntryPoint,
        canShowCachedMessages,
        AgentSession.cachedHistories,
        CoroutineScope(SupervisorJob() + Dispatchers.Main),
        stoppedAnswerDurationMs = {
            if (isAgentStoppedAnswerAnimated) AGENT_STOPPED_ANSWER_DURATION_MS else 0L
        }
    )

    // A rating that settles while the clear hides the timeline updates [fallbackMessages]
    private class ClearIntent(
        var fallbackMessages: List<AgentMessage>,
        val fallbackScrollPosition: ScrollPosition?
    ) {
        var chatOpening: Pair<List<AgentMessage>, AgentV2EntryPoint>? = null
            private set

        fun reopenChat(messages: List<AgentMessage>, entryPoint: AgentV2EntryPoint): Boolean {
            if (chatOpening != null) return false
            chatOpening = messages to entryPoint
            return true
        }
    }

    interface Delegate {
        fun onStateChanged(state: State)
        fun onMessageAdded(message: AgentMessage, animated: Boolean = true)
        fun onMessageRemoved(messageId: String)
        fun onMessagesLoaded(messages: List<AgentMessage>)
        fun onMessagesRefreshed(messages: List<AgentMessage>) {}
        fun onMessagesTruncated(removedMessages: List<AgentMessage>)
        fun onMessagesPrepended(messages: List<AgentMessage>)
        fun onStreamingUpdate(messageId: String)
        fun onStreamingFinished(messageId: String)
        fun onFollowupsChanged(messageId: String, animated: Boolean = false)
        fun onOutgoingMessageFailed(messageId: String)
        fun onPendingMessageActivated(messageId: String)
        fun onActionUnavailable(reason: String? = null)
        fun onOpenDapp(site: MExploreSite)
        fun onError()
        fun onHintsUpdated(hints: List<AgentHint>)
        fun onThreadChanged(thread: AgentV2ThreadSummary)

        /** A limit started or stopped blocking new questions ([AgentVM.isInputBlockedByLimit]) */
        fun onInputLimitChanged() {}

        /** The chat started or stopped offering problem reports ([AgentVM.canReportProblem]) */
        fun onProblemReportAvailabilityChanged() {}

        fun onOlderMessagesLoadingChanged() {}
    }

    enum class State {
        LOADING,
        CONSENT_REQUIRED,
        ACCEPTING_CONSENT,
        READY,
        RUNNING,
        CLEARING,
        ERROR
    }

    sealed interface SupportState {
        data object None : SupportState
        data object Waiting : SupportState
        data class Operator(val name: String?) : SupportState
        data object Closed : SupportState
    }

    sealed interface ScrollAnchor {
        data object Bottom : ScrollAnchor
        data class Message(val messageId: String) : ScrollAnchor
        data object Hints : ScrollAnchor
    }

    data class ScrollPosition(
        val anchor: ScrollAnchor,
        val offset: Int = 0,
        val pinnedMessageId: String? = null,
        val pinnedBottomPadding: Int = 0
    )

    private val delegates = mutableListOf<WeakReference<Delegate>>()
    private val activeDelegates = mutableListOf<WeakReference<Delegate>>()
    private val hostContextProvider =
        contextProvider ?: AgentV2HostContextProvider(client, scope)

    // Its own scope lets the inactive state reach the SDK after onDestroy cancels [scope].
    private val chatActivity = AgentV2ChatActivity(
        CoroutineScope(scope.coroutineContext + SupervisorJob()),
        AgentSession.chatActivityGroup,
        client::setChatActive
    )

    private val actionAvailability = AgentActionAvailability(client::actionPresentation)
    private val pendingMessages = mutableListOf<AgentPendingMessage>()
    private val _messages = initialMessages.toMutableList()
    private var initialOpeningMessageId = initialMessages
        .firstOrNull { it.role == AgentMessageRole.USER }?.id
    private val initialOpeningPrompts = AgentPromptQueue().apply {
        if (initialOpeningEntryPoint != null) {
            initialMessages.firstOrNull { it.role == AgentMessageRole.USER }?.let {
                enqueue(initialMessages, checkNotNull(initialOpeningEntryPoint))
            }
        }
    }
    private var initialAssistantMessageId = initialMessages
        .firstOrNull { it.role == AgentMessageRole.ASSISTANT }?.id
    private var availableHints = emptyList<AgentHint>()
    private var hintsCatalogVersion: String? = null
    private var followupsAndHintsNotificationJob: Job? = null
    private var startupJob: Job? = null
    private var hintsJob: Job? = null
    private var operationJob: Job? = null
    private var actionJob: Job? = null
    private var historyJob: Job? = null

    // The SDK's copy of the history being read while the history loads
    private var cacheReadJob: Job? = null
    private var refreshJob: Job? = null
    private var supportRefreshJob: Deferred<Boolean>? = null
    private var supportPollingJob: Job? = null
    private var isInBackground = false
    private var shouldRefreshSupportHistory = false

    // A history refresh failed, so the chat reads its history again as it shows or the app returns, even after support
    // closes and polling stops; only a merged history clears it
    private var hasFailedSupportRefresh = false
    private var cancellationJob: Job? = null
    private var hostContextRecoveryJob: Job? = null
    private var isDeletingChat = false
    private var availability: AgentV2Availability? = null
    private var userQuota: AgentV2UserQuota? = null
    private var limitRetry: AgentLimitRetry? = null
    private var limitExpiryJob: Job? = null
    private val problemReportJobs = mutableSetOf<Job>()

    // The rating requests of each answer that have not all settled yet, by its server id: history
    // restored after a failed clear keeps it, while presentation ids change
    private val feedbackRequests = mutableMapOf<String, FeedbackRequests>()

    // The answers stopped in this chat as they were shown, by server id: the server may keep less of one than showed
    private val stoppedAnswers = mutableMapOf<String, AgentMessage>()
    private var problemReportAvailabilityJob: Job? = null

    // Whether the server takes problem reports, as its check last answered; null until it has
    private var problemReportAvailability: Boolean? = null
    private var thread: AgentV2ThreadSummary = initialThread

    // The thread's message count as of the history the chat holds. A support chat takes a summary without history, from
    // the list or a thread update, at once and its newest messages only with the next history refresh, so the summary
    // may count replies that haven't loaded.
    private var historyMessageCount = initialThread.messageCount
    internal var historyCursor: String? = null
        private set
    private var hasLoadedHistoryMessages = false

    // Until stored messages load, the chat's counts can't be compared with the thread's
    private var hasHydratedMessages = false
    private val loadedHistoryMessageIds = mutableSetOf<String>()

    // The messages that are the device's copy of the history, shown until the history loads
    private var cachedMessageIds = emptySet<String>()
    private val seenHistoryCursors = mutableSetOf<String>()
    private var revision = initialThread.revision
    private var clearIntent: ClearIntent? = null
    private var currentAccountId = AccountStore.activeAccountId
    private var activeRun: AgentActiveRun? = null

    // The answer stopped before it showed, whose row stays a moment, and the job that takes it away
    private var stoppingAnswer: Pair<String, Job>? = null

    // The queued question a stop sent: the same Stop button stays under the finger, so a repeated tap doesn't stop
    // it before its run reports itself
    private var runStartedByStop: AgentActiveRun? = null
    internal var onSessionIdle: (() -> Unit)? = null

    val messages: List<AgentMessage> get() = _messages
    val currentThread: AgentV2ThreadSummary get() = thread
    internal var loadedOperatorMessageAt: String? = null
        private set
    val supportState: SupportState
        get() = when (thread.support?.state) {
            "waiting" -> SupportState.Waiting

            "operator" -> SupportState.Operator(
                _messages.lastOrNull {
                    it.operator != null || it.supportEvent?.code == "operator_joined"
                }?.let { it.operator?.name ?: it.supportEvent?.operatorName }
            )

            "closed" -> SupportState.Closed

            else -> SupportState.None
        }

    internal val isChatWithSupport: Boolean
        get() = thread.support?.state == "waiting" || thread.support?.state == "operator"

    /** Settled messages, including unloaded older ones; null until stored messages load. */
    internal val seenMessageCount: Int?
        get() = if (hasHydratedMessages) unloadedMessageCount + settledMessages().size else null

    /** Whether the chat holds the messages its thread counts, so that it can tell which of them are unseen */
    internal val hasLoadedNewestMessages: Boolean
        get() = hasHydratedMessages && thread.messageCount <= historyMessageCount

    /**
     * Null until the newest messages load; the first loaded message when the seen ones go past the loaded pages.
     */
    internal fun findFirstUnseenMessageId(seenMessageCount: Int): String? {
        if (!hasLoadedNewestMessages) return null
        return settledMessages().getOrNull(max(0, seenMessageCount - unloadedMessageCount))?.id
    }

    private fun settledMessages(): List<AgentMessage> =
        _messages.filter { it.sdkMessageId != null && !it.isStreaming && it.supportEvent == null }

    // Messages on older pages that haven't loaded
    private val unloadedMessageCount: Int
        get() = max(
            0,
            historyMessageCount -
                _messages.count { it.sdkMessageId != null && it.supportEvent == null }
        )

    /**
     * The status the chat shows while it answers: that it is writing while the answer streams, else the step the
     * Agent is on, or that it is analyzing the question; null when it isn't answering
     */
    internal val answeringText: String?
        get() {
            if (state != State.RUNNING) return null
            val last = _messages.lastOrNull { it.role != AgentMessageRole.SYSTEM }
            val answer = last?.takeIf { it.role == AgentMessageRole.ASSISTANT && it.isStreaming }
            return when {
                answer?.hasText == true -> getAgentWritingAnswerText()
                else -> answer?.activityText ?: getAgentAnalyzingRequestText()
            }
        }
    internal val hasUnsentOpening: Boolean get() = initialOpeningPrompts.isNotEmpty

    /**
     * Whether the server has sent answer links in this session. From then on an answer carries its links and keeps
     * bare domains as text; before, an answer may come from a server that sends its URLs as text.
     */
    var publishesAnswerLinks = false
        private set
    var scrollPosition: ScrollPosition? = initialScrollPosition
        private set
    val visibleHints: List<AgentHint>
        get() = if (!isChatWithSupport && state == State.READY && clearIntent == null &&
            _messages.isEmpty() &&
            !thread.hasPost
        ) {
            availableHints
        } else {
            emptyList()
        }
    val canSendFollowup: Boolean
        get() = !isChatWithSupport && clearIntent == null && cachedMessageIds.isEmpty() &&
            pendingMessages.isEmpty() && canSendNow() && !isInputBlockedByLimit

    /**
     * No question can be sent while the Agent's capacity is exhausted, the user's quota is used up, or a question a
     * limit held back waits for it, until the limit resets
     */
    val isInputBlockedByLimit: Boolean
        get() {
            val now = now()
            val capacity = availability?.takeIf { it.state == CAPACITY_EXHAUSTED }
            if ((capacity?.resetAt ?: 0L) > now) return true
            // A question the quota held back waits for its own reset rather than the quota's
            val quota = userQuota?.takeIf { it.remaining == 0 && limitRetry?.isRateLimit != false }
            if ((quota?.resetAt?.let(::parseAgentV2Timestamp)?.time ?: 0L) > now) return true
            return (limitRetry?.resetAt ?: 0L) > now
        }

    /** Retry can send the question a limit held back, which it can once the limit resets */
    private val canRetryLimit: Boolean
        get() {
            if (isChatWithSupport) return false
            val retry = limitRetry ?: return false
            if (retry.expiresAt <= now()) return false
            return !isInputBlockedByLimit && clearIntent == null &&
                pendingMessages.isEmpty() && canSendNow()
        }

    /**
     * What Retry under the chat's latest failure does now, if anything: start the chat again after its startup
     * failed, or send the question a limit held back. Neither shows while a limit blocks sending.
     */
    val failureRetry: (() -> Unit)?
        get() = when {
            isInputBlockedByLimit -> null
            state == State.ERROR -> ::retry
            canRetryLimit -> ::retryLimit
            else -> null
        }

    /**
     * With the user's consent, the chat offers problem reports from the start, before its history loads or the server's
     * check answers: reports count as taken until the check says otherwise
     */
    val canReportProblem: Boolean
        get() = (hasConsent ?: client.isConsentKnownGiven) && problemReportAvailability != false &&
            cachedMessageIds.isEmpty()
    var state = State.LOADING
        private set

    /** Whether the user has written in the thread, a question sent here counting at once */
    val isThreadStarted: Boolean
        get() = isAgentV2ThreadStarted(thread) || _messages.any { it.role == AgentMessageRole.USER }

    /** Whether the user has allowed the Agent, once the chat has read it; a news discussion loads without it */
    var hasConsent: Boolean? = null
        private set
    internal var startupErrorCode: String? = null
        private set
    internal val shouldRetainSession: Boolean
        get() = !isDeletingChat && (
            state == State.RUNNING ||
                state == State.CLEARING ||
                clearIntent != null ||
                operationJob?.isActive == true ||
                historyJob?.isActive == true ||
                hostContextRecoveryJob?.isActive == true ||
                (
                    initialOpeningPrompts.isNotEmpty &&
                        (startupJob?.isActive == true || state == State.READY)
                    ) ||
                problemReportJobs.isNotEmpty()
            )

    /** A chat closed lately stays loaded while it is ready to show, or answering */
    internal val canStayLoaded: Boolean
        get() = !isDeletingChat && (state == State.READY || state == State.RUNNING)

    init {
        hostContextProvider.isRunActive = { operationJob?.isActive == true }
        hostContextProvider.onAuthorityContextInvalidated = ::invalidateWalletAuthority
        hostContextProvider.onAuthorityContextPublished = {
            enqueueInitialOpeningPrompt()
            sendNextPending()
            notifyFollowupsAndHints()
        }
        hostContextProvider.onMessageAuthorityChanged = {
            enqueueInitialOpeningPrompt()
            notifyFollowupsAndHints()
        }
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        WalletCore.registerObserver(this)
        // The copy held in memory shows in the chat's first frame, without waiting for the SDK
        if (canReadCachedMessages()) cachedHistories.get(thread.id)?.let(::applyCachedMessages)
        start()
    }

    fun attach(delegate: Delegate) {
        if (liveDelegates(delegates).none { it === delegate }) {
            delegates.add(WeakReference(delegate))
        }
        delegate.onMessagesLoaded(_messages.toList())
        delegate.onThreadChanged(thread)
        delegate.onHintsUpdated(visibleHints)
        delegate.onStateChanged(state)
    }

    fun detach(delegate: Delegate) {
        removeDelegate(delegates, delegate)
        setActive(delegate, false)
    }

    fun setActive(delegate: Delegate, active: Boolean) {
        val wasActive = liveDelegates(activeDelegates).isNotEmpty()
        val wasVisible = isSupportChatVisible
        removeDelegate(activeDelegates, delegate)
        if (active) {
            activeDelegates.add(WeakReference(delegate))
            retry()
            refreshProblemReportAvailability()
        }
        val isActive = liveDelegates(activeDelegates).isNotEmpty()
        if (wasActive && !isActive) {
            activeRun?.let { run ->
                run.canResendSupportConflict = false
                if (run.shouldResendSupportConflict) {
                    run.shouldResendSupportConflict = false
                    refreshJob?.cancel()
                }
            }
        }
        chatActivity.setVisible(isActive)
        if (!wasVisible && isSupportChatVisible && (isChatWithSupport || hasFailedSupportRefresh)) {
            shouldRefreshSupportHistory = true
        }
        updateSupportPolling()
    }

    fun retry() {
        if (state == State.ERROR && startupJob?.isActive != true) start()
    }

    /**
     * A chat kept loaded and opened again from a newer [summary] of its thread loads its newest messages again, in
     * place, as iOS's does; a question sent meanwhile cancels the refresh, and a failed one keeps what shows
     */
    internal fun refreshThreadIfNeeded(summary: AgentV2ThreadSummary) {
        if (summary.id != thread.id || isDeletingChat) return
        if (isChatWithSupport || summary.support != thread.support) {
            if (summary.revision >= currentRevision() &&
                (summary.support != thread.support || summary.revision > currentRevision())
            ) {
                val hasSupportChanged = summary.support != thread.support
                bindThread(summary)
                if (!hasSupportChanged) requestSupportHistoryRefresh()
            }
            return
        }
        if (isDeletingChat || state != State.READY || summary.id != thread.id ||
            summary.revision <= currentRevision() || clearIntent != null ||
            operationJob?.isActive == true || historyJob?.isActive == true ||
            refreshJob?.isActive == true
        ) {
            return
        }
        refreshJob = scope.launch {
            try {
                hydrate(isKeptChatRefresh = true)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
            } finally {
                if (refreshJob === currentCoroutineContext().job) refreshJob = null
                updateSupportPolling()
                notifySessionIdle()
            }
        }
    }

    private val isSupportChatVisible: Boolean
        get() = !isInBackground && liveDelegates(activeDelegates).isNotEmpty()

    private fun canRefreshSupportHistory(): Boolean =
        isSupportChatVisible && hasHydratedMessages && state == State.READY &&
            clearIntent == null && !isDeletingChat && historyJob == null &&
            operationJob?.isActive != true && startupJob?.isActive != true

    private fun requestSupportHistoryRefresh() {
        shouldRefreshSupportHistory = true
        updateSupportPolling()
    }

    private fun updateSupportPolling() {
        if (!canRefreshSupportHistory() || !isChatWithSupport) {
            supportPollingJob?.cancel()
            supportPollingJob = null
        } else if (supportPollingJob == null) {
            supportPollingJob = scope.launch {
                while (true) {
                    waitForSupportPoll()
                    requestSupportHistoryRefresh()
                }
            }
        }
        if (!isSupportChatVisible && thread.support != null && state != State.RUNNING) {
            if (supportRefreshJob?.isActive == true) shouldRefreshSupportHistory = true
            supportRefreshJob?.cancel()
        }
        if (shouldRefreshSupportHistory && canRefreshSupportHistory() &&
            refreshJob?.isActive != true
        ) {
            shouldRefreshSupportHistory = false
            startLatestSupportRefresh()
        }
    }

    private suspend fun refreshLatestSupportMessages(run: AgentActiveRun): Boolean {
        val request = startLatestSupportRefresh(run)
        return try {
            request.await()
        } catch (e: CancellationException) {
            currentCoroutineContext().ensureActive()
            false
        } finally {
            if (!currentCoroutineContext().isActive) request.cancel()
        }
    }

    private fun startLatestSupportRefresh(run: AgentActiveRun? = null): Deferred<Boolean> {
        refreshJob?.cancel()
        val threadId = thread.id
        val startingSupport = thread.support
        val request = scope.async(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            var hasMerged = false
            try {
                val pages = mutableListOf<AgentV2ThreadHydration>()
                val cursors = mutableSetOf<String>()
                val knownIds = _messages.mapNotNullTo(mutableSetOf()) {
                    it.sdkMessageId?.takeIf(loadedHistoryMessageIds::contains)
                }
                var cursor: String? = null
                do {
                    val page = client.messages(threadId, cursor, MESSAGE_PAGE_SIZE)
                    currentCoroutineContext().ensureActive()
                    check(page.thread.id == threadId) { "Unexpected Agent thread" }
                    if (refreshJob !== owner) return@async false
                    pages.add(page)
                    if (page.messages.any { it.id in knownIds }) break
                    cursor = page.nextCursor
                    check(cursor == null || cursors.add(cursor)) { "Repeated Agent message cursor" }
                } while (cursor != null && pages.size < MAX_SUPPORT_REFRESH_PAGES)

                val newest = pages.first()

                // The chat may have moved on while the pages loaded, and again while they were read
                fun isStale() = refreshJob !== owner || thread.id != threadId ||
                    clearIntent != null || isDeletingChat ||
                    newest.thread.revision < currentRevision() ||
                    (
                        newest.thread.revision == currentRevision() &&
                            thread.support != startingSupport &&
                            newest.thread.support != thread.support
                        ) ||
                    (run == null && !canRefreshSupportHistory()) ||
                    (run != null && activeRun !== run)
                if (isStale()) return@async false
                val pageMessages =
                    withStoppedAnswers(nativeMessages(pages.asReversed().flatMap { it.messages }))
                currentCoroutineContext().ensureActive()
                if (isStale()) return@async false
                val merged = withPendingFeedback(mergeSupportAgentMessages(_messages, pageMessages))
                bindThread(newest.thread, isLatestHistory = true, hasHistory = true)
                cachedHistories.storeLoadedPage(
                    newest.thread,
                    newest.messages,
                    hasOlder = newest.nextCursor != null
                )
                _messages.clear()
                _messages.addAll(merged)
                pageMessages.mapNotNullTo(loadedHistoryMessageIds) { it.sdkMessageId }
                hasLoadedHistoryMessages = hasAgentThreadHistory(newest.thread, merged)
                loadedOperatorMessageAt = newest.thread.support?.lastOperatorMessageAt
                hasFailedSupportRefresh = false
                notifyDelegates { it.onMessagesRefreshed(_messages.toList()) }
                notifyHints()
                hasMerged = true
                true
            } catch (e: CancellationException) {
                if (run == null && refreshJob === owner) shouldRefreshSupportHistory = true
                throw e
            } catch (_: Throwable) {
                if (run == null) hasFailedSupportRefresh = true
                false
            } finally {
                if (supportRefreshJob === owner) supportRefreshJob = null
                if (refreshJob === owner) {
                    refreshJob = null
                    if (hasMerged || shouldRefreshSupportHistory) updateSupportPolling()
                }
            }
        }
        refreshJob = request
        supportRefreshJob = request
        request.start()
        return request
    }

    fun updateScrollPosition(delegate: Delegate, position: ScrollPosition) {
        if (liveDelegates(activeDelegates).none { it === delegate }) return
        scrollPosition = position.copy(
            anchor = when (val anchor = position.anchor) {
                is ScrollAnchor.Message -> ScrollAnchor.Message(
                    canonicalMessageId(anchor.messageId)
                )

                else -> anchor
            },
            pinnedMessageId = position.pinnedMessageId?.let(::canonicalMessageId)
        )
    }

    fun clearChat() {
        if (clearIntent != null) return
        val clearAction = agentClearAction(
            state,
            operationInFlight = operationJob?.isActive == true
        )
        if (clearAction == AgentClearAction.IGNORE) return

        initialOpeningEntryPoint = null
        initialOpeningPrompts.clear()
        initialAssistantMessageId = null
        limitRetry = null
        clearIntent = ClearIntent(
            fallbackMessages = safeAgentClearFallback(
                _messages.filterNot { message ->
                    message.id in cachedMessageIds ||
                        pendingMessages.any { it.assistantMessageId == message.id }
                },
                pendingMessages.map { it.message }
            ),
            fallbackScrollPosition = scrollPosition
        )
        cancelHostContextRecovery()
        cancelPendingAction()
        cachedMessageIds = emptySet()
        clearPresentation()
        setState(State.CLEARING)
        when (clearAction) {
            AgentClearAction.CANCEL_RUN -> requestRunCancellation()
            AgentClearAction.START -> launchPendingClear()
            AgentClearAction.QUEUE -> Unit
            AgentClearAction.IGNORE -> Unit
        }
    }

    /** Stops local work now; server deletion outlives the screen and its session. */
    fun deleteChat(onFailure: (Throwable) -> Unit) {
        if (isDeletingChat) return
        isDeletingChat = true
        val threadId = thread.id
        cachedHistories.remove(threadId)
        initialOpeningPrompts.clear()
        pendingMessages.clear()
        val deletionScope = CoroutineScope(scope.coroutineContext + SupervisorJob())
        onDestroy()
        deletionScope.launch {
            try {
                client.deleteThread(threadId)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                onFailure(error)
            } finally {
                deletionScope.cancel()
            }
        }
    }

    internal fun reopenOpeningAfterClear(
        messages: List<AgentMessage>,
        entryPoint: AgentV2EntryPoint
    ) {
        if (messages.isEmpty()) return
        val intent = clearIntent ?: return
        if (!intent.reopenChat(messages, entryPoint)) return
        _messages.addAll(messages)
        notifyLoaded()
    }

    internal fun acceptOpening(messages: List<AgentMessage>, entryPoint: AgentV2EntryPoint) {
        if (isDeletingChat || messages.isEmpty()) return
        if (clearIntent != null) {
            reopenOpeningAfterClear(messages, entryPoint)
            return
        }
        val user = messages.first { it.role == AgentMessageRole.USER }
        if (_messages.any { it.id == user.id }) return
        _messages.addAll(messages)
        initialOpeningPrompts.enqueue(messages, entryPoint)
        notifyLoaded()
        sendNextPending()
    }

    private fun launchPendingClear() {
        val currentThread = thread
        val intent = clearIntent ?: return
        if (operationJob?.isActive == true) return
        refreshJob?.cancel()
        resetActiveRunState()
        setState(State.CLEARING)
        operationJob = scope.launch {
            var hasFailed = false
            try {
                val response = clearAgentThreadWithConflictRetry(
                    clear = {
                        client.clearThread(currentThread.id, currentRevision())
                    },
                    refreshRevision = {
                        refreshThreadRevisionForClear(currentThread.id)
                    }
                )
                check(response.thread.id == currentThread.id) { "Unexpected Agent thread" }
                hasLoadedHistoryMessages = false
                bindThread(response.thread)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                hasFailed = true
            } finally {
                if (operationJob === currentCoroutineContext().job) operationJob = null
                notifyFollowupsAndHints()
            }

            if (!hasFailed) {
                cachedHistories.remove(currentThread.id)
                clearIntent = null
                intent.chatOpening?.let { (messages, entryPoint) ->
                    val user = messages.first { it.role == AgentMessageRole.USER }
                    initialOpeningMessageId = user.id
                    initialAssistantMessageId = messages
                        .firstOrNull { it.role == AgentMessageRole.ASSISTANT }?.id
                    initialOpeningEntryPoint = entryPoint
                    initialOpeningPrompts.enqueue(messages, entryPoint)
                    _messages.clear()
                    _messages.addAll(messages)
                    notifyLoaded()
                }
                setState(State.READY)
                enqueueInitialOpeningPrompt()
                sendNextPending()
                hintsJob?.cancel()
                hintsJob = scope.launch { loadHints() }
            } else {
                finishClearFailure()
            }
            notifySessionIdle()
        }
    }

    // The limits arrive as updates
    private fun loadLimits() {
        scope.launch {
            try {
                client.loadAvailability()
                client.loadUserQuota()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Without them, questions go out and the server tells about any limit
            }
        }
    }

    // Lets the screen block or unblock the composer, and again when the nearest limit resets
    private fun onLimitsChanged() {
        limitExpiryJob?.cancel()
        val now = now()
        if (limitRetry?.expiresAt?.let { it <= now } == true) limitRetry = null
        notifyDelegates { it.onInputLimitChanged() }
        notifyFollowupsAndHints()
        val nextReset = listOfNotNull(
            availability?.resetAt,
            userQuota?.resetAt?.let(::parseAgentV2Timestamp)?.time,
            limitRetry?.resetAt,
            limitRetry?.expiresAt
        ).filter { it > now }.minOrNull() ?: return
        limitExpiryJob = scope.launch {
            delay(nextReset - now)
            limitExpiryJob = null
            onLimitsChanged()
        }
    }

    /** Asks whether the server takes problem reports */
    private fun refreshProblemReportAvailability(): Job {
        problemReportAvailabilityJob?.cancel()
        return scope.launch {
            val isAvailable = try {
                client.problemReportAvailability()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                false
            }
            val couldReport = canReportProblem
            problemReportAvailability = isAvailable
            if (canReportProblem != couldReport) {
                notifyDelegates { it.onProblemReportAvailabilityChanged() }
            }
        }.also { problemReportAvailabilityJob = it }
    }

    /** Whether the server takes problem reports, asking it while its check hasn't answered */
    private suspend fun awaitProblemReportAvailability(): Boolean {
        repeat(PROBLEM_REPORT_CHECK_ATTEMPTS) {
            problemReportAvailability?.let { return it }
            // The check under way, or a new one when that ended without an answer
            val availabilityCheck = problemReportAvailabilityJob?.takeIf { it.isActive }
                ?: refreshProblemReportAvailability()
            availabilityCheck.join()
        }
        return problemReportAvailability ?: false
    }

    // The user's consent decides whether the chat offers problem reports
    private fun updateConsent(isAllowed: Boolean) {
        val couldReport = canReportProblem
        hasConsent = isAllowed
        if (canReportProblem != couldReport) {
            notifyDelegates { it.onProblemReportAvailabilityChanged() }
        }
    }

    /**
     * Reports the answer shown as [presentationId], or the whole conversation when it is null. A report sent before the
     * server's check has answered waits for it, and fails when the server takes no reports.
     */
    fun reportProblem(presentationId: String?, comment: String?, onResult: (Boolean) -> Unit) {
        val threadId = thread.id
        val messageId = presentationId?.let { resolveAgentReportMessageId(_messages, it) }
        if (presentationId != null && messageId == null) {
            onResult(false)
            return
        }
        // The session outlives the screen until the report settles; see `shouldRetainSession`.
        // The job is tracked before it starts, so its own removal can never come first.
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val isSent = try {
                if (awaitProblemReportAvailability()) {
                    client.reportProblem(threadId, messageId, comment)
                    true
                } else {
                    false
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // A server that has switched reports off refuses them, and asking again takes the entry points away
                refreshProblemReportAvailability().join()
                false
            } finally {
                problemReportJobs.remove(currentCoroutineContext().job)
            }
            onResult(isSent)
            notifySessionIdle()
        }
        problemReportJobs += job
        job.start()
    }

    /**
     * Sets the rating of the complete answer shown as [presentationId], or withdraws it when [feedback] is null.
     * The rating shows at once; [onSaved] runs once the server keeps it, and a failed save shows the rating the server
     * keeps again and calls [onFailure]. Neither runs for a rating that a later one replaced.
     */
    fun rateMessage(
        presentationId: String,
        feedback: AgentAnswerFeedback?,
        onSaved: () -> Unit,
        onFailure: () -> Unit
    ) {
        val threadId = thread.id
        val message = _messages.firstOrNull { it.matchesMessageId(presentationId) } ?: return
        val messageId = message.sdkMessageId ?: return
        if (!message.isComplete || message.newsPost) return
        val request = FeedbackRequest(feedback)
        val requests = feedbackRequests.getOrPut(messageId) {
            FeedbackRequests(latest = request, saved = message.feedback)
        }
        requests.latest = request
        applyFeedback(messageId, feedback)
        scope.launch {
            val isSaved = try {
                requests.saved = AgentAnswerFeedback.fromWireValue(
                    client.setMessageFeedback(threadId, messageId, feedback?.wireValue).feedback
                )
                true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                false
            }
            if (requests.latest !== request) return@launch
            feedbackRequests.remove(messageId)
            applyFeedback(messageId, requests.saved)
            if (!isSaved) {
                onFailure()
            } else if (requests.saved == feedback) {
                onSaved()
            }
        }
    }

    /**
     * The rating requests of one answer: [latest] settles the rating, and the SDK sends an answer's requests in
     * order, so it settles last. [saved] is the rating the server keeps after the requests settled so far.
     */
    private class FeedbackRequests(var latest: FeedbackRequest, var saved: AgentAnswerFeedback?)

    private class FeedbackRequest(val feedback: AgentAnswerFeedback?)

    /**
     * The server's [messages] with each stopped answer as it showed while the server holds less of its text, and with
     * the server's answer once it holds as much
     */
    private fun withStoppedAnswers(messages: List<AgentMessage>): List<AgentMessage> {
        val awaitingAdmissionIds = activeRun?.takeUnless { it.isEditAdmitted }
            ?.replacedStoppedAnswerIds.orEmpty()
        return messages.map { message ->
            val sdkMessageId = message.sdkMessageId?.takeUnless(awaitingAdmissionIds::contains)
                ?: return@map message
            val stopped = stoppedAnswers[sdkMessageId] ?: return@map message
            if (message.text.trim().length >= stopped.text.trim().length) {
                stoppedAnswers.remove(sdkMessageId)
                message
            } else {
                stopped.copy(id = message.id)
            }
        }
    }

    /**
     * An older [page] with each stopped answer it lacks after its question, the page's last user message no later than
     * the answer. An answer [newerMessages] hold, or whose question they hold, stays out; one whose question is on an
     * older page waits for it.
     */
    private fun withLeftOutStoppedAnswers(
        page: List<AgentMessage>,
        newerMessages: List<AgentMessage>
    ): List<AgentMessage> = stoppedAnswers.entries.sortedBy { it.value.date }
        .fold(page) { messages, (sdkMessageId, stopped) ->
            fun isQuestion(message: AgentMessage) =
                message.role == AgentMessageRole.USER && !message.date.after(stopped.date)
            if (messages.any { it.matchesMessageId(sdkMessageId) } ||
                newerMessages.any { it.matchesMessageId(sdkMessageId) || isQuestion(it) }
            ) {
                return@fold messages
            }
            val question = messages.indexOfLast(::isQuestion)
            if (question < 0) {
                messages
            } else {
                messages.take(question + 1) + stopped + messages.drop(question + 1)
            }
        }

    /** History carries the rating the server keeps; a rating still being saved shows over it */
    private fun withPendingFeedback(messages: List<AgentMessage>) = messages.map { message ->
        val requests = message.sdkMessageId?.let(feedbackRequests::get)
        requests?.let { message.copy(feedback = it.latest.feedback) } ?: message
    }

    /**
     * Shows [feedback] on the answer with the server id [messageId], also in the history that a
     * failed clear restores
     */
    private fun applyFeedback(messageId: String, feedback: AgentAnswerFeedback?) {
        clearIntent?.let { intent ->
            intent.fallbackMessages = intent.fallbackMessages.map { message ->
                val isRated = message.sdkMessageId == messageId
                if (isRated) message.copy(feedback = feedback) else message
            }
        }
        val message = _messages.firstOrNull { it.matchesMessageId(messageId) } ?: return
        if (message.feedback == feedback) return
        replaceMessage(message.copy(feedback = feedback))
        notifyDelegates { it.onStreamingUpdate(message.id) }
    }

    fun sendMessage(text: String, entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()): Boolean {
        if (isDeletingChat || hasUnsentOpening || isInputBlockedByLimit) return false
        val normalized = normalizeAgentMessageText(text)
        if (normalized.isEmpty()) return false
        val authority = hostContextProvider.captureMessageAuthority() ?: return false
        val shouldSendNow = canSendNow()
        val canRecoverHostContext = hostContextProvider.canRecoverAuthorityContext()
        if (
            !shouldAcceptAgentMessage(
                state,
                shouldSendNow,
                canRecoverHostContext,
                clearIntent != null
            )
        ) {
            return false
        }
        acceptMessage(
            normalized,
            entryPoint.takeUnless {
                thread.hasPost
            },
            null,
            authority,
            shouldSendNow
        )
        return true
    }

    /**
     * Stops the answer the chat is waiting for and frees the chat at once: the text shown so far stays, without a
     * rating or suggestions, and the next queued question goes. The SDK cancels the run on the server itself.
     */
    fun stopAnswer() {
        if (state != State.RUNNING || clearIntent != null || isDeletingChat) return
        val run = activeRun ?: return
        if (run === runStartedByStop && run.runId == null) return
        val threadId = thread.id
        // Reaches the SDK before the next queued question starts its run
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                client.stopRun(threadId)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                Unit
            }
        }
        val job = operationJob
        operationJob = null
        job?.cancel()
        keepStoppedAnswer(run)
        resetActiveRunState()
        setState(State.READY)
        sendNextPending()
        runStartedByStop = activeRun
        if (state == State.READY) {
            scope.launch { hostContextProvider.flushDeferredDynamicUpdate() }
        }
        notifySessionIdle()
    }

    fun canEditMessage(messageId: String): Boolean = canSendFollowup &&
        _messages.any {
            it.matchesMessageId(messageId) && it.role == AgentMessageRole.USER &&
                it.sdkMessageId != null && !it.newsPost
        }

    fun canRegenerateMessage(messageId: String): Boolean = canSendFollowup &&
        _messages.any {
            it.matchesMessageId(messageId) && it.role == AgentMessageRole.ASSISTANT &&
                it.sdkMessageId != null && !it.isStreaming && !it.newsPost
        }

    fun regenerateMessage(messageId: String): Boolean {
        if (!canRegenerateMessage(messageId)) return false
        val message = _messages.first { it.matchesMessageId(messageId) }
        val authority = hostContextProvider.captureMessageAuthority() ?: return false
        historyJob?.cancel()
        historyJob = null
        sendNow(
            AgentPendingMessage(
                message,
                null,
                authority,
                targetAssistantMessageId = message.sdkMessageId,
                replacedStoppedAnswerIds = findStoppedAnswerIdsFrom(messageId)
            )
        )
        return true
    }

    // An answer asked again, or one after an edited question, is no longer the answer the user stopped
    private fun findStoppedAnswerIdsFrom(messageId: String): Set<String> {
        val index = _messages.indexOfFirst { it.matchesMessageId(messageId) }
        if (index < 0) return emptySet()
        return _messages.drop(index)
            .mapNotNull { it.sdkMessageId }
            .filter(stoppedAnswers::containsKey)
            .toSet()
    }

    fun editMessage(messageId: String, text: String): Boolean {
        val normalized = text.trim()
        if (normalized.isEmpty() || !canEditMessage(messageId)) return false
        val message = _messages.first { it.matchesMessageId(messageId) }
        if (normalized == message.text.trim()) return true
        val authority = hostContextProvider.captureMessageAuthority() ?: return false
        val prefix = agentMessagesBeforeEdit(_messages, messageId) ?: return false
        val fallbackMessages = _messages.toList()
        historyJob?.cancel()
        historyJob = null
        val replacedStoppedAnswerIds = findStoppedAnswerIdsFrom(messageId)
        val editedMessage = message.copy(
            id = "local-${UUID.randomUUID()}",
            text = normalized,
            date = Date()
        )
        _messages.clear()
        _messages.addAll(prefix)
        notifyDelegates { it.onMessagesTruncated(fallbackMessages.drop(prefix.size)) }
        _messages.add(editedMessage)
        notifyDelegates { it.onMessageAdded(editedMessage) }
        sendNow(
            AgentPendingMessage(
                editedMessage,
                null,
                authority,
                targetUserMessageId = message.sdkMessageId,
                editFallbackMessages = fallbackMessages,
                replacedStoppedAnswerIds = replacedStoppedAnswerIds
            )
        )
        return true
    }

    fun visibleFollowups(messageId: String): List<AgentV2FollowUp> = _messages
        .findFollowupOwner()
        ?.takeIf {
            !isChatWithSupport && it.matchesMessageId(messageId) &&
                (!it.newsPost || state == State.READY)
        }
        ?.followups
        .orEmpty()

    fun sendFollowup(messageId: String, followupId: String): Boolean {
        if (!canSendFollowup) return false
        val message = _messages.findFollowupOwner()
            ?.takeIf { it.matchesMessageId(messageId) && !it.isStreaming }
            ?: return false
        val sdkMessageId = message.sdkMessageId ?: return false
        val followup = message.followups.firstOrNull { it.id == followupId } ?: return false
        val authority = hostContextProvider.captureMessageAuthority() ?: return false
        acceptMessage(
            followup.text,
            null,
            AgentV2FollowUpReference(sdkMessageId, followup.id),
            authority,
            shouldSendNow = true
        )
        return true
    }

    private fun acceptMessage(
        text: String,
        entryPoint: AgentV2EntryPoint?,
        followupOf: AgentV2FollowUpReference?,
        authority: AgentV2AuthorityBinding,
        shouldSendNow: Boolean
    ) {
        val previousFollowupOwner = _messages.findFollowupOwner()
        val localMessage = AgentMessage(
            id = "local-${UUID.randomUUID()}",
            role = AgentMessageRole.USER,
            text = text
        )
        _messages.add(localMessage)
        previousFollowupOwner?.takeIf { it.followups.isNotEmpty() }?.let { message ->
            notifyDelegates { it.onFollowupsChanged(message.id) }
        }
        notifyDelegates { it.onMessageAdded(localMessage) }
        val pendingMessage = AgentPendingMessage(localMessage, entryPoint, authority, followupOf)
        if (!shouldSendNow) {
            pendingMessages.add(pendingMessage)
            when (state) {
                State.ERROR -> retry()
                State.READY -> sendNextPending()
                else -> Unit
            }
            notifyHints()
            return
        }
        sendNow(pendingMessage)
        notifyHints()
    }

    fun hintEntryPoint(hint: AgentHint) = AgentV2EntryPoint(
        kind = "emptyState",
        surface = "agentTab",
        hintId = hint.id,
        catalogVersion = hintsCatalogVersion
    )

    /** Reads the consent again, which the user may have given elsewhere since the chat read it; a failed read is none */
    internal suspend fun readConsent(): Boolean = try {
        client.consent()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        false
    }

    /**
     * The user allowed the Agent, in the consent sheet or elsewhere, as [readConsent] found. A news discussion loaded
     * before consent only learns it, as it is stored already; a chat waiting for consent stores it and loads.
     */
    fun acceptConsent() {
        if (state != State.CONSENT_REQUIRED) {
            if (state != State.ACCEPTING_CONSENT && hasConsent != true) {
                updateConsent(true)
                chatActivity.setConsentAccepted(true)
                refreshProblemReportAvailability()
                loadLimits()
            }
            return
        }
        if (startupJob?.isActive == true) return
        setState(State.ACCEPTING_CONSENT)
        startupJob = scope.launch {
            try {
                client.acceptConsent()
                updateConsent(true)
                initializeConversation()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                setState(State.CONSENT_REQUIRED)
                notifyErrorEvent()
            } finally {
                startupJob = null
            }
        }
    }

    fun performAction(messageId: String, actionId: String) {
        if (state != State.READY || operationJob?.isActive == true || actionJob?.isActive == true) {
            return
        }
        val authority = hostContextProvider.captureActionAuthority()
        if (authority == null) {
            notifyActionUnavailable()
            return
        }
        val sdkMessageId = _messages.firstOrNull { it.matchesMessageId(messageId) }
            ?.sdkMessageId
            ?: messageId
        actionJob = scope.launch {
            try {
                val action = client.resolveAction(sdkMessageId, actionId)
                currentCoroutineContext().ensureActive()
                if (hostContextProvider.isActionAuthorityCurrent(authority)) {
                    openResolvedAction(action, authority)
                } else {
                    notifyActionUnavailable()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                notifyActionUnavailable()
            } finally {
                if (actionJob === currentCoroutineContext().job) actionJob = null
                notifyFollowupsAndHints()
            }
        }
        notifyFollowupsAndHints()
    }

    val isLoadingOlderMessages: Boolean get() = historyJob?.isActive == true

    fun loadOlderMessages() {
        if (activeRun?.editedMessage != null || activeRun?.regenerationTargetId != null) return
        // The history's cursor comes before the history replaces the device's copy
        if (historyJob?.isActive == true || cachedMessageIds.isNotEmpty()) return
        val currentThread = thread
        val cursor = historyCursor ?: return
        if (thread.support != null) {
            if (refreshJob?.isActive == true) shouldRefreshSupportHistory = true
            refreshJob?.cancel()
            refreshJob = null
        }
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val owner = currentCoroutineContext().job
            try {
                val hydration = client.messages(currentThread.id, cursor, MESSAGE_PAGE_SIZE)
                currentCoroutineContext().ensureActive()
                if (historyJob !== owner) return@launch
                check(hydration.thread.id == currentThread.id) { "Unexpected Agent thread" }
                val nextCursor = hydration.nextCursor
                check(nextCursor == null || seenHistoryCursors.add(nextCursor)) {
                    "Repeated Agent message cursor"
                }
                hasLoadedHistoryMessages = hasLoadedHistoryMessages || hasAgentThreadHistory(
                    hydration.thread,
                    emptyList(),
                    hydration.messages
                )
                if (hydration.thread.revision > currentRevision() ||
                    thread.support == currentThread.support ||
                    hydration.thread.support == thread.support
                ) {
                    bindThread(hydration.thread)
                }
                if (historyJob !== owner) return@launch
                historyCursor = nextCursor

                val existingIds = _messages.mapTo(mutableSetOf()) {
                    it.sdkMessageId ?: it.id
                }
                val pageMessages = withLeftOutStoppedAnswers(
                    withStoppedAnswers(nativeMessages(hydration.messages)),
                    _messages
                )
                val olderMessages = pageMessages.filter { message ->
                    val sdkMessageId = message.sdkMessageId ?: message.id
                    existingIds.add(sdkMessageId)
                }
                currentCoroutineContext().ensureActive()
                if (historyJob !== owner) return@launch
                if (olderMessages.isNotEmpty()) {
                    _messages.addAll(0, olderMessages)
                    pageMessages.mapNotNullTo(loadedHistoryMessageIds) { it.sdkMessageId }
                    notifyPrepended()
                } else if (thread.hasPost && nextCursor == null) {
                    notifyLoaded()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                if (historyJob === owner) notifyErrorEvent()
            } finally {
                if (historyJob === owner) historyJob = null
                updateSupportPolling()
                notifyDelegates { it.onOlderMessagesLoadingChanged() }
                notifySessionIdle()
            }
        }
        historyJob = job
        updateSupportPolling()
        job.start()
        notifyDelegates { it.onOlderMessagesLoadingChanged() }
    }

    internal suspend fun transcribeAudio(audio: String) = client.transcribe(
        AgentV2TranscriptionRequest(audio = audio, lang = LocaleController.activeLanguage.langCode)
    )

    override fun onBridgeUpdate(update: ApiUpdate) {
        val agentUpdate = (update as? ApiUpdate.ApiUpdateAgentV2)?.update ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            handle(agentUpdate)
        } else {
            scope.launch { handle(agentUpdate) }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AppBackground -> {
                isInBackground = true
                chatActivity.setInBackground(true)
                updateSupportPolling()
            }

            WalletEvent.AppForeground -> {
                isInBackground = false
                chatActivity.setInBackground(false)
                if (isChatWithSupport || hasFailedSupportRefresh) shouldRefreshSupportHistory = true
                updateSupportPolling()
            }

            // The copy belongs to the previous wallet's Agent identity; the reset handles the loaded messages
            WalletEvent.AccountsReset -> {
                cacheReadJob?.cancel()
                cacheReadJob = null
                discardCachedMessages()
            }

            else -> Unit
        }
    }

    fun onDestroy() {
        supportPollingJob?.cancel()
        refreshJob?.cancel()
        resetActiveRunState()
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        WalletCore.unregisterObserver(this)
        chatActivity.stop()
        cancelPendingAction()
        historyJob?.cancel()
        historyJob = null
        cancelHostContextRecovery()
        hostContextProvider.stop()
        scope.cancel()
        delegates.clear()
        activeDelegates.clear()
    }

    private fun start() {
        if (isDeletingChat || startupJob?.isActive == true) return
        startupErrorCode = null
        limitRetry = null
        actionAvailability.invalidate()
        setState(State.LOADING)
        startupJob = scope.launch {
            try {
                // The sheet may have stored the consent while this read it
                updateConsent(client.consent() || hasConsent == true)
                // A news discussion reads its thread and post without consent; what it sends asks for consent first
                val canLoad =
                    hasConsent == true ||
                        (thread.hasPost && clearIntent == null)
                when (agentConsentLoadAction(canLoad, clearIntent != null)) {
                    AgentConsentLoadAction.INITIALIZE -> initializeConversation()

                    AgentConsentLoadAction.REQUIRE_CONSENT -> {
                        chatActivity.setConsentAccepted(false)
                        // Chats open with their copies only after the SDK confirms consent
                        cachedHistories.clear()
                        discardCachedMessages()
                        setState(State.CONSENT_REQUIRED)
                    }

                    AgentConsentLoadAction.RESTORE_CLEAR_AND_REQUIRE_CONSENT -> {
                        chatActivity.setConsentAccepted(false)
                        cachedHistories.clear()
                        discardCachedMessages()
                        restoreQueuedClearWithoutConsent()
                        setState(State.CONSENT_REQUIRED)
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (error: Throwable) {
                failStartup(error)
            } finally {
                startupJob = null
                updateSupportPolling()
                notifySessionIdle()
            }
        }
    }

    private suspend fun initializeConversation() {
        chatActivity.setConsentAccepted(hasConsent == true)
        check(hostContextProvider.start()) { "Host context is unavailable" }
        hydrate()
        refreshProblemReportAvailability()
        loadLimits()
        if (clearIntent != null) {
            launchPendingClear()
            return
        }
        setState(State.READY)
        enqueueInitialOpeningPrompt()
        hintsJob?.cancel()
        hintsJob = scope.launch { loadHints() }
        sendNextPending()
        notifySessionIdle()
    }

    /**
     * Loads the thread's newest page. A kept chat refreshing takes that page as its history, so older pages load again
     * by scrolling; other loads merge it into the messages shown.
     */
    private suspend fun hydrate(isKeptChatRefresh: Boolean = false) {
        val startingSupport = thread.support
        val loadMessages: suspend (String) -> AgentV2ThreadHydration = { threadId ->
            client.messages(threadId, null, MESSAGE_PAGE_SIZE)
        }
        val threadId = thread.id
        val cacheJob = if (canReadCachedMessages() && canApplyCachedMessages()) {
            scope.launch { showCachedMessages(threadId) }.also { cacheReadJob = it }
        } else {
            null
        }
        val hydration = try {
            if (initialOpeningEntryPoint != null) {
                hydrateAgentOpeningThread(thread, loadMessages)
            } else {
                hydrateAgentThread(thread, loadMessages)
            }
        } catch (error: AgentV2OperationException) {
            if (error.error.code == AGENT_THREAD_NOT_FOUND) {
                cachedHistories.remove(threadId)
                discardCachedMessages()
            }
            throw error
        } finally {
            // Any end of the history request makes the device's copy outdated
            cacheJob?.cancel()
            if (cacheReadJob === cacheJob) cacheReadJob = null
        }
        historyJob?.cancel()
        historyJob = null
        hasLoadedHistoryMessages = hasAgentThreadHistory(
            hydration.thread,
            emptyList(),
            hydration.messages
        )
        if (initialOpeningEntryPoint != null && hasLoadedHistoryMessages) {
            initialOpeningEntryPoint = null
            initialOpeningPrompts.clear()
            _messages.removeAll {
                it.id == initialOpeningMessageId || it.id == initialAssistantMessageId
            }
            initialAssistantMessageId = null
        }
        if (hydration.thread.revision > currentRevision() || thread.support == startingSupport ||
            hydration.thread.support == thread.support
        ) {
            bindThread(hydration.thread, isLatestHistory = true, hasHistory = true)
        }
        historyCursor = hydration.nextCursor
        seenHistoryCursors.clear()
        hydration.nextCursor?.let(seenHistoryCursors::add)
        if (clearIntent != null) return
        cachedHistories.storeLoadedPage(
            hydration.thread,
            hydration.messages,
            hasOlder = hydration.nextCursor != null
        )
        val hydratedMessages = withStoppedAnswers(nativeMessages(hydration.messages))
        val shownMessages = _messages.filterNot { it.id in cachedMessageIds }
        val reconciledMessages = withPendingFeedback(
            if (isKeptChatRefresh) {
                refreshAgentMessages(shownMessages, hydratedMessages, stoppedAnswers.keys)
            } else {
                reconcileAgentMessages(shownMessages, hydratedMessages)
            }
        )
        _messages.clear()
        _messages.addAll(reconciledMessages)
        cachedMessageIds = emptySet()
        loadedHistoryMessageIds.clear()
        hydratedMessages.mapNotNullTo(loadedHistoryMessageIds) { it.sdkMessageId }
        loadedOperatorMessageAt = hydration.thread.support?.lastOperatorMessageAt
        if (hydration.thread.revision >= currentRevision() &&
            hydration.thread.support == thread.support
        ) {
            shouldRefreshSupportHistory = false
            hasFailedSupportRefresh = false
        }
        hasHydratedMessages = true
        if (_messages.isEmpty()) scrollPosition = ScrollPosition(ScrollAnchor.Bottom)
        notifyLoaded()
    }

    /** Shows the SDK's copy of the thread's latest messages while its history loads, in a chat that shows nothing yet */
    private suspend fun showCachedMessages(threadId: String) {
        val cached = try {
            client.getCachedMessages(threadId)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            null
        }
        currentCoroutineContext().ensureActive()
        if (cached != null && canApplyCachedMessages()) applyCachedMessages(cached)
    }

    private fun canReadCachedMessages() = canShowCachedMessages &&
        initialOpeningEntryPoint == null && !thread.hasPost && thread.messageCount > 0

    /**
     * The copy offers nothing to act on: its actions and suggestions show inactive, its actions load no presentations,
     * and its messages come without rating and without a cursor to load older ones
     */
    private fun applyCachedMessages(cached: AgentV2CachedMessages) {
        if (cached.thread.id != thread.id || cached.thread.hasPost) return
        val messages = cached.messages.mapNotNull { message ->
            mapAgentV2Message(message)?.copy(isComplete = false)
        }
        if (messages.isEmpty()) return
        if (messages.any { it.links.isNotEmpty() }) publishesAnswerLinks = true
        _messages.addAll(messages)
        cachedMessageIds = messages.mapTo(mutableSetOf()) { it.id }
        notifyLoaded()
    }

    /** Whether the message belongs to the device's copy of the history, whose actions and suggestions are inactive */
    internal fun isCachedMessage(messageId: String) = messageId in cachedMessageIds

    private fun canApplyCachedMessages() = !isDeletingChat && clearIntent == null &&
        !hasHydratedMessages && activeRun == null && _messages.isEmpty()

    private fun discardCachedMessages() {
        if (cachedMessageIds.isEmpty()) return
        _messages.removeAll { it.id in cachedMessageIds }
        cachedMessageIds = emptySet()
        notifyLoaded()
    }

    private fun enqueueInitialOpeningPrompt() {
        if (isDeletingChat || (state != State.READY && state != State.RUNNING) ||
            clearIntent != null
        ) {
            return
        }
        initialOpeningPrompts.submit(
            { messages, entryPoint ->
                val message = messages.first { it.role == AgentMessageRole.USER }
                val assistant = messages.first { it.role == AgentMessageRole.ASSISTANT }
                val authority = hostContextProvider.captureMessageAuthority()
                    ?: return@submit false
                initialOpeningEntryPoint = null
                pendingMessages.add(
                    AgentPendingMessage(
                        message,
                        entryPoint,
                        authority,
                        assistantMessageId = assistant.id
                    )
                )
                true
            },
            state
        )
    }

    private suspend fun loadHints() {
        if (thread.hasPost) return
        availableHints = try {
            val response = client.hints(LocaleController.activeLanguage.langCode)
            hintsCatalogVersion = response.catalogVersion
            response.items.mapNotNull { hint ->
                localizedAgentV2Hint(hint.id)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            hintsCatalogVersion = null
            emptyList()
        }
        notifyHints()
    }

    private suspend fun failStartup(error: Throwable) {
        if (clearIntent != null) {
            finishClearFailure(canReturnToReady = false)
            return
        }
        startupErrorCode = (error as? AgentV2OperationException)?.error?.code
        val text = when (startupErrorCode) {
            "client_update_required", "device_token_missing", "device_token_invalid",
            "device_token_expired", "profile_id_invalid", "profile_deleted", "network_error",
            "invalid_event" -> agentV2ErrorText(startupErrorCode)

            else -> LocaleController.getString("Failed to load chat")
        }
        hideCachedFollowups()
        appendUnavailable(text = text)
        setState(State.ERROR)
    }

    /** Under the failure, the device's copy shows no suggestions, which return with the history Retry loads */
    private fun hideCachedFollowups() {
        if (_messages.none { it.id in cachedMessageIds && it.followups.isNotEmpty() }) return
        _messages.forEachIndexed { index, message ->
            if (message.id !in cachedMessageIds) return@forEachIndexed
            _messages[index] = message.copy(followups = emptyList())
        }
        notifyLoaded()
    }

    private fun sendNow(pendingMessage: AgentPendingMessage) {
        val localMessage = pendingMessage.message
        if (!hostContextProvider.isMessageAuthorityCurrent(pendingMessage.authority)) {
            notifyPendingMessageFailed(pendingMessage)
            sendNextPending()
            return
        }
        val currentThread = thread
        if (!canSendNow()) {
            pendingMessages.add(0, pendingMessage)
            requestHostContextRecovery()
            return
        }

        val run = AgentActiveRun(
            UUID.randomUUID().toString(),
            localMessage.id,
            pendingMessage.authority,
            canResendSupportConflict = isChatWithSupport &&
                pendingMessage.targetUserMessageId == null &&
                pendingMessage.targetAssistantMessageId == null,
            editedMessage = localMessage.takeIf { pendingMessage.targetUserMessageId != null },
            editFallbackMessages = pendingMessage.editFallbackMessages,
            regenerationTargetId = pendingMessage.targetAssistantMessageId,
            replacedStoppedAnswerIds = pendingMessage.replacedStoppedAnswerIds
        )
        removeStoppingAnswer()
        activeRun = run
        if (run.regenerationTargetId == null) {
            run.assistantPresentationId = pendingMessage.assistantMessageId
                ?.takeIf { id -> _messages.any { it.id == id } }
                ?: addAssistantPlaceholder()
            initialAssistantMessageId = null
        }
        // A new question takes the place of one a limit held back
        limitRetry = null
        setState(State.RUNNING)
        launchRun(run) {
            client.startRun(
                clientRunId = run.clientRunId,
                threadId = currentThread.id,
                revision = currentRevision(),
                text = localMessage.text,
                entryPoint = pendingMessage.entryPoint,
                followupOf = pendingMessage.followupOf,
                targetUserMessageId = pendingMessage.targetUserMessageId,
                targetAssistantMessageId = pendingMessage.targetAssistantMessageId
            )
        }
    }

    /** Sends again the question a limit held back, as the same run, once the limit has reset */
    fun retryLimit() {
        val retry = limitRetry ?: return
        if (!canRetryLimit) return
        val authority = hostContextProvider.captureMessageAuthority() ?: return
        val inputPresentationId = retry.inputPresentationId ?: return
        limitRetry = null
        retry.failureMessageId?.let(::removeMessage)
        val run = AgentActiveRun(
            retry.clientRunId,
            inputPresentationId,
            authority,
            editedMessage = retry.editedMessage,
            editFallbackMessages = retry.editFallbackMessages,
            regenerationTargetId = retry.regenerationTargetId,
            replacedStoppedAnswerIds = retry.replacedStoppedAnswerIds
        )
        // The failed edit restored server history, so its local question needs the canonical replacement
        run.shouldResyncThread = run.editedMessage != null
        removeStoppingAnswer()
        activeRun = run
        if (run.regenerationTargetId == null) {
            run.assistantPresentationId = addAssistantPlaceholder()
        }
        setState(State.RUNNING)
        // Without the held run, the question fails as a plain failure
        launchRun(run) { client.retryRun(retry.clientRunId) }
    }

    /** Follows [run], which [start] starts, and shows how it ends */
    private fun launchRun(run: AgentActiveRun, start: suspend () -> AgentV2RunResult?) {
        refreshJob?.cancel()
        val threadId = thread.id
        operationJob = scope.launch {
            var hasFailed = false
            try {
                check(hostContextProvider.flushPendingUpdateBeforeRun()) {
                    "agent_host_context_update_failed"
                }
                if (activeRun !== run) return@launch
                check(hostContextProvider.isMessageAuthorityCurrent(run.authority)) {
                    "agent_wallet_authority_changed"
                }
                currentCoroutineContext().ensureActive()
                if (isDeletingChat) return@launch
                var result = start()
                if (activeRun !== run) return@launch
                if (run.shouldResendSupportConflict && result != null &&
                    result.clientRunId == run.clientRunId && result.runId == null &&
                    result.state != "cancelled" && clearIntent == null
                ) {
                    val hasRefreshed = refreshLatestSupportMessages(run)
                    if (activeRun !== run) return@launch
                    val shouldResend = hasRefreshed && run.shouldResendSupportConflict &&
                        thread.id == threadId && clearIntent == null &&
                        hostContextProvider.isMessageAuthorityCurrent(run.authority)
                    run.shouldResendSupportConflict = false
                    if (shouldResend) {
                        run.hasFailed = false
                        run.failureCode = null
                        result = start()
                        if (activeRun !== run) return@launch
                    }
                }
                if (result != null && run.bind(result.clientRunId, result.runId)) {
                    if (result.runId != null) admitRun(run)
                    if (run.regenerationTargetId == null) {
                        bindInputSdkId(run.inputPresentationId, result.inputMessageId)
                    }
                    requestRunCancellation()
                    hasFailed = run.hasFailed || result.hasVisibleFailure
                } else {
                    hasFailed = true
                }
            } catch (e: CancellationException) {
                throw e
            } catch (error: Throwable) {
                hasFailed = true
                run.failureCode = (error as? AgentV2OperationException)?.error?.code
            } finally {
                if (operationJob === currentCoroutineContext().job) {
                    operationJob = null
                    notifyFollowupsAndHints()
                }
            }

            if (activeRun !== run) return@launch
            if (hasFailed) {
                removeEmptyAssistantPlaceholder()
            } else if (!run.hasStartedAssistant) {
                removeUnboundAssistantPlaceholder()
            }
            finalizeStreamingMessages()
            if (activeRun !== run) return@launch
            if (continuePendingClearAfterRun(run)) return@launch
            if (hasFailed || (!run.hasStartedAssistant && !run.hasDeliveredToSupport)) {
                notifyDelegates { it.onOutgoingMessageFailed(run.inputPresentationId) }
            }
            val failure = if (hasFailed) appendUnavailable(run.failureCode) else null
            run.limitRetry?.takeIf { hasFailed }?.let { retry ->
                limitRetry = retry.copy(
                    inputPresentationId = run.inputPresentationId,
                    failureMessageId = failure?.id,
                    editedMessage = run.editedMessage,
                    editFallbackMessages = run.editFallbackMessages,
                    regenerationTargetId = run.regenerationTargetId,
                    replacedStoppedAnswerIds = run.replacedStoppedAnswerIds
                )
                onLimitsChanged()
            }
            if (hasFailed && (
                    run.failureCode == AGENT_THREAD_REVISION_CONFLICT ||
                        run.editedMessage != null ||
                        (run.regenerationTargetId != null && run.isEditAdmitted)
                    )
            ) {
                run.shouldResyncThread = true
            }
            if (hasFailed && !run.isEditAdmitted) run.replacedStoppedAnswerIds = emptySet()
            val didRecoverThread = !run.shouldResyncThread || resyncThread(run, failure)
            if (activeRun !== run) return@launch
            if (continuePendingClearAfterRun(run)) return@launch
            if (!didRecoverThread) {
                resetActiveRunState()
                appendUnavailable()
                setState(State.ERROR)
                notifySessionIdle()
                return@launch
            }
            val didFlushHostContext = hostContextProvider.flushDeferredDynamicUpdate()
            if (activeRun !== run) return@launch
            if (continuePendingClearAfterRun(run)) return@launch
            if (!didFlushHostContext) {
                resetActiveRunState()
                appendUnavailable()
                setState(State.ERROR)
                notifySessionIdle()
                return@launch
            }
            resetActiveRunState()
            setState(State.READY)
            sendNextPending()
            notifySessionIdle()
        }
    }

    private fun sendNextPending() {
        enqueueInitialOpeningPrompt()
        val message = activateNextAgentPendingMessage(
            pendingMessages = pendingMessages,
            canStart = canSendNow(),
            isAuthorityCurrent = hostContextProvider::isMessageAuthorityCurrent,
            onInvalidated = ::notifyPendingMessageFailed,
            onActivated = { pendingMessage ->
                notifyDelegates { it.onPendingMessageActivated(pendingMessage.message.id) }
            }
        )
        if (message == null) {
            requestHostContextRecovery()
            return
        }
        sendNow(message)
    }

    private fun requestHostContextRecovery() {
        if (
            state != State.READY ||
            pendingMessages.isEmpty() ||
            hostContextRecoveryJob?.isActive == true ||
            !hostContextProvider.canRecoverAuthorityContext()
        ) {
            return
        }
        hostContextRecoveryJob = scope.launch {
            val didRecover = try {
                hostContextProvider.recoverAuthorityContext()
            } catch (e: CancellationException) {
                throw e
            } finally {
                if (hostContextRecoveryJob === currentCoroutineContext().job) {
                    hostContextRecoveryJob = null
                }
            }
            if (state != State.READY || pendingMessages.isEmpty()) {
                notifySessionIdle()
                return@launch
            }
            if (didRecover && hasCurrentAuthority()) {
                sendNextPending()
            } else {
                failPendingMessages()
                appendUnavailable()
                setState(State.ERROR)
            }
            notifySessionIdle()
        }
    }

    private fun canSendNow() = !isDeletingChat && state == State.READY &&
        operationJob?.isActive != true &&
        actionJob?.isActive != true &&
        hasCurrentAuthority()

    private fun hasCurrentAuthority() = hostContextProvider.captureActionAuthority() != null

    private fun bindActiveRun(clientRunId: String, runId: String?, threadId: String?): Boolean {
        if (!hasActiveRunOperation()) return false
        val currentThreadId = thread.id
        if (threadId != null && threadId != currentThreadId) return false
        return activeRun?.bind(clientRunId, runId) == true
    }

    private fun matchesActiveRun(clientRunId: String, runId: String, threadId: String): Boolean =
        hasActiveRunOperation() &&
            thread.id == threadId &&
            activeRun?.matches(clientRunId, runId) == true

    private fun hasActiveRunOperation() = activeRun?.inputPresentationId != null &&
        operationJob?.isActive == true &&
        (state == State.RUNNING || state == State.CLEARING)

    private suspend fun continuePendingClearAfterRun(run: AgentActiveRun): Boolean {
        if (clearIntent == null) return false
        cancellationJob?.join()
        if (activeRun !== run) return true
        resetActiveRunState()
        launchPendingClear()
        notifySessionIdle()
        return true
    }

    private fun handle(update: AgentV2Update) {
        val currentThreadId = thread.id
        when (update) {
            is AgentV2Update.RunStarted -> {
                if (!bindActiveRun(update.clientRunId, update.runId, update.threadId)) return
                revision = update.threadRevision
                activeRun?.let { run ->
                    // The SDK requires `run_start` before all other sequenced stream events
                    run.hasReceivedStreamEvent = true
                    admitRun(run)
                    if (run.regenerationTargetId == null) {
                        bindInputSdkId(run.inputPresentationId, update.inputMessageId)
                    }
                }
                requestRunCancellation()
            }

            is AgentV2Update.MessageStarted -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    update.contentKind !in setOf("markdown", "semantic") ||
                    clearIntent != null
                ) {
                    return
                }
                activeRun?.hasStartedAssistant = true
                val message = ensureAssistantMessage(update.messageId)
                replaceMessage(
                    message.copy(isAwaitingSemanticContent = update.contentKind == "semantic")
                )
            }

            is AgentV2Update.TextDelta -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                activeRun?.hasStartedAssistant = true
                val message = ensureAssistantMessage(update.messageId)
                val text = message.text + update.delta
                replaceMessage(message.copy(text = text))
                notifyDelegates { it.onStreamingUpdate(message.id) }
            }

            is AgentV2Update.AnswerTablesChanged -> {
                if (!matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                val message = ensureAssistantMessage(update.messageId)
                replaceMessage(
                    message.copy(
                        answerTables = update.tables,
                        tableReferences = update.tableReferences
                    )
                )
                notifyDelegates { it.onStreamingUpdate(message.id) }
            }

            is AgentV2Update.AnswerLinkAdded -> {
                if (!matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                // The link arrives before the text that carries its label
                publishesAnswerLinks = true
                val message = ensureAssistantMessage(update.messageId)
                replaceMessage(message.copy(links = message.links + update.link))
                notifyDelegates { it.onStreamingUpdate(message.id) }
            }

            is AgentV2Update.MessageContentEnded -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                finishMessageContent(update.messageId, shouldWaitForSemanticContent = true)
            }

            is AgentV2Update.MessageCompleted -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                if (update.finishReason == "delivered_to_support") {
                    activeRun?.let { run ->
                        run.hasDeliveredToSupport = true
                        bindInputSdkId(run.inputPresentationId, update.messageId)
                    }
                    removeUnboundAssistantPlaceholder()
                    finishMessageContent(update.messageId)
                    return
                }
                finishMessageContent(update.messageId)
                // An answer the agent finished without a client tool is still stored as complete
                if (update.finishReason == "complete" ||
                    update.finishReason == "tool_unavailable"
                ) {
                    val message = updateMessage(update.messageId) { it.copy(isComplete = true) }
                    message?.let {
                        notifyDelegates { delegate -> delegate.onStreamingUpdate(it.id) }
                    }
                }
            }

            is AgentV2Update.FollowupsAvailable -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                activeRun?.hasStartedAssistant = true
                val message = ensureAssistantMessage(update.messageId)
                if (message.followups == update.items) return
                replaceMessage(message.copy(followups = update.items))
                val shouldAnimate = message.followups.isEmpty() &&
                    visibleFollowups(message.id).isNotEmpty()
                notifyDelegates { it.onFollowupsChanged(message.id, shouldAnimate) }
                notifyHints()
            }

            is AgentV2Update.ActionAvailable -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                val authority = hostContextProvider.captureActionAuthority() ?: return
                scope.launch {
                    if (availableActions(update.messageId, listOf(update.action), authority)
                            .isNotEmpty()
                    ) {
                        addAvailableAction(update)
                    }
                }
            }

            is AgentV2Update.SemanticContentAvailable -> {
                if (
                    !matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    clearIntent != null
                ) {
                    return
                }
                activeRun?.hasStartedAssistant = true
                val message = ensureAssistantMessage(update.messageId)
                val text = agentV2SemanticText(update.content)
                replaceMessage(message.copy(text = text, isAwaitingSemanticContent = false))
                notifyDelegates { it.onStreamingUpdate(message.id) }
            }

            is AgentV2Update.RunFailed -> {
                if (!bindActiveRun(update.clientRunId, update.runId, update.threadId)) return
                val run = activeRun ?: return
                if (run.hasStartedAssistant) finalizeStreamingMessages()
                run.hasFailed = true
                run.failureCode = update.code
                if (run.canResendSupportConflict && update.code == "thread_revision_conflict" &&
                    update.runId == null && update.messageId == null &&
                    !run.hasReceivedStreamEvent && !run.isEditAdmitted
                ) {
                    run.canResendSupportConflict = false
                    run.shouldResendSupportConflict = true
                    return
                }
                run.limitRetry = update.toLimitRetry(run.hasReceivedStreamEvent, now())
                run.shouldResyncThread = run.shouldResyncThread ||
                    requiresAgentV2ThreadResync(update.code)
            }

            is AgentV2Update.RunCancelled -> {
                if (!matchesActiveRun(update.clientRunId, update.runId, update.threadId)) return
                if (activeRun?.hasStartedAssistant == true) finalizeStreamingMessages()
            }

            is AgentV2Update.WalletAuthorityChanged -> {
                if (update.threadId != null && update.threadId != currentThreadId) return
                invalidateAuthorityBoundActions()
                appendAccountChangeMarker()
            }

            is AgentV2Update.ThreadChanged -> {
                if (update.threadId == currentThreadId && update.thread.id == currentThreadId) {
                    bindThread(update.thread)
                }
            }

            is AgentV2Update.RuntimeReady -> chatActivity.onRuntimeReady()

            is AgentV2Update.RunActivityChanged -> {
                if (!matchesActiveRun(update.clientRunId, update.runId, update.threadId) ||
                    update.event.runId != update.runId ||
                    clearIntent != null
                ) {
                    return
                }
                val text = getAgentV2RunActivityText(update.event) ?: return
                val presentationId = activeRun?.assistantPresentationId ?: return
                val message = _messages.firstOrNull { it.matchesMessageId(presentationId) }
                    ?.takeIf { it.isStreaming && it.activityText != text }
                    ?: return
                replaceMessage(message.copy(activityText = text))
                notifyDelegates { it.onStreamingUpdate(message.id) }
            }

            is AgentV2Update.AvailabilityChanged -> {
                availability = update.availability
                onLimitsChanged()
            }

            is AgentV2Update.UserQuotaChanged -> {
                userQuota = update.quota
                onLimitsChanged()
            }

            is AgentV2Update.ToolActivityChanged,
            is AgentV2Update.WalletContextChanged -> Unit
        }
    }

    private fun admitRun(run: AgentActiveRun) {
        if (run.isEditAdmitted) return
        run.isEditAdmitted = true
        run.replacedStoppedAnswerIds.forEach(stoppedAnswers::remove)
        run.inputPresentationId?.let { id ->
            val message = _messages.firstOrNull { it.id == id }
            if (message?.role == AgentMessageRole.USER && message.isStreaming) {
                replaceMessage(message.copy(isStreaming = false))
                notifyDelegates { it.onStreamingUpdate(id) }
            }
        }
        val targetId = run.regenerationTargetId ?: return
        val retained = agentMessagesBeforeRegeneration(
            _messages,
            targetId,
            pendingMessages.map { it.message }
        ) ?: return
        for (removed in _messages.filterNot { it in retained }.asReversed()) {
            _messages.remove(removed)
            notifyDelegates { it.onMessageRemoved(removed.id) }
        }
        run.assistantPresentationId = addAssistantPlaceholder()
    }

    private fun ensureAssistantMessage(messageId: String): AgentMessage =
        findOrAddAssistantMessage(messageId).also { activeRun?.answerMessageIds?.add(it.id) }

    private fun findOrAddAssistantMessage(messageId: String): AgentMessage {
        _messages.firstOrNull { it.matchesMessageId(messageId) }?.let { return it }
        activeRun?.assistantPresentationId?.let { presentationId ->
            updateMessage(presentationId) { message ->
                message.copy(sdkMessageId = messageId)
            }?.let { return it }
        }
        val message = AgentMessage(
            id = messageId,
            sdkMessageId = messageId,
            role = AgentMessageRole.ASSISTANT,
            text = "",
            isStreaming = true
        )
        val index = activeRunOutputInsertionIndex(
            _messages,
            activeRun?.inputPresentationId,
            pendingMessages.map { it.message }
        )
        _messages.add(index, message)
        notifyDelegates { it.onMessageAdded(message) }
        return message
    }

    private fun addAssistantPlaceholder(): String {
        val message = AgentMessage(
            id = "local-${UUID.randomUUID()}",
            role = AgentMessageRole.ASSISTANT,
            text = "",
            isStreaming = true
        )
        val index = activeRunOutputInsertionIndex(
            _messages,
            activeRun?.inputPresentationId,
            pendingMessages.map { it.message }
        )
        _messages.add(index, message)
        notifyDelegates { it.onMessageAdded(message) }
        return message.id
    }

    private fun removeMessage(id: String) {
        val index = _messages.indexOfFirst { it.id == id }
        if (index < 0) return
        _messages.removeAt(index)
        notifyDelegates { it.onMessageRemoved(id) }
    }

    private fun removeUnboundAssistantPlaceholder() {
        val presentationId = activeRun?.assistantPresentationId ?: return
        val index = _messages.indexOfFirst { message ->
            message.id == presentationId && message.sdkMessageId == null
        }
        if (index < 0) return
        activeRun?.assistantPresentationId = null
        val message = _messages.removeAt(index)
        notifyDelegates { it.onMessageRemoved(message.id) }
        notifyHints()
    }

    private fun removeEmptyAssistantPlaceholder() {
        val presentationId = activeRun?.assistantPresentationId ?: return
        val index = _messages.indexOfFirst { message ->
            message.id == presentationId &&
                message.role == AgentMessageRole.ASSISTANT &&
                !message.hasText &&
                message.deeplinks.isEmpty() &&
                message.followups.isEmpty()
        }
        if (index < 0) return
        activeRun?.assistantPresentationId = null
        val message = _messages.removeAt(index)
        notifyDelegates { it.onMessageRemoved(message.id) }
        notifyHints()
    }

    private suspend fun nativeMessages(
        messages: List<AgentV2PersistedMessage>
    ): List<AgentMessage> {
        val authority = hostContextProvider.captureActionAuthority()
        val actionContext = actionAvailability.context
        val mapped = messages.mapNotNull { message ->
            val actions = availableActions(message.id, message.actions.orEmpty(), authority)
            // A stopped answer the server saved empty keeps its place, which `withStoppedAnswers` fills with its text
            mapAgentV2Message(message, actions)
                ?: stoppedAnswers[message.id]?.copy(
                    id = message.id,
                    sdkMessageId = message.id,
                    text = ""
                )
        }
        if (mapped.any { it.links.isNotEmpty() }) publishesAnswerLinks = true
        return if (actionContext === actionAvailability.context &&
            (authority == null || hostContextProvider.isActionAuthorityCurrent(authority))
        ) {
            mapped
        } else {
            mapped.map { it.copy(deeplinks = emptyList()) }
        }
    }

    private suspend fun availableActions(
        messageId: String,
        actions: List<AgentV2Action>,
        authority: AgentV2AuthorityBinding?
    ): List<AgentV2Action> {
        if (authority == null || !hostContextProvider.isActionAuthorityCurrent(authority)) {
            return emptyList()
        }
        val available = actionAvailability.filterAvailable(messageId, actions)
        return available.takeIf { hostContextProvider.isActionAuthorityCurrent(authority) }
            .orEmpty()
    }

    private fun addAvailableAction(update: AgentV2Update.ActionAvailable) {
        if (update.threadId != thread.id || clearIntent != null) return
        val message = updateMessage(update.messageId) { message ->
            val action = AgentDeeplink(
                title = update.action.title,
                actionId = update.action.id
            )
            message.copy(
                deeplinks = message.deeplinks.filterNot {
                    it.actionId == update.action.id
                } + action
            )
        }
        message?.let { updated ->
            notifyDelegates { it.onStreamingUpdate(updated.id) }
        }
    }

    private suspend fun openResolvedAction(
        action: AgentV2ResolvedAction,
        authority: AgentV2AuthorityBinding
    ) {
        if (action is AgentV2ResolvedAction.OpenDapp) {
            val delegate = liveDelegates(activeDelegates).lastOrNull() ?: return
            val site = suspendCancellableCoroutine<MExploreSite?> { continuation ->
                WalletCore.loadExploreSites { _, sites, _ ->
                    if (continuation.isActive) {
                        continuation.resume(
                            sites?.firstOrNull {
                                it.url == action.url &&
                                    it.canBeShown
                            }
                        )
                    }
                }
            }
            currentCoroutineContext().ensureActive()
            if (!hostContextProvider.isActionAuthorityCurrent(authority) ||
                delegate !in liveDelegates(activeDelegates)
            ) {
                return
            }
            if (site != null) delegate.onOpenDapp(site) else notifyActionUnavailable()
            return
        }
        if (action is AgentV2ResolvedAction.Inactive) {
            notifyActionUnavailable(action.reason)
            return
        }
        if (action is AgentV2ResolvedAction.OpenSwap &&
            listOfNotNull(action.tokenInSlug, action.tokenOutSlug).any {
                TokenStore.swapAssetsMap?.containsKey(it) != true
            }
        ) {
            notifyActionUnavailable()
            return
        }
        val url = buildAgentActionUrl(action)
        url?.let {
            WalletCore.notifyEvent(
                WalletEvent.OpenUrl(it, source = DeeplinkOpenSource.AGENT)
            )
        } ?: notifyActionUnavailable()
    }

    /** [hasHistory]: the thread comes with the newest messages, which the chat now holds */
    private fun bindThread(
        nextThread: AgentV2ThreadSummary,
        isLatestHistory: Boolean = false,
        hasHistory: Boolean = false
    ) {
        if (thread.id != nextThread.id) return
        if ((thread.support != null || nextThread.support != null) &&
            nextThread.revision < currentRevision()
        ) {
            return
        }
        val nextNews = nextThread.news
        val updatedThread = nextThread.copy(
            news = nextNews?.copy(
                body = nextNews.body ?: thread.news?.body,
                sources = nextNews.sources ?: thread.news?.sources
            ) ?: thread.news
        )
        val hasChanged = thread != updatedThread
        val hasSupportChanged = thread.support != updatedThread.support
        // A failed final read leaves the replies of a closed support chat to load
        val isSupportSummary = !hasHistory && (
            isChatWithSupport || hasFailedSupportRefresh ||
                updatedThread.support?.state.let { it == "waiting" || it == "operator" }
            )
        historyMessageCount = if (isSupportSummary) {
            // A summary confirms only the messages the chat holds
            minOf(
                updatedThread.messageCount,
                unloadedMessageCount +
                    _messages.count { it.sdkMessageId != null && it.supportEvent == null }
            )
        } else {
            updatedThread.messageCount
        }
        thread = updatedThread
        revision = updatedThread.revision
        if (hasSupportChanged) notifyFollowupsAndHints()
        if (hasChanged) notifyDelegates { it.onThreadChanged(updatedThread) }
        if (hasSupportChanged && !isLatestHistory) {
            requestSupportHistoryRefresh()
        } else {
            updateSupportPolling()
        }
    }

    /** Replaces the history with the server's; the [failure] shown for an edit or a regeneration stays after it */
    private suspend fun resyncThread(run: AgentActiveRun, failure: AgentMessage? = null): Boolean {
        val history = fetchCanonicalHistory()
        if (activeRun !== run) return false
        if (history == null) {
            if (!run.isEditAdmitted && clearIntent == null) {
                run.editFallbackMessages?.let { fallback ->
                    _messages.clear()
                    _messages.addAll(fallback + pendingMessages.map { it.message })
                    notifyLoaded()
                }
            }
            return false
        }
        applyCanonicalHistoryPosition(history)
        val historyMessages = withStoppedAnswers(history.messages)
        val reconciledMessages = withPendingFeedback(
            if (run.editedMessage != null || run.regenerationTargetId != null) {
                val existingBySdkId = _messages.associateBy { it.sdkMessageId ?: it.id }
                historyMessages.map { message ->
                    val existing = existingBySdkId[message.sdkMessageId ?: message.id]
                    message.copy(id = existing?.id ?: message.id)
                } + listOfNotNull(failure) + pendingMessages.map { it.message }
            } else {
                reconcileAgentMessages(_messages, historyMessages)
            }
        )
        if (clearIntent == null && reconciledMessages != _messages) {
            _messages.clear()
            _messages.addAll(reconciledMessages)
            notifyLoaded()
        }
        return true
    }

    private suspend fun refreshThreadRevisionForClear(threadId: String): Boolean {
        val refreshedThread = client.messages(threadId, null, 1).thread
        if (refreshedThread.id != threadId) return false
        bindThread(refreshedThread)
        return true
    }

    private suspend fun finishClearFailure(canReturnToReady: Boolean = true) {
        val intent = clearIntent ?: return
        val canonicalMessages = restoreCanonicalHistory()
        restoreClearPresentation(
            intent,
            agentHistoryAfterClearFailure(canonicalMessages, intent.fallbackMessages)
        )
        appendUnavailable()
        val nextState = if (canReturnToReady && canonicalMessages != null) {
            State.READY
        } else {
            State.ERROR
        }
        setState(nextState)
    }

    private fun restoreQueuedClearWithoutConsent() {
        val intent = clearIntent ?: return
        restoreClearPresentation(intent, intent.fallbackMessages)
    }

    private fun restoreClearPresentation(intent: ClearIntent, messages: List<AgentMessage>) {
        _messages.clear()
        _messages.addAll(withPendingFeedback(messages))
        scrollPosition = intent.fallbackScrollPosition
        clearIntent = null
        notifyLoaded()
    }

    private suspend fun restoreCanonicalHistory(): List<AgentMessage>? {
        val history = fetchCanonicalHistory() ?: return null
        applyCanonicalHistoryPosition(history)
        return history.messages
    }

    private data class CanonicalHistory(
        val thread: AgentV2ThreadSummary,
        val messages: List<AgentMessage>,
        val hasMessages: Boolean,
        val loadedOperatorMessageAt: String?
    )

    private suspend fun fetchCanonicalHistory(): CanonicalHistory? {
        val threadId = thread.id
        return try {
            val pages = mutableListOf<List<AgentV2PersistedMessage>>()
            var loadedOperatorMessageAt: String? = null
            val cursors = mutableSetOf<String>()
            var cursor: String? = null
            var hydration: AgentV2ThreadHydration
            do {
                hydration = client.messages(threadId, cursor, MESSAGE_PAGE_SIZE)
                check(hydration.thread.id == threadId) { "Unexpected Agent thread" }
                if (pages.isEmpty()) {
                    loadedOperatorMessageAt =
                        hydration.thread.support?.lastOperatorMessageAt
                }
                pages.add(hydration.messages)
                cursor = hydration.nextCursor
                check(cursor == null || cursors.add(cursor)) { "Repeated Agent message cursor" }
            } while (cursor != null)
            val messages = pages.asReversed().flatten()
            cachedHistories.storeLoadedPage(hydration.thread, messages, hasOlder = false)
            CanonicalHistory(
                hydration.thread,
                nativeMessages(messages),
                hasAgentThreadHistory(hydration.thread, emptyList(), messages),
                loadedOperatorMessageAt
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: AgentV2OperationException) {
            if (e.error.code == AGENT_THREAD_NOT_FOUND) cachedHistories.remove(threadId)
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun applyCanonicalHistoryPosition(history: CanonicalHistory) {
        historyJob?.cancel()
        historyJob = null
        hasLoadedHistoryMessages = history.hasMessages
        loadedHistoryMessageIds.clear()
        history.messages.mapNotNullTo(loadedHistoryMessageIds) { it.sdkMessageId }
        loadedOperatorMessageAt = history.loadedOperatorMessageAt
        bindThread(history.thread, hasHistory = true)
        historyCursor = null
        seenHistoryCursors.clear()
    }

    private fun currentRevision() = maxOf(revision, thread.revision)

    private fun updateMessage(
        messageId: String,
        update: (AgentMessage) -> AgentMessage
    ): AgentMessage? {
        val index = _messages.indexOfFirst { it.matchesMessageId(messageId) }
        if (index < 0) return null
        return update(_messages[index]).also { _messages[index] = it }
    }

    private fun replaceMessage(message: AgentMessage) {
        updateMessage(message.id) { message }
    }

    private fun bindInputSdkId(presentationId: String?, sdkMessageId: String?) {
        if (presentationId == null || sdkMessageId == null) return
        updateMessage(presentationId) { message ->
            message.copy(sdkMessageId = sdkMessageId)
        }
    }

    private fun canonicalMessageId(messageId: String) = _messages
        .firstOrNull { it.matchesMessageId(messageId) }
        ?.sdkMessageId
        ?: messageId

    private fun finishMessageContent(
        messageId: String,
        shouldWaitForSemanticContent: Boolean = false
    ) {
        val message = _messages.firstOrNull { it.matchesMessageId(messageId) } ?: return
        if (!message.isStreaming ||
            (shouldWaitForSemanticContent && message.isAwaitingSemanticContent)
        ) {
            return
        }
        replaceMessage(message.copy(isStreaming = false, isAwaitingSemanticContent = false))
        notifyDelegates { it.onStreamingFinished(message.id) }
    }

    private fun finalizeStreamingMessages() {
        for (index in _messages.indices) {
            val current = _messages[index]
            if (current.isStreaming && !initialOpeningPrompts.containsMessage(current.id) &&
                pendingMessages.none {
                    it.message.id == current.id || it.assistantMessageId == current.id
                }
            ) {
                val message = _messages[index].copy(
                    isStreaming = false,
                    isAwaitingSemanticContent = false
                )
                _messages[index] = message
                notifyDelegates { it.onStreamingFinished(message.id) }
            }
        }
    }

    /**
     * Keeps what [run] has shown as a finished answer, and drops its answers that show nothing. A question the run
     * didn't answer gives its place back, as a failed one does, so an edit or a regeneration shows the rows it hid.
     */
    private fun keepStoppedAnswer(run: AgentActiveRun) {
        val fallback = run.editFallbackMessages
        if (fallback != null && !run.isEditAdmitted) {
            _messages.clear()
            _messages.addAll(fallback + pendingMessages.map { it.message })
            notifyLoaded()
        } else {
            for (message in _messages.toList()) {
                if (message.role != AgentMessageRole.ASSISTANT ||
                    (!message.isStreaming && message.id !in run.answerMessageIds) ||
                    initialOpeningPrompts.containsMessage(message.id) ||
                    pendingMessages.any { it.assistantMessageId == message.id }
                ) {
                    continue
                }
                keepStoppedAnswerMessage(message)
            }
            finalizeStreamingMessages()
        }
        if (!run.hasStartedAssistant) {
            notifyDelegates { it.onOutgoingMessageFailed(run.inputPresentationId) }
        }
    }

    private fun keepStoppedAnswerMessage(message: AgentMessage) {
        if (!message.hasText && message.answerTables.isEmpty() && message.deeplinks.isEmpty()) {
            // The Agent's indicator takes the Stop before it goes, unless a queued question takes its place at once
            val keepsIndicator = message.isStreaming && pendingMessages.isEmpty()
            val durationMs = if (keepsIndicator) stoppedAnswerDurationMs() else 0L
            if (durationMs > 0) {
                showStoppingAnswer(message, durationMs)
            } else {
                removeMessage(message.id)
            }
            return
        }
        val shown = message.copy(
            isStreaming = false,
            isAwaitingSemanticContent = false,
            activityText = null,
            followups = emptyList(),
            isComplete = false
        )
        replaceMessage(shown)
        message.sdkMessageId?.takeIf { message.hasText }?.let { stoppedAnswers[it] = shown }
        notifyDelegates {
            if (message.isStreaming) {
                it.onStreamingFinished(message.id)
            } else {
                it.onStreamingUpdate(message.id)
            }
            if (message.followups.isNotEmpty()) it.onFollowupsChanged(message.id)
        }
    }

    private fun showStoppingAnswer(message: AgentMessage, durationMs: Long) {
        removeStoppingAnswer()
        replaceMessage(
            message.copy(
                isStreaming = false,
                isAwaitingSemanticContent = false,
                isStopping = true,
                followups = emptyList(),
                isComplete = false
            )
        )
        notifyDelegates { it.onStreamingFinished(message.id) }
        val job = scope.launch {
            delay(durationMs)
            stoppingAnswer = null
            removeStoppingAnswerMessage(message.id)
        }
        stoppingAnswer = message.id to job
    }

    /** The row of an answer stopped a moment ago goes at once as the next question starts its run */
    private fun removeStoppingAnswer() {
        val (messageId, job) = stoppingAnswer ?: return
        stoppingAnswer = null
        job.cancel()
        removeStoppingAnswerMessage(messageId)
    }

    // A reload in the meantime may have put the server's messages in its place
    private fun removeStoppingAnswerMessage(messageId: String) {
        if (_messages.any { it.id == messageId && it.isStopping }) removeMessage(messageId)
    }

    private fun resetActiveRunState() {
        activeRun = null
    }

    private fun invalidateWalletAuthority() {
        val invalidatedMessages = pendingMessages.filterNot { pendingMessage ->
            hostContextProvider.isMessageAuthorityCurrent(pendingMessage.authority)
        }
        pendingMessages.removeAll(invalidatedMessages.toSet())
        invalidatedMessages.forEach(::notifyPendingMessageFailed)
        invalidateAuthorityBoundActions()
        notifyFollowupsAndHints()
    }

    private fun invalidateAuthorityBoundActions() {
        cancelPendingAction()
        // The SDK sends a held question only for the wallet it was asked for
        if (limitRetry != null) {
            limitRetry = null
            onLimitsChanged()
        }
        for (index in _messages.indices) {
            val message = _messages[index]
            val deeplinks = message.deeplinks.filter { it.actionId == null }
            if (deeplinks.size == message.deeplinks.size) continue
            _messages[index] = message.copy(deeplinks = deeplinks)
            notifyDelegates { it.onStreamingUpdate(message.id) }
        }
    }

    private fun cancelPendingAction() {
        actionAvailability.invalidate()
        actionJob?.cancel()
        actionJob = null
        notifyFollowupsAndHints()
    }

    private fun cancelHostContextRecovery() {
        hostContextRecoveryJob?.cancel()
        hostContextRecoveryJob = null
    }

    private fun failPendingMessages() {
        val failedMessages = pendingMessages.toList()
        pendingMessages.clear()
        failedMessages.forEach(::notifyPendingMessageFailed)
    }

    private fun notifyPendingMessageFailed(pendingMessage: AgentPendingMessage) {
        pendingMessage.assistantMessageId?.let { messageId ->
            val index = _messages.indexOfFirst { it.id == messageId && it.sdkMessageId == null }
            if (index >= 0) {
                _messages.removeAt(index)
                notifyDelegates { it.onMessageRemoved(messageId) }
            }
        }
        finishMessageContent(pendingMessage.message.id)
        notifyDelegates { it.onOutgoingMessageFailed(pendingMessage.message.id) }
    }

    private fun requestRunCancellation() {
        if (clearIntent == null || cancellationJob?.isActive == true) return
        val run = activeRun ?: return
        val runId = run.runId ?: return
        cancellationJob = scope.launch {
            try {
                val response = client.cancelRun(runId)
                if (activeRun === run) bindThread(response.thread)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                Unit
            } finally {
                if (cancellationJob === currentCoroutineContext().job) cancellationJob = null
            }
        }
    }

    /** Shows the failure after the active run's output and returns the row that shows it */
    private fun appendUnavailable(
        code: String? = null,
        text: String = agentV2ErrorText(code)
    ): AgentMessage {
        val index = activeRunOutputInsertionIndex(
            _messages,
            activeRun?.inputPresentationId,
            pendingMessages.map { it.message }
        )
        val previousMessage = _messages.getOrNull(index - 1)
        val isShown = previousMessage?.role == AgentMessageRole.SYSTEM &&
            previousMessage.text == text
        val failure = if (isShown && previousMessage != null) {
            previousMessage
        } else {
            val message =
                AgentMessage(role = AgentMessageRole.SYSTEM, text = text, isFailure = true)
            _messages.add(index, message)
            notifyDelegates { it.onMessageAdded(message) }
            message
        }
        notifyErrorEvent()
        return failure
    }

    private fun setState(nextState: State) {
        if (state == nextState) return
        if (state == State.RUNNING && nextState == State.READY && isChatWithSupport) {
            shouldRefreshSupportHistory = true
        }
        state = nextState
        notifyDelegates { it.onStateChanged(nextState) }
        notifyFollowupsAndHints()
        updateSupportPolling()
    }

    private fun notifyFollowupsAndHints() {
        if (followupsAndHintsNotificationJob != null) return
        followupsAndHintsNotificationJob = scope.launch {
            followupsAndHintsNotificationJob = null
            _messages.findFollowupOwner()?.takeIf { it.followups.isNotEmpty() }?.let { message ->
                notifyDelegates { it.onFollowupsChanged(message.id) }
            }
            notifyHints()
        }
    }

    private fun notifyLoaded() {
        notifyDelegates { it.onMessagesLoaded(_messages.toList()) }
        notifyHints()
    }

    private fun notifyPrepended() {
        notifyDelegates { it.onMessagesPrepended(_messages.toList()) }
    }

    private fun notifyHints() {
        notifyDelegates { it.onHintsUpdated(visibleHints) }
    }

    private fun notifyErrorEvent() {
        notifyDelegates { it.onError() }
    }

    private fun notifyActionUnavailable(reason: String? = null) {
        notifyDelegates { it.onActionUnavailable(reason) }
    }

    private fun notifySessionIdle() {
        if (
            !shouldRetainSession &&
            (state != State.READY || pendingMessages.isEmpty())
        ) {
            onSessionIdle?.invoke()
        }
    }

    private fun clearPresentation() {
        historyJob?.cancel()
        historyJob = null
        historyCursor = null
        seenHistoryCursors.clear()
        pendingMessages.clear()
        _messages.clear()
        scrollPosition = ScrollPosition(ScrollAnchor.Bottom)
        notifyLoaded()
    }

    private fun appendAccountChangeMarker() {
        if (_messages.isEmpty()) return
        val nextAccountId = AccountStore.activeAccountId ?: return
        if (nextAccountId == currentAccountId) return
        currentAccountId = nextAccountId
        val accountName = AccountStore.accountById(nextAccountId)
            ?.name
            ?.takeIf { it.isNotEmpty() }
            ?: "Account"
        val text = LocaleController.getStringWithKeyValues(
            "Switched to %account%",
            listOf("%account%" to accountName)
        )
        val message = AgentMessage(role = AgentMessageRole.SYSTEM, text = text)
        val currentActiveInputId = activeRun?.inputPresentationId?.takeIf {
            activeRun?.authority?.let(hostContextProvider::isMessageAuthorityCurrent) == true
        }
        val insertionIndex = accountChangeMarkerInsertionIndex(
            _messages,
            currentActiveInputId,
            pendingMessages.map { it.message }
        )
        _messages.add(insertionIndex, message)
        val animated = liveDelegates(activeDelegates).isNotEmpty()
        notifyDelegates { it.onMessageAdded(message, animated) }
    }

    private fun liveDelegates(references: MutableList<WeakReference<Delegate>>): List<Delegate> {
        val result = mutableListOf<Delegate>()
        val iterator = references.iterator()
        while (iterator.hasNext()) {
            val delegate = iterator.next().get()
            if (delegate == null) {
                iterator.remove()
            } else {
                result.add(delegate)
            }
        }
        return result
    }

    private fun removeDelegate(
        references: MutableList<WeakReference<Delegate>>,
        delegate: Delegate
    ) {
        references.removeAll { reference ->
            val current = reference.get()
            current == null || current === delegate
        }
    }

    private inline fun notifyDelegates(callback: (Delegate) -> Unit) {
        liveDelegates(delegates).forEach(callback)
    }

    private companion object {
        const val MESSAGE_PAGE_SIZE = 100
        const val CAPACITY_EXHAUSTED = "capacity_exhausted"
        const val PROBLEM_REPORT_CHECK_ATTEMPTS = 3
    }
}

internal fun normalizeAgentMessageText(text: String): String = text.trim()

private data class AgentPendingMessage(
    val message: AgentMessage,
    val entryPoint: AgentV2EntryPoint?,
    val authority: AgentV2AuthorityBinding,
    val followupOf: AgentV2FollowUpReference? = null,
    val targetUserMessageId: String? = null,
    val targetAssistantMessageId: String? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val assistantMessageId: String? = null,
    val replacedStoppedAnswerIds: Set<String> = emptySet()
)

private fun activateNextAgentPendingMessage(
    pendingMessages: MutableList<AgentPendingMessage>,
    canStart: Boolean,
    isAuthorityCurrent: (AgentV2AuthorityBinding) -> Boolean,
    onInvalidated: (AgentPendingMessage) -> Unit,
    onActivated: (AgentPendingMessage) -> Unit
): AgentPendingMessage? {
    val iterator = pendingMessages.iterator()
    while (iterator.hasNext()) {
        val pendingMessage = iterator.next()
        if (isAuthorityCurrent(pendingMessage.authority)) continue
        iterator.remove()
        onInvalidated(pendingMessage)
    }
    if (!canStart) return null
    return pendingMessages.removeFirstOrNull()?.also(onActivated)
}

private enum class AgentClearAction {
    IGNORE,
    QUEUE,
    START,
    CANCEL_RUN
}

private enum class AgentConsentLoadAction {
    INITIALIZE,
    REQUIRE_CONSENT,
    RESTORE_CLEAR_AND_REQUIRE_CONSENT
}

private fun agentConsentLoadAction(hasConsent: Boolean, hasClearIntent: Boolean) = when {
    hasConsent -> AgentConsentLoadAction.INITIALIZE
    hasClearIntent -> AgentConsentLoadAction.RESTORE_CLEAR_AND_REQUIRE_CONSENT
    else -> AgentConsentLoadAction.REQUIRE_CONSENT
}

private fun agentClearAction(state: AgentVM.State, operationInFlight: Boolean) = when (state) {
    AgentVM.State.LOADING,
    AgentVM.State.ACCEPTING_CONSENT -> AgentClearAction.QUEUE

    AgentVM.State.READY,
    AgentVM.State.ERROR -> if (!operationInFlight) {
        AgentClearAction.START
    } else {
        AgentClearAction.QUEUE
    }

    AgentVM.State.RUNNING -> AgentClearAction.CANCEL_RUN

    AgentVM.State.CONSENT_REQUIRED,
    AgentVM.State.CLEARING -> AgentClearAction.IGNORE
}

/** The server id of a reported message; a message the server has not bound yet has none */
internal fun resolveAgentReportMessageId(
    messages: List<AgentMessage>,
    presentationId: String
): String? = messages.firstOrNull { it.matchesMessageId(presentationId) }?.sdkMessageId

private fun shouldAcceptAgentMessage(
    state: AgentVM.State,
    canSendNow: Boolean,
    canRecoverHostContext: Boolean = false,
    hasClearIntent: Boolean = false
): Boolean {
    if (hasClearIntent) return false
    if (canSendNow) return true
    return when (state) {
        AgentVM.State.LOADING,
        AgentVM.State.CONSENT_REQUIRED,
        AgentVM.State.ACCEPTING_CONSENT,
        AgentVM.State.RUNNING,
        AgentVM.State.ERROR -> true

        AgentVM.State.READY -> canRecoverHostContext

        AgentVM.State.CLEARING -> false
    }
}

private suspend fun <T> clearAgentThreadWithConflictRetry(
    clear: suspend () -> T,
    refreshRevision: suspend () -> Boolean
): T {
    var didRetry = false
    while (true) {
        try {
            return clear()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (
                didRetry ||
                e.message != AGENT_THREAD_REVISION_CONFLICT ||
                !refreshRevision()
            ) {
                throw e
            }
            didRetry = true
        }
    }
}

private fun agentHistoryAfterClearFailure(
    canonicalMessages: List<AgentMessage>?,
    fallbackMessages: List<AgentMessage>
) = canonicalMessages ?: fallbackMessages

private fun safeAgentClearFallback(
    messages: List<AgentMessage>,
    pendingMessages: List<AgentMessage>
) = messages
    .filterNot { message ->
        pendingMessages.any { pendingMessage ->
            message === pendingMessage ||
                message.matchesMessageId(pendingMessage.id) ||
                pendingMessage.matchesMessageId(message.id) ||
                message.sdkMessageId?.let(pendingMessage::matchesMessageId) == true ||
                pendingMessage.sdkMessageId?.let(message::matchesMessageId) == true
        }
    }
    .map { message ->
        if (message.isStreaming) message.copy(isStreaming = false) else message
    }

private fun activeRunOutputInsertionIndex(
    messages: List<AgentMessage>,
    activeInputMessageId: String?,
    pendingMessages: List<AgentMessage>
): Int {
    val activeIndex = activeInputMessageId?.let { messageId ->
        messages.indexOfFirst { it.matchesMessageId(messageId) }
    } ?: return messages.size
    if (activeIndex < 0) return messages.size
    return pendingMessages.firstNotNullOfOrNull { pendingMessage ->
        messages.indexOfFirst { it.matchesMessageId(pendingMessage.id) }
            .takeIf { it > activeIndex }
    } ?: messages.size
}

private fun accountChangeMarkerInsertionIndex(
    messages: List<AgentMessage>,
    activeInputMessageId: String?,
    pendingMessages: List<AgentMessage>
): Int = messages.indexOfFirst { message ->
    activeInputMessageId?.let(message::matchesMessageId) == true ||
        pendingMessages.any { pendingMessage ->
            message === pendingMessage ||
                message.matchesMessageId(pendingMessage.id) ||
                pendingMessage.matchesMessageId(message.id)
        }
}.takeIf { it >= 0 } ?: messages.size

private fun reconcileAgentMessages(
    existingMessages: List<AgentMessage>,
    canonicalMessages: List<AgentMessage>
): List<AgentMessage> {
    val canonicalIds = canonicalMessages.map { it.sdkMessageId ?: it.id }.toSet()
    val reconciled = canonicalMessages.map { canonicalMessage ->
        val sdkMessageId = canonicalMessage.sdkMessageId ?: canonicalMessage.id
        val existingMessage = existingMessages.firstOrNull {
            it.matchesMessageId(sdkMessageId)
        }
        if (existingMessage == null) {
            canonicalMessage
        } else {
            canonicalMessage.copy(id = existingMessage.id, sdkMessageId = sdkMessageId)
        }
    }
    return reconciled + existingMessages.filter { message ->
        message.sdkMessageId == null || message.sdkMessageId !in canonicalIds
    }
}

/**
 * The server's newest page as a kept chat's history after a refresh. Of the messages shown that the page lacks, only
 * those not stored yet and the stopped answers newer than the page's oldest message stay, each in its place by time;
 * older stopped answers wait for their page.
 */
private fun refreshAgentMessages(
    existingMessages: List<AgentMessage>,
    pageMessages: List<AgentMessage>,
    stoppedAnswerIds: Set<String>
): List<AgentMessage> {
    val page = reconcileAgentMessages(existingMessages, pageMessages).take(pageMessages.size)
    val pageIds = page.mapNotNull { it.sdkMessageId }.toSet()
    val oldestDate = page.minOfOrNull { it.date }
    val keptMessages = existingMessages.filter { message ->
        val sdkMessageId = message.sdkMessageId ?: return@filter true
        sdkMessageId !in pageIds && sdkMessageId in stoppedAnswerIds &&
            oldestDate != null && message.date > oldestDate
    }
    return keptMessages.fold(page) { messages, kept ->
        val index = messages.indexOfLast { !it.date.after(kept.date) } + 1
        messages.take(index) + kept + messages.drop(index)
    }
}

private const val AGENT_THREAD_REVISION_CONFLICT = "thread_revision_conflict"
private const val AGENT_THREAD_NOT_FOUND = "thread_not_found"
private const val SUPPORT_POLLING_INTERVAL_MS = 15_000L
private const val MAX_SUPPORT_REFRESH_PAGES = 10

private fun mergeSupportAgentMessages(
    existingMessages: List<AgentMessage>,
    pageMessages: List<AgentMessage>
): List<AgentMessage> {
    val merged = existingMessages.toMutableList()
    var followingMessageId: String? = null
    for (message in pageMessages.asReversed()) {
        val sourceId = message.sdkMessageId ?: message.id
        val index = merged.indexOfFirst { it.matchesMessageId(sourceId) }
        if (index >= 0) {
            merged[index] = message.copy(id = merged[index].id)
            followingMessageId = merged[index].id
            continue
        }
        val followingIndex = followingMessageId?.let { id -> merged.indexOfFirst { it.id == id } }
        val insertionIndex = followingIndex ?: merged.indexOfFirst {
            it.sdkMessageId == null && it.date.after(message.date)
        }.takeIf { it >= 0 } ?: merged.size
        merged.add(insertionIndex, message)
        followingMessageId = message.id
    }
    return merged
}

internal fun hasAgentThreadHistory(
    thread: AgentV2ThreadSummary,
    messages: List<AgentMessage>,
    historyMessages: List<AgentV2PersistedMessage> = emptyList()
): Boolean = thread.messageCount > 0 || historyMessages.isNotEmpty() || messages.any {
    it.role == AgentMessageRole.USER || it.sdkMessageId != null
}

/**
 * A thread opened by its id shows its cached messages unless it is unread, also without a first unread message, as
 * after an answer the summary doesn't count yet: an unread chat opens by its loaded history
 */
internal fun canShowAgentCachedMessages(
    thread: AgentV2ThreadSummary,
    hasOpening: Boolean,
    readState: AgentThreadReadState
) = !hasOpening && !readState.isUnread(thread)

/** A chat of a thread with messages shows their placeholder while it has none to show and loads */
internal fun shouldShowAgentMessagesSkeleton(model: AgentVM, hasOpening: Boolean) = !hasOpening &&
    model.state == AgentVM.State.LOADING && model.messages.isEmpty() &&
    model.currentThread.messageCount > 0

internal suspend fun hydrateAgentThread(
    thread: AgentV2ThreadSummary,
    loadMessages: suspend (String) -> AgentV2ThreadHydration
): AgentV2ThreadHydration = loadMessages(thread.id).also { hydration ->
    check(hydration.thread.id == thread.id) { "Unexpected Agent thread" }
}

internal fun agentMessagesBeforeRegeneration(
    messages: List<AgentMessage>,
    messageId: String,
    pendingMessages: List<AgentMessage> = emptyList()
): List<AgentMessage>? {
    val index = messages.indexOfFirst { it.matchesMessageId(messageId) }
    if (index < 0 || messages[index].role != AgentMessageRole.ASSISTANT) return null
    return messages.take(index) + pendingMessages
}

internal fun agentMessagesBeforeEdit(
    messages: List<AgentMessage>,
    messageId: String
): List<AgentMessage>? {
    val index = messages.indexOfFirst { it.matchesMessageId(messageId) }
    if (index < 0 || messages[index].role != AgentMessageRole.USER) return null
    return messages.take(index)
}
