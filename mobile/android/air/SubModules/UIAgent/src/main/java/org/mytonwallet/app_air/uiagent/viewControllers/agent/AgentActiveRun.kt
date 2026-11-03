package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

// Matches `FAILED_RUN_RETRY_GRACE_MS` in `src/api/agentV2/runtime.ts`
private const val FAILED_RUN_RETRY_GRACE_MS = 5 * 60_000L

// Matches `FAILED_RUN_RETRY_MAX_TTL_MS` (`UTC_DAY_MS`) in `src/api/agentV2/runtime.ts`
private const val FAILED_RUN_RETRY_MAX_TTL_MS = 24 * 60 * 60_000L

internal class AgentActiveRun(
    val inputPresentationId: String,
    val authority: AgentV2AuthorityBinding,
    val editedMessage: AgentMessage? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val regenerationTargetId: String? = null
) {
    var isEditAdmitted = false
    var assistantPresentationId: String? = null
    var hasStartedAssistant = false
    var hasReceivedStreamEvent = false
    var hasFailed = false
    var failureCode: String? = null
    var shouldResyncThread = false

    /** Set when a limit stopped the run before it started, so it can go again once the limit resets */
    var limitRetry: AgentLimitRetry? = null
    var clientRunId: String? = null
        private set
    var runId: String? = null
        private set

    fun bind(clientRunId: String, runId: String?): Boolean {
        val currentClientRunId = this.clientRunId
        if (currentClientRunId != null && currentClientRunId != clientRunId) return false
        val currentRunId = this.runId
        if (currentRunId != null && runId != null && currentRunId != runId) return false
        this.clientRunId = clientRunId
        if (runId != null) this.runId = runId
        return true
    }

    fun matches(clientRunId: String, runId: String): Boolean =
        this.clientRunId == clientRunId && this.runId == runId
}

/**
 * A request that a limit stopped before any stream event. Retry expires five minutes after the limit resets
 * (or after the failure when no reset time is known), or one day after the failure, whichever comes first.
 */
internal data class AgentLimitRetry(
    val clientRunId: String,
    val isRateLimit: Boolean,
    val resetAt: Long?,
    val failedAt: Long,
    val inputPresentationId: String? = null,
    val failureMessageId: String? = null,
    val editedMessage: AgentMessage? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val regenerationTargetId: String? = null
) {
    val expiresAt: Long
        get() = minOf(
            (resetAt ?: failedAt) + FAILED_RUN_RETRY_GRACE_MS,
            failedAt + FAILED_RUN_RETRY_MAX_TTL_MS
        )
}

internal fun AgentV2Update.RunFailed.toLimitRetry(
    hasReceivedStreamEvent: Boolean,
    failedAt: Long
): AgentLimitRetry? {
    if (!retryable || hasReceivedStreamEvent) return null
    val isRateLimit = when {
        code == "rate_limited" -> true
        code == "user_quota_exhausted" && runId == null -> false
        else -> return null
    }
    return AgentLimitRetry(clientRunId, isRateLimit, resetAt, failedAt)
}
