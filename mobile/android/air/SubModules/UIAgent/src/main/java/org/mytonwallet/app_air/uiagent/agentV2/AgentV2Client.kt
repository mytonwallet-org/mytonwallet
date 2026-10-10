package org.mytonwallet.app_air.uiagent.agentV2

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUpReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2HintsResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MutationResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadHydration
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadResponse
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

interface AgentV2Client {
    suspend fun consent(): Boolean
    suspend fun acceptConsent()
    suspend fun updateHostContext(context: JSONObject?)
    suspend fun setChatActive(isActive: Boolean)
    suspend fun hints(langCode: String?): AgentV2HintsResponse
    suspend fun problemReportAvailability(): Boolean
    suspend fun defaultThread(): AgentV2ThreadResponse
    suspend fun messages(threadId: String, cursor: String?, limit: Int): AgentV2ThreadHydration
    suspend fun startRun(
        threadId: String?,
        revision: Int,
        text: String,
        entryPoint: AgentV2EntryPoint? = null,
        followupOf: AgentV2FollowUpReference? = null,
        targetUserMessageId: String? = null,
        targetAssistantMessageId: String? = null
    ): AgentV2RunResult
    suspend fun cancelRun(runId: String): AgentV2ThreadResponse
    suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse
    suspend fun reportProblem(threadId: String, messageId: String?, comment: String?)
    suspend fun actionPresentation(messageId: String, actionId: String): AgentV2ActionPresentation
    suspend fun resolveAction(messageId: String, actionId: String): AgentV2ResolvedAction
}

class LiveAgentV2Client : AgentV2Client {
    override suspend fun consent() = WalletCore.call(ApiMethod.AgentV2.GetConsent())

    override suspend fun acceptConsent() {
        WalletCore.call(ApiMethod.AgentV2.AcceptConsent())
    }

    override suspend fun updateHostContext(context: JSONObject?) {
        callAgentV2Mutation(ApiMethod.AgentV2.UpdateHostContext(context))
    }

    override suspend fun setChatActive(isActive: Boolean) {
        WalletCore.call(ApiMethod.AgentV2.SetChatActive(isActive))
    }

    override suspend fun hints(langCode: String?) =
        WalletCore.call(ApiMethod.AgentV2.GetHints(langCode))

    override suspend fun problemReportAvailability() =
        WalletCore.call(ApiMethod.AgentV2.GetProblemReportAvailability())

    override suspend fun defaultThread() = callAgentV2Mutation(ApiMethod.AgentV2.GetDefaultThread())

    override suspend fun messages(
        threadId: String,
        cursor: String?,
        limit: Int
    ): AgentV2ThreadHydration =
        callAgentV2Mutation(ApiMethod.AgentV2.GetMessages(threadId, cursor, limit))

    override suspend fun startRun(
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
            targetAssistantMessageId
        )
    )

    override suspend fun cancelRun(runId: String) =
        WalletCore.call(ApiMethod.AgentV2.CancelRun(runId))

    override suspend fun clearThread(threadId: String, revision: Int): AgentV2ThreadResponse =
        callAgentV2Mutation(ApiMethod.AgentV2.ClearThread(threadId, revision))

    override suspend fun reportProblem(threadId: String, messageId: String?, comment: String?) {
        callAgentV2Mutation(ApiMethod.AgentV2.ReportProblem(threadId, messageId, comment))
    }

    override suspend fun resolveAction(messageId: String, actionId: String) =
        WalletCore.call(ApiMethod.AgentV2.ResolveAction(messageId, actionId))

    override suspend fun actionPresentation(messageId: String, actionId: String) =
        WalletCore.call(ApiMethod.AgentV2.GetActionPresentation(messageId, actionId))
}

private suspend fun <T> callAgentV2Mutation(method: ApiMethod<AgentV2MutationResult<T>>): T {
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
