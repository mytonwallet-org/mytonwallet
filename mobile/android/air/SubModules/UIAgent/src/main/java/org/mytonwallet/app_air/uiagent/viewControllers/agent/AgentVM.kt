package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.os.Looper
import java.lang.ref.WeakReference
import java.util.Date
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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
import org.mytonwallet.app_air.uiagent.agentV2.hasVisibleFailure
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.agentV2.mapAgentV2Message
import org.mytonwallet.app_air.uiagent.agentV2.requiresAgentV2ThreadResync
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.loadExploreSites
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class AgentVM(
    initialScrollPosition: ScrollPosition? = null,
    private val client: AgentV2Client = LiveAgentV2Client()
) : WalletCore.UpdatesObserver,
    WalletCore.EventObserver {
    private data class ClearIntent(
        val fallbackMessages: List<AgentMessage>,
        val fallbackScrollPosition: ScrollPosition?
    )

    interface Delegate {
        fun onMessageAcceptanceChanged()
        fun onStateChanged(state: State)
        fun onMessageAdded(message: AgentMessage, animated: Boolean = true)
        fun onMessageRemoved(messageId: String)
        fun onMessagesLoaded(messages: List<AgentMessage>)
        fun onMessagesTruncated(removedMessages: List<AgentMessage>)
        fun onMessagesPrepended(messages: List<AgentMessage>)
        fun onStreamingUpdate(messageId: String)
        fun onStreamingFinished(messageId: String)
        fun onFollowupsChanged(messageId: String, animated: Boolean = false)
        fun onOutgoingMessageFailed(messageId: String)
        fun onPendingMessageActivated(messageId: String)
        fun onActionUnavailable()
        fun onOpenDapp(site: MExploreSite)
        fun onError()
        fun onHintsUpdated(hints: List<AgentHint>)
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
    private val supervisorJob = SupervisorJob()
    private val scope = CoroutineScope(supervisorJob + Dispatchers.Main)
    private val hostContextProvider = AgentV2HostContextProvider(client, scope)

    // Its own scope lets the inactive state reach the SDK after onDestroy cancels [scope].
    private val chatActivity = AgentV2ChatActivity(
        CoroutineScope(SupervisorJob() + Dispatchers.Main),
        client::setChatActive
    )

    private val actionAvailability = AgentActionAvailability(client::actionPresentation)
    private val pendingMessages = mutableListOf<AgentPendingMessage>()
    private val _messages = mutableListOf<AgentMessage>()
    private var availableHints = emptyList<AgentHint>()
    private var hintsCatalogVersion: String? = null
    private var acceptanceNotificationJob: Job? = null
    private var startupJob: Job? = null
    private var hintsJob: Job? = null
    private var operationJob: Job? = null
    private var actionJob: Job? = null
    private var historyJob: Job? = null
    private var cancellationJob: Job? = null
    private var hostContextRecoveryJob: Job? = null
    private val problemReportJobs = mutableSetOf<Job>()
    private var problemReportAvailabilityJob: Job? = null
    private var isProblemReportAvailable = false
    private var thread: AgentV2ThreadSummary? = null
    private var historyCursor: String? = null
    private val seenHistoryCursors = mutableSetOf<String>()
    private var revision = 1
    private var clearIntent: ClearIntent? = null
    private var currentAccountId = AccountStore.activeAccountId
    private var activeRun: AgentActiveRun? = null
    internal var onSessionIdle: (() -> Unit)? = null

    val messages: List<AgentMessage> get() = _messages

    /**
     * Whether the server has sent answer links in this session. From then on an answer carries its links and keeps
     * bare domains as text; before, an answer may come from a server that sends its URLs as text.
     */
    var publishesAnswerLinks = false
        private set
    var scrollPosition: ScrollPosition? = initialScrollPosition
        private set
    val visibleHints: List<AgentHint>
        get() = if (state == State.READY && clearIntent == null && _messages.isEmpty()) {
            availableHints
        } else {
            emptyList()
        }
    val canSendFollowup: Boolean
        get() = clearIntent == null && thread != null && pendingMessages.isEmpty() && canSendNow()
    val canReportProblem: Boolean
        get() = isProblemReportAvailable && thread != null && _messages.isNotEmpty()
    var state = State.LOADING
        private set
    internal val shouldRetainSession: Boolean
        get() = state == State.RUNNING ||
            state == State.CLEARING ||
            clearIntent != null ||
            operationJob?.isActive == true ||
            historyJob?.isActive == true ||
            hostContextRecoveryJob?.isActive == true ||
            problemReportJobs.isNotEmpty()

    init {
        hostContextProvider.isRunActive = { operationJob?.isActive == true }
        hostContextProvider.onAuthorityContextInvalidated = ::invalidateWalletAuthority
        hostContextProvider.onAuthorityContextPublished = {
            sendNextPending()
            notifyMessageAcceptanceChanged()
        }
        hostContextProvider.onMessageAuthorityChanged = ::notifyMessageAcceptanceChanged
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        WalletCore.registerObserver(this)
        start()
    }

    fun attach(delegate: Delegate) {
        if (liveDelegates(delegates).none { it === delegate }) {
            delegates.add(WeakReference(delegate))
        }
        delegate.onMessagesLoaded(_messages.toList())
        delegate.onHintsUpdated(visibleHints)
        delegate.onStateChanged(state)
    }

    fun detach(delegate: Delegate) {
        removeDelegate(delegates, delegate)
        removeDelegate(activeDelegates, delegate)
        chatActivity.setVisible(liveDelegates(activeDelegates).isNotEmpty())
    }

    fun setActive(delegate: Delegate, active: Boolean) {
        removeDelegate(activeDelegates, delegate)
        if (active) {
            activeDelegates.add(WeakReference(delegate))
            retry()
            refreshProblemReportAvailability()
        }
        chatActivity.setVisible(liveDelegates(activeDelegates).isNotEmpty())
    }

    fun retry() {
        if (state == State.ERROR && startupJob?.isActive != true) start()
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
            hasThread = thread != null,
            operationInFlight = operationJob?.isActive == true
        )
        if (clearAction == AgentClearAction.IGNORE) return

        clearIntent = ClearIntent(
            fallbackMessages = safeAgentClearFallback(
                _messages,
                pendingMessages.map { it.message }
            ),
            fallbackScrollPosition = scrollPosition
        )
        cancelHostContextRecovery()
        cancelPendingAction()
        clearPresentation()
        setState(State.CLEARING)
        when (clearAction) {
            AgentClearAction.CANCEL_RUN -> requestRunCancellation()

            AgentClearAction.START -> launchPendingClear()

            AgentClearAction.QUEUE -> {
                if (
                    startupJob?.isActive != true &&
                    operationJob?.isActive != true &&
                    thread == null
                ) {
                    start()
                }
            }

            AgentClearAction.IGNORE -> Unit
        }
    }

    private fun launchPendingClear() {
        val currentThread = thread ?: return
        if (clearIntent == null || operationJob?.isActive == true) return
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
                bindThread(response.thread)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                hasFailed = true
            } finally {
                if (operationJob === currentCoroutineContext().job) operationJob = null
                notifyMessageAcceptanceChanged()
            }

            if (!hasFailed) {
                clearIntent = null
                setState(State.READY)
                hintsJob?.cancel()
                hintsJob = scope.launch { loadHints() }
            } else {
                finishClearFailure()
            }
            notifySessionIdle()
        }
    }

    /** Asks whether the server takes problem reports; a loaded thread means the consent the SDK requires */
    private fun refreshProblemReportAvailability() {
        if (thread == null) return
        problemReportAvailabilityJob?.cancel()
        problemReportAvailabilityJob = scope.launch {
            isProblemReportAvailable = try {
                client.problemReportAvailability()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                false
            }
        }
    }

    /** Reports the answer shown as [presentationId], or the whole conversation when it is null */
    fun reportProblem(presentationId: String?, comment: String?, onResult: (Boolean) -> Unit) {
        val threadId = thread?.id
        val messageId = presentationId?.let { resolveAgentReportMessageId(_messages, it) }
        if (threadId == null || (presentationId != null && messageId == null)) {
            onResult(false)
            return
        }
        // The session outlives the screen until the report settles; see `shouldRetainSession`.
        // The job is tracked before it starts, so its own removal can never come first.
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val isSent = try {
                client.reportProblem(threadId, messageId, comment)
                true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // A server that has switched reports off refuses them, and asking again takes the entry points away
                refreshProblemReportAvailability()
                problemReportAvailabilityJob?.join()
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

    fun sendMessage(text: String, entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()): Boolean {
        val normalized = text.trim()
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
        acceptMessage(normalized, entryPoint, null, authority, shouldSendNow)
        return true
    }

    fun canEditMessage(messageId: String): Boolean = canSendFollowup &&
        _messages.any {
            it.matchesMessageId(messageId) && it.role == AgentMessageRole.USER &&
                it.sdkMessageId != null
        }

    fun canRegenerateMessage(messageId: String): Boolean = canSendFollowup &&
        _messages.any {
            it.matchesMessageId(messageId) && it.role == AgentMessageRole.ASSISTANT &&
                it.sdkMessageId != null && !it.isStreaming
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
                targetAssistantMessageId = message.sdkMessageId
            )
        )
        return true
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
                editFallbackMessages = fallbackMessages
            )
        )
        return true
    }

    fun visibleFollowups(messageId: String): List<AgentV2FollowUp> = _messages
        .findFollowupOwner()
        ?.takeIf { it.matchesMessageId(messageId) }
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

    fun acceptConsent() {
        if (state != State.CONSENT_REQUIRED || startupJob?.isActive == true) return
        setState(State.ACCEPTING_CONSENT)
        startupJob = scope.launch {
            try {
                client.acceptConsent()
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
                notifyMessageAcceptanceChanged()
            }
        }
        notifyMessageAcceptanceChanged()
    }

    fun loadOlderMessages() {
        loadOlderMessagesUntil()
    }

    fun loadMessageHistoryUntil(messageId: String, completion: (Boolean) -> Unit) {
        if (_messages.any { it.matchesMessageId(messageId) }) {
            completion(true)
            return
        }
        historyJob?.takeIf { it.isActive }?.let { activeJob ->
            activeJob.invokeOnCompletion {
                scope.launch { loadMessageHistoryUntil(messageId, completion) }
            }
            return
        }
        loadOlderMessagesUntil(messageId, completion)
    }

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
            WalletEvent.AppBackground -> chatActivity.setInBackground(true)
            WalletEvent.AppForeground -> chatActivity.setInBackground(false)
            else -> Unit
        }
    }

    fun onDestroy() {
        resetActiveRunState()
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        WalletCore.unregisterObserver(this)
        chatActivity.stop()
        cancelPendingAction()
        historyJob?.cancel()
        cancelHostContextRecovery()
        hostContextProvider.stop()
        scope.cancel()
        delegates.clear()
        activeDelegates.clear()
    }

    private fun start() {
        if (startupJob?.isActive == true) return
        actionAvailability.invalidate()
        setState(State.LOADING)
        startupJob = scope.launch {
            try {
                when (agentConsentLoadAction(client.consent(), clearIntent != null)) {
                    AgentConsentLoadAction.INITIALIZE -> initializeConversation()

                    AgentConsentLoadAction.REQUIRE_CONSENT -> {
                        chatActivity.setConsentAccepted(false)
                        setState(State.CONSENT_REQUIRED)
                    }

                    AgentConsentLoadAction.RESTORE_CLEAR_AND_REQUIRE_CONSENT -> {
                        chatActivity.setConsentAccepted(false)
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
                notifySessionIdle()
            }
        }
    }

    private suspend fun initializeConversation() {
        chatActivity.setConsentAccepted(true)
        check(hostContextProvider.start()) { "Host context is unavailable" }
        val defaultThread = client.defaultThread()
        bindThread(defaultThread.thread)
        refreshProblemReportAvailability()
        hydrate()
        if (clearIntent != null) {
            launchPendingClear()
            return
        }
        setState(State.READY)
        hintsJob?.cancel()
        hintsJob = scope.launch { loadHints() }
        sendNextPending()
        notifySessionIdle()
    }

    private suspend fun hydrate() {
        val currentThread = checkNotNull(thread)
        val hydration = client.messages(currentThread.id, null, MESSAGE_PAGE_SIZE)
        check(hydration.thread.id == currentThread.id) { "Unexpected Agent thread" }
        bindThread(hydration.thread)
        historyCursor = hydration.nextCursor
        seenHistoryCursors.clear()
        hydration.nextCursor?.let(seenHistoryCursors::add)
        if (clearIntent != null) return
        val hydratedMessages = nativeMessages(hydration.messages)
        val reconciledMessages = reconcileAgentMessages(_messages, hydratedMessages)
        _messages.clear()
        _messages.addAll(reconciledMessages)
        if (_messages.isEmpty()) scrollPosition = ScrollPosition(ScrollAnchor.Bottom)
        notifyLoaded()
    }

    private fun loadOlderMessagesUntil(
        targetMessageId: String? = null,
        completion: ((Boolean) -> Unit)? = null
    ) {
        if (activeRun?.editedMessage != null || activeRun?.regenerationTargetId != null) {
            completion?.invoke(false)
            return
        }
        if (historyJob?.isActive == true) return
        val currentThread = thread ?: return
        if (targetMessageId != null && _messages.any { it.matchesMessageId(targetMessageId) }) {
            completion?.invoke(true)
            return
        }
        if (historyCursor == null) {
            completion?.invoke(false)
            return
        }
        historyJob = scope.launch {
            var foundTarget = false
            try {
                do {
                    val cursor = historyCursor ?: break
                    val hydration = client.messages(currentThread.id, cursor, MESSAGE_PAGE_SIZE)
                    check(hydration.thread.id == currentThread.id) { "Unexpected Agent thread" }
                    val nextCursor = hydration.nextCursor
                    check(nextCursor == null || seenHistoryCursors.add(nextCursor)) {
                        "Repeated Agent message cursor"
                    }
                    bindThread(hydration.thread)
                    historyCursor = nextCursor

                    val existingIds = _messages.mapTo(mutableSetOf()) {
                        it.sdkMessageId ?: it.id
                    }
                    val olderMessages = nativeMessages(hydration.messages).filter { message ->
                        val sdkMessageId = message.sdkMessageId ?: message.id
                        existingIds.add(sdkMessageId)
                    }
                    if (olderMessages.isNotEmpty()) {
                        _messages.addAll(0, olderMessages)
                        notifyPrepended()
                    }
                    foundTarget = targetMessageId != null && _messages.any {
                        it.matchesMessageId(targetMessageId)
                    }
                } while (targetMessageId != null && !foundTarget && historyCursor != null)
                completion?.invoke(foundTarget)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                notifyErrorEvent()
            } finally {
                if (historyJob === currentCoroutineContext().job) historyJob = null
                notifySessionIdle()
            }
        }
    }

    private suspend fun loadHints() {
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
        appendUnavailable((error as? AgentV2OperationException)?.error?.code)
        setState(State.ERROR)
    }

    private fun sendNow(pendingMessage: AgentPendingMessage) {
        val localMessage = pendingMessage.message
        if (!hostContextProvider.isMessageAuthorityCurrent(pendingMessage.authority)) {
            notifyPendingMessageFailed(pendingMessage)
            sendNextPending()
            return
        }
        val currentThread = thread ?: run {
            pendingMessages.add(0, pendingMessage)
            return
        }
        if (!canSendNow()) {
            pendingMessages.add(0, pendingMessage)
            requestHostContextRecovery()
            return
        }

        val run = AgentActiveRun(
            localMessage.id,
            pendingMessage.authority,
            editedMessage = localMessage.takeIf { pendingMessage.targetUserMessageId != null },
            editFallbackMessages = pendingMessage.editFallbackMessages,
            regenerationTargetId = pendingMessage.targetAssistantMessageId
        )
        activeRun = run
        if (run.regenerationTargetId == null) {
            run.assistantPresentationId = addAssistantPlaceholder()
        }
        setState(State.RUNNING)

        operationJob = scope.launch {
            var hasFailed = false
            try {
                check(hostContextProvider.flushPendingUpdateBeforeRun()) {
                    "agent_host_context_update_failed"
                }
                if (activeRun !== run) return@launch
                check(hostContextProvider.isMessageAuthorityCurrent(pendingMessage.authority)) {
                    "agent_wallet_authority_changed"
                }
                val result = client.startRun(
                    threadId = currentThread.id,
                    revision = currentRevision(),
                    text = localMessage.text,
                    entryPoint = pendingMessage.entryPoint,
                    followupOf = pendingMessage.followupOf,
                    targetUserMessageId = pendingMessage.targetUserMessageId,
                    targetAssistantMessageId = pendingMessage.targetAssistantMessageId
                )
                if (activeRun !== run) return@launch
                if (run.bind(result.clientRunId, result.runId)) {
                    if (result.runId != null) admitRun(run)
                    if (run.regenerationTargetId == null) {
                        bindInputSdkId(localMessage.id, result.inputMessageId)
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
                    notifyMessageAcceptanceChanged()
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
            if (hasFailed || !run.hasStartedAssistant) {
                notifyDelegates { it.onOutgoingMessageFailed(localMessage.id) }
            }
            if (hasFailed) {
                appendUnavailable(run.failureCode)
            }
            if (hasFailed && (
                    run.editedMessage != null ||
                        (run.regenerationTargetId != null && run.isEditAdmitted)
                    )
            ) {
                run.shouldResyncThread = true
            }
            val didRecoverThread = !run.shouldResyncThread || resyncThread(run)
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

    private fun canSendNow() = state == State.READY &&
        operationJob?.isActive != true &&
        actionJob?.isActive != true &&
        hasCurrentAuthority()

    private fun hasCurrentAuthority() = hostContextProvider.captureActionAuthority() != null

    private fun bindActiveRun(clientRunId: String, runId: String?, threadId: String?): Boolean {
        if (!hasActiveRunOperation()) return false
        val currentThreadId = thread?.id ?: return false
        if (threadId != null && threadId != currentThreadId) return false
        return activeRun?.bind(clientRunId, runId) == true
    }

    private fun matchesActiveRun(clientRunId: String, runId: String, threadId: String): Boolean =
        hasActiveRunOperation() &&
            thread?.id == threadId &&
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
        val currentThreadId = thread?.id
        when (update) {
            is AgentV2Update.RunStarted -> {
                if (!bindActiveRun(update.clientRunId, update.runId, update.threadId)) return
                revision = update.threadRevision
                activeRun?.let { run ->
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
                finishMessageContent(update.messageId)
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
                if (activeRun?.hasStartedAssistant == true) finalizeStreamingMessages()
                activeRun?.hasFailed = true
                activeRun?.failureCode = update.code
                activeRun?.shouldResyncThread = (activeRun?.shouldResyncThread == true) ||
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
        }
    }

    private fun admitRun(run: AgentActiveRun) {
        if (run.isEditAdmitted) return
        run.isEditAdmitted = true
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

    private fun ensureAssistantMessage(messageId: String): AgentMessage {
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
            mapAgentV2Message(message, actions)
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
        if (update.threadId != thread?.id || clearIntent != null) return
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

    private fun bindThread(nextThread: AgentV2ThreadSummary) {
        if (thread != null && thread?.id != nextThread.id) return
        thread = nextThread
        revision = nextThread.revision
    }

    private suspend fun resyncThread(run: AgentActiveRun): Boolean {
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
        applyCanonicalHistoryPosition(history.thread)
        val reconciledMessages = if (run.editedMessage != null ||
            run.regenerationTargetId != null
        ) {
            val existingBySdkId = _messages.associateBy { it.sdkMessageId ?: it.id }
            history.messages.map { message ->
                val existing = existingBySdkId[message.sdkMessageId ?: message.id]
                message.copy(id = existing?.id ?: message.id)
            } + pendingMessages.map { it.message }
        } else {
            reconcileAgentMessages(_messages, history.messages)
        }
        if (clearIntent == null && reconciledMessages != _messages) {
            _messages.clear()
            _messages.addAll(reconciledMessages)
            notifyLoaded()
        }
        return true
    }

    private suspend fun refreshThreadRevisionForClear(threadId: String): Boolean {
        val refreshedThread = client.defaultThread().thread
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
        _messages.addAll(messages)
        scrollPosition = intent.fallbackScrollPosition
        clearIntent = null
        notifyLoaded()
    }

    private suspend fun restoreCanonicalHistory(): List<AgentMessage>? {
        val history = fetchCanonicalHistory() ?: return null
        applyCanonicalHistoryPosition(history.thread)
        return history.messages
    }

    private data class CanonicalHistory(
        val thread: AgentV2ThreadSummary,
        val messages: List<AgentMessage>
    )

    private suspend fun fetchCanonicalHistory(): CanonicalHistory? {
        val threadId = thread?.id ?: return null
        return try {
            if (client.defaultThread().thread.id != threadId) return null
            val pages = mutableListOf<List<AgentV2PersistedMessage>>()
            val cursors = mutableSetOf<String>()
            var cursor: String? = null
            var hydration: AgentV2ThreadHydration
            do {
                hydration = client.messages(threadId, cursor, MESSAGE_PAGE_SIZE)
                check(hydration.thread.id == threadId) { "Unexpected Agent thread" }
                pages.add(hydration.messages)
                cursor = hydration.nextCursor
                check(cursor == null || cursors.add(cursor)) { "Repeated Agent message cursor" }
            } while (cursor != null)
            CanonicalHistory(hydration.thread, nativeMessages(pages.asReversed().flatten()))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            null
        }
    }

    private fun applyCanonicalHistoryPosition(canonicalThread: AgentV2ThreadSummary) {
        bindThread(canonicalThread)
        historyCursor = null
        seenHistoryCursors.clear()
    }

    private fun currentRevision() = maxOf(revision, thread?.revision ?: 1)

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
            if (_messages[index].isStreaming) {
                val message = _messages[index].copy(
                    isStreaming = false,
                    isAwaitingSemanticContent = false
                )
                _messages[index] = message
                notifyDelegates { it.onStreamingFinished(message.id) }
            }
        }
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
        notifyMessageAcceptanceChanged()
    }

    private fun invalidateAuthorityBoundActions() {
        cancelPendingAction()
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
        notifyMessageAcceptanceChanged()
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

    private fun appendUnavailable(code: String? = null) {
        val text = agentV2ErrorText(code)
        val index = activeRunOutputInsertionIndex(
            _messages,
            activeRun?.inputPresentationId,
            pendingMessages.map { it.message }
        )
        val previousMessage = _messages.getOrNull(index - 1)
        if (previousMessage?.role != AgentMessageRole.SYSTEM || previousMessage.text != text) {
            val message = AgentMessage(role = AgentMessageRole.SYSTEM, text = text)
            _messages.add(index, message)
            notifyDelegates { it.onMessageAdded(message) }
        }
        notifyErrorEvent()
    }

    private fun setState(nextState: State) {
        if (state == nextState) return
        state = nextState
        notifyDelegates { it.onStateChanged(nextState) }
        notifyMessageAcceptanceChanged()
    }

    private fun notifyMessageAcceptanceChanged() {
        if (acceptanceNotificationJob != null) return
        acceptanceNotificationJob = scope.launch {
            acceptanceNotificationJob = null
            notifyDelegates { it.onMessageAcceptanceChanged() }
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

    private fun notifyActionUnavailable() {
        notifyDelegates { it.onActionUnavailable() }
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
    }
}

private data class AgentPendingMessage(
    val message: AgentMessage,
    val entryPoint: AgentV2EntryPoint?,
    val authority: AgentV2AuthorityBinding,
    val followupOf: AgentV2FollowUpReference? = null,
    val targetUserMessageId: String? = null,
    val targetAssistantMessageId: String? = null,
    val editFallbackMessages: List<AgentMessage>? = null
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

private fun agentClearAction(state: AgentVM.State, hasThread: Boolean, operationInFlight: Boolean) =
    when (state) {
        AgentVM.State.LOADING,
        AgentVM.State.ACCEPTING_CONSENT -> AgentClearAction.QUEUE

        AgentVM.State.READY,
        AgentVM.State.ERROR -> if (hasThread && !operationInFlight) {
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

private const val AGENT_THREAD_REVISION_CONFLICT = "thread_revision_conflict"

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
