package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.getAgentSupportRequestText
import org.mytonwallet.app_air.uiagent.agentV2.isAgentSupportHandoffDeclared
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDigestSchedule
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsFeedClient
import org.mytonwallet.app_air.uiagent.viewControllers.news.LiveAgentNewsFeedClient
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Availability
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2UserQuota
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore

data class AgentNewsChatRequest(
    val eventId: Int,
    val locale: String? = null,
    val headline: String = "",
    val icon: String? = null,
    val threadId: String? = null,
    val excerpt: String? = null,
    val imageUrl: String? = null,
    val publishedAt: String? = null,
    val body: String? = null,
    val sources: List<AgentV2NewsFeedItem.Source>? = null,
    val discussionNaming: AgentV2NewsFeedItem.DiscussionNaming? = null,
    val shouldDeferCreation: Boolean = false
)

data class AgentPromptChatRequest(
    val prompt: String,
    val entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()
)

internal class AgentChatOpening(
    private val prompt: AgentPromptChatRequest? = null,
    private val news: AgentNewsChatRequest? = null,
    private val client: AgentV2Client = LiveAgentV2Client(),
    private val digestId: String? = null,
    private val feedClient: AgentNewsFeedClient = LiveAgentNewsFeedClient(),
    private val shouldDeferCreation: Boolean = false
) : WalletCore.EventObserver {
    init {
        require(listOfNotNull(prompt, news, digestId).size == 1) {
            "An opening requires one chat request"
        }
    }

    private val loader = AgentNewChatLoader(
        {
            ensureOpeningIsActive()
            client.consent().also { hasConsent = it }
        },
        {
            ensureOpeningIsActive()
            client.acceptConsent()
            hasConsent = true
        },
        ::createThread,
        news?.let { request ->
            request.locale?.let { AgentV2ThreadNewsRequest(request.eventId, it) }
        },
        hasDiscussion = news != null || digestId != null,
        shouldDeferCreation = isDeferredDiscussion
    )
    private val promptMessages = prompt?.let {
        listOf(
            AgentMessage(
                role = AgentMessageRole.USER,
                text = normalizeAgentMessageText(it.prompt),
                isStreaming = true
            ),
            AgentMessage(
                role = AgentMessageRole.ASSISTANT,
                text = "",
                isStreaming = true
            )
        )
    }.orEmpty()
    val isDeferredDiscussion: Boolean
        get() = getAgentDeferredDiscussionKey(news, digestId, shouldDeferCreation) != null
    private var pendingDiscussionMessage: AgentMessage? = null
    private var isHeaderSupportRequest = false
    val hasStagedMessage: Boolean
        get() = pendingDiscussionMessage != null
    var messageAuthority: AgentV2AuthorityBinding? = null
        private set
    private val openingMessages: List<AgentMessage>
        get() = pendingDiscussionMessage?.let(::listOf) ?: promptMessages
    var followupText: String? = null
        private set
    val canSubmitDiscussionMessage: Boolean
        get() = isDeferredDiscussion && pendingDiscussionMessage == null && !isDeleted &&
            !isInputBlockedByLimit && (hasConsent != true || areLimitsLoaded)
    val entryPoint: AgentV2EntryPoint
        get() = if (isHeaderSupportRequest) {
            AgentV2EntryPoint.supportRequest(AgentV2SupportRequestSource.HEADER)
        } else {
            prompt?.entryPoint ?: AgentV2EntryPoint()
        }
    private var discussionThread = news?.threadId?.let {
        AgentV2ThreadSummary(it, revision = 0, icon = news.icon, news = news.newsPostCard())
    }
    var messages = if (discussionThread == null) openingMessages else emptyList()
        private set
    var error: Throwable? = null
        private set
    var isConsentRequired = false
        private set
    var isCreating = false
        private set

    /** Whether the user has allowed the Agent, once read: a discussion opens without asking */
    var hasConsent: Boolean? = null
        private set
    var onChange: (() -> Unit)? = null
    private var isDeleted = false
    private val heldProblemReports = mutableListOf<HeldProblemReport>()

    /**
     * With the user's consent, the conversation can be reported while its thread is being created: the report waits
     * for the chat the thread opens, see [releaseHeldReports]
     */
    val canReportProblem: Boolean
        get() = !isDeferredDiscussion && (hasConsent ?: client.isConsentKnownGiven) &&
            error == null && !isDeleted

    val isSupportRequestVisible: Boolean
        get() = isAgentSupportHandoffDeclared && !isDeleted
    val canRequestSupport: Boolean
        get() = isSupportRequestVisible && isDeferredDiscussion && discussionThread == null &&
            hasConsent == true && !isCreating && !hasStagedMessage
    private var creationScope: CoroutineScope? = null
    private var creationRequest: Deferred<Result<AgentV2ThreadSummary>>? = null
    private var availability: AgentV2Availability? = null
    private var userQuota: AgentV2UserQuota? = null
    private var limitsRequest: CompletableDeferred<Unit>? = null
    private var areLimitsLoaded = false
    val isInputBlockedByLimit: Boolean
        get() = getInputLimitCode() != null

    fun acquireDiscussion(
        acquire: (AgentV2ThreadSummary) -> AgentVM = AgentSession::acquire
    ): AgentVM? = discussionThread?.let(acquire)

    fun recreateMissingDiscussion(errorCode: String?): Boolean {
        if (discussionThread == null || errorCode != "thread_not_found") return false
        dropStagedSupportRequest()
        discussionThread = null
        messages = openingMessages
        return true
    }

    fun stageDiscussionMessage(text: String, isFollowup: Boolean = false): Boolean {
        if (!canSubmitDiscussionMessage) return false
        val messageText = if (isFollowup) text else normalizeAgentMessageText(text)
        if (messageText.isEmpty()) return false
        messageAuthority = AgentV2AuthorityBinding(AccountStore.activeAccountId)
        pendingDiscussionMessage = AgentMessage(role = AgentMessageRole.USER, text = messageText)
        followupText = text.takeIf { isFollowup }
        messages = openingMessages
        onChange?.invoke()
        return true
    }

    fun stageSupportRequest(): Boolean {
        if (!canRequestSupport) return false
        messageAuthority = AgentV2AuthorityBinding(AccountStore.activeAccountId)
        pendingDiscussionMessage = AgentMessage(
            role = AgentMessageRole.USER,
            text = getAgentSupportRequestText()
        )
        isHeaderSupportRequest = true
        WalletCore.registerObserver(this)
        error = null
        messages = openingMessages
        onChange?.invoke()
        return true
    }

    fun markConsentAccepted() {
        hasConsent = true
        onChange?.invoke()
    }

    suspend fun transcribeAudio(audio: String) = client.transcribe(
        AgentV2TranscriptionRequest(audio = audio, lang = LocaleController.activeLanguage.langCode)
    )

    suspend fun prepareDiscussionSubmission(): Boolean {
        readConsent()
        return hasConsent == true && canSubmitDiscussionMessage
    }

    suspend fun create(shouldAcceptConsent: Boolean = false): AgentV2ThreadSummary? {
        if (isCreating || isDeleted) return null
        if (isDeferredDiscussion) discussionThread?.let { return it }
        isCreating = true
        error = null
        isConsentRequired = false
        messages = openingMessages
        onChange?.invoke()
        try {
            if (isDeferredDiscussion && pendingDiscussionMessage != null) {
                readConsent()
                if (hasConsent != true) return null
                if (!isHeaderSupportRequest) {
                    getInputLimitCode()?.let {
                        throw AgentV2OperationException(AgentV2MutationError(it, retryable = true))
                    }
                }
            }
            val chat = loader.load(
                shouldAcceptConsent,
                hasMessage =
                    pendingDiscussionMessage != null
            )
            if (isDeleted) return null
            if (chat == null) {
                isConsentRequired = true
                return null
            }
            val thread = chat.thread ?: return null
            messages = if (thread.messageCount == 0 || isDeferredDiscussion) {
                openingMessages
            } else {
                emptyList()
            }
            val preview = news?.newsPostCard()
            val serverNews = thread.news
            return thread.copy(
                news = serverNews?.copy(
                    body = serverNews.body ?: preview?.body,
                    sources = serverNews.sources ?: preview?.sources
                ) ?: preview
            ).also { if (isDeferredDiscussion) discussionThread = it }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (isDeleted) return null
            this.error = error
            messages = openingMessages.take(1).map { it.copy(isStreaming = false) }
            failHeldReports()
            return null
        } finally {
            if (isHeaderSupportRequest) {
                if (discussionThread == null) {
                    dropStagedSupportRequest()
                } else {
                    WalletCore.unregisterObserver(this)
                }
            }
            isCreating = false
            onChange?.invoke()
        }
    }

    /** Reads whether the user has allowed the Agent, alongside the creation, which asks only for a question */
    suspend fun readConsent() {
        if (hasConsent != true) {
            val isAllowed = try {
                client.consent()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return
            }
            hasConsent = isAllowed || hasConsent == true
            onChange?.invoke()
        }
        if (hasConsent == true) loadLimits()
    }

    private suspend fun loadLimits() {
        if (!isDeferredDiscussion || hasConsent != true || areLimitsLoaded) return
        limitsRequest?.let {
            it.await()
            return
        }
        val request = CompletableDeferred<Unit>()
        limitsRequest = request
        try {
            client.loadAvailability()
            client.loadUserQuota()
            areLimitsLoaded = true
        } catch (error: CancellationException) {
            request.cancel(error)
            throw error
        } catch (_: Throwable) {
            // The SDK's optional probes leave the server to enforce limits when unavailable
            areLimitsLoaded = true
        } finally {
            limitsRequest = null
            request.complete(Unit)
            onChange?.invoke()
        }
    }

    private fun getInputLimitCode(): String? =
        getAgentInputLimitCode(availability, userQuota, System.currentTimeMillis())

    fun onBridgeUpdate(update: ApiUpdate) {
        if (!isDeferredDiscussion) return
        when (val agentUpdate = (update as? ApiUpdate.ApiUpdateAgentV2)?.update) {
            is AgentV2Update.AvailabilityChanged -> availability = agentUpdate.availability
            is AgentV2Update.UserQuotaChanged -> userQuota = agentUpdate.quota
            else -> return
        }
        onChange?.invoke()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (!isHeaderSupportRequest) return
        when (walletEvent) {
            is WalletEvent.AccountWillChange,
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp,
            WalletEvent.AccountChangeAborted,
            is WalletEvent.AccountRemoved,
            WalletEvent.AddNewWalletCompletion,
            is WalletEvent.ByChainUpdated,
            is WalletEvent.TemporaryAccountSaved,
            WalletEvent.AccountsReset -> {
                dropStagedSupportRequest()
                onChange?.invoke()
            }

            else -> Unit
        }
    }

    /** Holds a report of the conversation until [releaseHeldReports] hands it to the chat the thread opens */
    fun reportProblem(comment: String?, onResult: (Boolean) -> Unit) {
        if (!canReportProblem) return onResult(false)
        heldProblemReports += HeldProblemReport(comment, onResult)
    }

    /** Hands each report held while the thread was being created to [report], once */
    fun releaseHeldReports(report: (comment: String?, onResult: (Boolean) -> Unit) -> Unit) {
        val reports = heldProblemReports.toList()
        heldProblemReports.clear()
        reports.forEach { report(it.comment, it.onResult) }
    }

    /** Cleans up only a creation request already started; without one there is nothing to delete. */
    fun deleteChat(onFailure: (Throwable) -> Unit) {
        if (isDeleted) return
        isDeleted = true
        onChange = null
        error = null
        dropStagedSupportRequest()
        failHeldReports()
        val request = creationRequest ?: return
        val cleanupScope = creationScope ?: return
        cleanupScope.launch {
            try {
                val thread = try {
                    request.await().getOrNull()
                } catch (_: CancellationException) {
                    null
                } ?: return@launch
                try {
                    client.deleteThread(thread.id)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    onFailure(error)
                }
            } finally {
                creationRequest = null
                creationScope = null
                cleanupScope.cancel()
            }
        }
    }

    // A report held for a thread that won't come fails, as one the server refuses does
    private fun failHeldReports() {
        val reports = heldProblemReports.toList()
        heldProblemReports.clear()
        reports.forEach { it.onResult(false) }
    }

    private suspend fun ensureOpeningIsActive() {
        currentCoroutineContext().ensureActive()
        if (isDeleted) throw CancellationException("Chat opening was deleted")
    }

    private suspend fun createThread(news: AgentV2ThreadNewsRequest?): AgentV2ThreadSummary {
        ensureOpeningIsActive()
        // Cancelling the creation cancels its request; only Delete keeps it running, to delete the created thread
        val requestScope = CoroutineScope(currentCoroutineContext() + SupervisorJob())
        val request = requestScope.async(start = CoroutineStart.UNDISPATCHED) {
            ensureOpeningIsActive()
            try {
                val newsRequest = news ?: this@AgentChatOpening.news?.let {
                    val locale = feedClient.getNewsFeed(
                        LocaleController.activeLanguage.langCode,
                        null,
                        AgentNewsDigestSchedule.current()
                    ).locale
                    AgentV2ThreadNewsRequest(it.eventId, locale)
                }
                Result.success(
                    client.createThread(
                        newsRequest,
                        digestId?.let(::AgentV2ThreadDigestRequest)
                    ).thread
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Result.failure(error)
            }
        }
        creationScope = requestScope
        creationRequest = request
        try {
            return request.await().getOrThrow()
        } finally {
            if (!isDeleted) {
                requestScope.cancel()
                creationScope = null
                creationRequest = null
            }
        }
    }

    private fun dropStagedSupportRequest() {
        if (!isHeaderSupportRequest) return
        WalletCore.unregisterObserver(this)
        pendingDiscussionMessage = null
        messageAuthority = null
        isHeaderSupportRequest = false
        messages = openingMessages
    }
}

/** Identifies a discussion whose thread its first message creates, or null for any other opening */
internal fun getAgentDeferredDiscussionKey(
    news: AgentNewsChatRequest?,
    digestId: String?,
    shouldDeferCreation: Boolean
): String? = when {
    news?.shouldDeferCreation == true && news.threadId == null ->
        "news:${news.eventId}:${news.locale}"

    digestId != null && shouldDeferCreation -> "digest:$digestId"

    else -> null
}

private class HeldProblemReport(val comment: String?, val onResult: (Boolean) -> Unit)

internal suspend fun hydrateAgentOpeningThread(
    thread: AgentV2ThreadSummary,
    loadMessages: suspend (String) -> AgentV2ThreadHydration
): AgentV2ThreadHydration = if (thread.messageCount == 0) {
    AgentV2ThreadHydration(thread, emptyList())
} else {
    hydrateAgentThread(thread, loadMessages)
}
