package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.getAgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.api.getAgentV2CachedThreads
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerFeedbackResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadCreateResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDeleteResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadUpdate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionResponse
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

interface AgentV2Client {
    /** The user's consent as the app last read or gave it, known at once: false until then */
    val isConsentKnownGiven: Boolean get() = false

    suspend fun consent(): Boolean
    suspend fun acceptConsent()
    suspend fun updateHostContext(context: JSONObject?)
    suspend fun setChatActive(isActive: Boolean)
    suspend fun hints(langCode: String?): AgentV2HintsResponse
    suspend fun problemReportAvailability(): Boolean

    /** Asks for the Agent's availability, which arrives as an `availabilityChanged` update */
    suspend fun loadAvailability() {}

    /** Asks for the user's quota, which arrives as a `userQuotaChanged` update */
    suspend fun loadUserQuota() {}

    suspend fun listThreads(
        cursor: String? = null,
        limit: Int? = null,
        query: String? = null
    ): AgentV2ThreadListResponse

    /** The device's copy of the first page of chats; null when there is none */
    suspend fun getCachedThreads(): List<AgentV2ThreadListItem>?
    suspend fun createThread(
        news: AgentV2ThreadNewsRequest? = null,
        digest: AgentV2ThreadDigestRequest? = null
    ): AgentV2ThreadCreateResponse
    suspend fun updateThread(threadId: String, update: AgentV2ThreadUpdate): AgentV2ThreadResponse
    suspend fun deleteThread(threadId: String): AgentV2ThreadDeleteResponse
    suspend fun messages(threadId: String, cursor: String?, limit: Int): AgentV2ThreadHydration

    /** The device's copy of the thread's latest messages; null when there is none */
    suspend fun getCachedMessages(threadId: String): AgentV2CachedMessages?

    /** Starts a run that the SDK reports under [clientRunId], which the caller chooses before the call */
    suspend fun startRun(
        clientRunId: String,
        threadId: String?,
        revision: Int,
        text: String,
        entryPoint: AgentV2EntryPoint? = null,
        followupOf: AgentV2FollowUpReference? = null,
        targetUserMessageId: String? = null,
        targetAssistantMessageId: String? = null
    ): AgentV2RunResult

    /** Sends again a run that a limit stopped before it started; null when the SDK no longer holds it */
    suspend fun retryRun(clientRunId: String): AgentV2RunResult? = null
    suspend fun cancelRun(runId: String): AgentV2ThreadResponse

    /** Stops every run of [threadId] the SDK holds; the SDK cancels it on the server and reloads the thread */
    suspend fun stopRun(threadId: String)
    suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse
    suspend fun reportProblem(threadId: String, messageId: String?, comment: String?)
    suspend fun transcribe(request: AgentV2TranscriptionRequest): AgentV2TranscriptionResponse
    suspend fun setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: String?
    ): AgentV2AnswerFeedbackResponse
    suspend fun actionPresentation(messageId: String, actionId: String): AgentV2ActionPresentation
    suspend fun resolveAction(messageId: String, actionId: String): AgentV2ResolvedAction
}

class LiveAgentV2Client : AgentV2Client {
    override val isConsentKnownGiven: Boolean get() = isConsentGiven

    override suspend fun consent() =
        WalletCore.call(ApiMethod.AgentV2.GetConsent()).also { isConsentGiven = it }

    override suspend fun acceptConsent() {
        WalletCore.call(ApiMethod.AgentV2.AcceptConsent())
        isConsentGiven = true
    }

    override suspend fun updateHostContext(context: JSONObject?) {
        // The context holds whole asset catalogs, which take long to serialize and quote for the SDK
        withContext(Dispatchers.Default) {
            callAgentV2Mutation(ApiMethod.AgentV2.UpdateHostContext(context))
        }
    }

    override suspend fun setChatActive(isActive: Boolean) {
        WalletCore.call(ApiMethod.AgentV2.SetChatActive(isActive))
    }

    override suspend fun hints(langCode: String?) =
        WalletCore.call(ApiMethod.AgentV2.GetHints(langCode))

    override suspend fun problemReportAvailability() =
        WalletCore.call(ApiMethod.AgentV2.GetProblemReportAvailability())

    override suspend fun loadAvailability() {
        WalletCore.call(ApiMethod.AgentV2.GetAvailability())
    }

    override suspend fun loadUserQuota() {
        WalletCore.call(ApiMethod.AgentV2.GetUserQuota())
    }

    override suspend fun listThreads(
        cursor: String?,
        limit: Int?,
        query: String?
    ): AgentV2ThreadListResponse =
        callAgentV2Mutation(ApiMethod.AgentV2.ListThreads(cursor, limit, query))

    override suspend fun getCachedThreads() = WalletCore.getAgentV2CachedThreads()

    override suspend fun createThread(
        news: AgentV2ThreadNewsRequest?,
        digest: AgentV2ThreadDigestRequest?
    ): AgentV2ThreadCreateResponse =
        callAgentV2Mutation(ApiMethod.AgentV2.CreateThread(news, digest)).also {
            if (it.created) WalletCore.notifyEvent(WalletEvent.AgentThreadCreated)
        }

    override suspend fun updateThread(
        threadId: String,
        update: AgentV2ThreadUpdate
    ): AgentV2ThreadResponse = callAgentV2Mutation(ApiMethod.AgentV2.UpdateThread(threadId, update))

    override suspend fun deleteThread(threadId: String): AgentV2ThreadDeleteResponse =
        callAgentV2Mutation(ApiMethod.AgentV2.DeleteThread(threadId)).also {
            WalletCore.notifyEvent(WalletEvent.AgentThreadDeleted(it.threadId))
        }

    override suspend fun messages(
        threadId: String,
        cursor: String?,
        limit: Int
    ): AgentV2ThreadHydration =
        callAgentV2Mutation(ApiMethod.AgentV2.GetMessages(threadId, cursor, limit))

    override suspend fun getCachedMessages(threadId: String) =
        WalletCore.getAgentV2CachedMessages(threadId)

    override suspend fun startRun(
        clientRunId: String,
        threadId: String?,
        revision: Int,
        text: String,
        entryPoint: AgentV2EntryPoint?,
        followupOf: AgentV2FollowUpReference?,
        targetUserMessageId: String?,
        targetAssistantMessageId: String?
    ) = WalletCore.call(
        ApiMethod.AgentV2.StartRun(
            threadId,
            revision,
            text,
            entryPoint,
            followupOf,
            targetUserMessageId,
            targetAssistantMessageId,
            clientRunId
        )
    )

    override suspend fun retryRun(clientRunId: String) =
        WalletCore.call(ApiMethod.AgentV2.RetryRun(clientRunId))

    override suspend fun cancelRun(runId: String) =
        WalletCore.call(ApiMethod.AgentV2.CancelRun(runId))

    override suspend fun stopRun(threadId: String) {
        WalletCore.call(ApiMethod.AgentV2.StopRun(threadId))
    }

    override suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse =
        callAgentV2Mutation(ApiMethod.AgentV2.ClearThread(threadId, revision))

    override suspend fun reportProblem(threadId: String, messageId: String?, comment: String?) {
        callAgentV2Mutation(ApiMethod.AgentV2.ReportProblem(threadId, messageId, comment))
    }

    override suspend fun transcribe(request: AgentV2TranscriptionRequest) =
        callAgentV2Mutation(ApiMethod.AgentV2.Transcribe(request))

    override suspend fun setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: String?
    ) = callAgentV2Mutation(ApiMethod.AgentV2.SetMessageFeedback(threadId, messageId, feedback))

    override suspend fun resolveAction(messageId: String, actionId: String) =
        WalletCore.call(ApiMethod.AgentV2.ResolveAction(messageId, actionId))

    override suspend fun actionPresentation(messageId: String, actionId: String) =
        WalletCore.call(ApiMethod.AgentV2.GetActionPresentation(messageId, actionId))

    companion object {
        // Shared by every chat and list, so that a chat opening knows the consent from its first frame
        @Volatile
        private var isConsentGiven = false

        // A reset of the accounts deletes the consent
        internal fun forgetKnownConsent() {
            isConsentGiven = false
        }
    }
}

internal suspend fun <T> callAgentV2Mutation(method: ApiMethod<AgentV2MutationResult<T>>): T {
    val result = try {
        WalletCore.call(method)
    } catch (error: JSWebViewBridge.ApiError) {
        val mutationError = (error.parsedResult as? AgentV2MutationResult<*>)?.error ?: throw error
        throw AgentV2OperationException(mutationError, error)
    }
    result.error?.let { throw AgentV2OperationException(it) }
    return requireNotNull(result.value.takeIf { result.ok }) { "invalid_response" }
}

internal class AgentV2OperationException(
    val error: AgentV2MutationError,
    cause: Throwable? = null
) : Exception(error.code, cause)
