package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

data class AgentNewsChatRequest(
    val eventId: Int,
    val locale: String,
    val headline: String,
    val icon: String? = null,
    val threadId: String? = null,
    val excerpt: String? = null,
    val imageUrl: String? = null,
    val publishedAt: String? = null,
    val body: String? = null,
    val sources: List<AgentV2NewsFeedItem.Source>? = null
)

data class AgentPromptChatRequest(
    val prompt: String,
    val entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()
)

internal class AgentChatOpening(
    private val prompt: AgentPromptChatRequest? = null,
    private val news: AgentNewsChatRequest? = null,
    private val client: AgentV2Client = LiveAgentV2Client()
) {
    init {
        require((prompt == null) != (news == null)) { "An opening requires one chat request" }
    }

    private val loader = AgentNewChatLoader(
        {
            ensureOpeningIsActive()
            client.consent()
        },
        {
            ensureOpeningIsActive()
            client.acceptConsent()
        },
        ::createThread,
        news?.let { AgentV2ThreadNewsRequest(it.eventId, it.locale) }
    )
    private val openingMessages = prompt?.let {
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
    val entryPoint = prompt?.entryPoint ?: AgentV2EntryPoint()
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
    var onChange: (() -> Unit)? = null
    private var isDeleted = false
    private var creationScope: CoroutineScope? = null
    private var creationRequest: Deferred<Result<AgentV2ThreadSummary>>? = null

    fun acquireDiscussion(
        acquire: (AgentV2ThreadSummary) -> AgentVM = AgentSession::acquire
    ): AgentVM? = discussionThread?.let(acquire)

    fun recreateMissingDiscussion(errorCode: String?): Boolean {
        if (discussionThread == null || errorCode != "thread_not_found") return false
        discussionThread = null
        messages = openingMessages
        return true
    }

    suspend fun create(shouldAcceptConsent: Boolean = false): AgentV2ThreadSummary? {
        if (isCreating || isDeleted) return null
        isCreating = true
        error = null
        isConsentRequired = false
        messages = openingMessages
        onChange?.invoke()
        try {
            val chat = loader.load(shouldAcceptConsent)
            if (isDeleted) return null
            if (chat == null) {
                isConsentRequired = true
                return null
            }
            val thread = chat.thread
            messages = if (thread.messageCount == 0) openingMessages else emptyList()
            val preview = news?.newsPostCard() ?: return thread
            val serverNews = thread.news
            return thread.copy(
                news = serverNews?.copy(
                    body = serverNews.body ?: preview.body,
                    sources = serverNews.sources ?: preview.sources
                ) ?: preview
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (isDeleted) return null
            this.error = error
            messages = openingMessages.take(1).map { it.copy(isStreaming = false) }
            return null
        } finally {
            isCreating = false
            onChange?.invoke()
        }
    }

    /** Cleans up only a creation request already started; without one there is nothing to delete. */
    fun deleteChat(onFailure: (Throwable) -> Unit) {
        if (isDeleted) return
        isDeleted = true
        onChange = null
        error = null
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

    private suspend fun ensureOpeningIsActive() {
        currentCoroutineContext().ensureActive()
        if (isDeleted) throw CancellationException("Chat opening was deleted")
    }

    private suspend fun createThread(news: AgentV2ThreadNewsRequest?): AgentV2ThreadSummary {
        ensureOpeningIsActive()
        // Navigation cancels creation; only Delete keeps it running, to delete the created thread
        val requestScope = CoroutineScope(currentCoroutineContext() + SupervisorJob())
        val request = requestScope.async(start = CoroutineStart.UNDISPATCHED) {
            ensureOpeningIsActive()
            try {
                Result.success(client.createThread(news).thread)
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
}

internal suspend fun hydrateAgentOpeningThread(
    thread: AgentV2ThreadSummary,
    loadMessages: suspend (String) -> AgentV2ThreadHydration
): AgentV2ThreadHydration = if (thread.messageCount == 0) {
    AgentV2ThreadHydration(thread, emptyList())
} else {
    hydrateAgentThread(thread, loadMessages)
}
