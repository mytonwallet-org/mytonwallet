package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

// Matches `FAILED_RUN_RETRY_GRACE_MS` in `src/api/agentV2/runtime.ts`
private const val FAILED_RUN_RETRY_GRACE_MS = 5 * 60_000L

// Matches `FAILED_RUN_RETRY_MAX_TTL_MS` (`UTC_DAY_MS`) in `src/api/agentV2/runtime.ts`
private const val FAILED_RUN_RETRY_MAX_TTL_MS = 24 * 60 * 60_000L

/** A run the chat follows; the chat chooses its [clientRunId] before the SDK sees it, so every update is told apart */
internal class AgentActiveRun(
    val clientRunId: String,
    val inputPresentationId: String,
    val authority: AgentV2AuthorityBinding,
    /** A support request, which a limit never holds back for Retry */
    val isSupportRequest: Boolean = false,
    var canResendSupportConflict: Boolean = false,
    val editedMessage: AgentMessage? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val regenerationTargetId: String? = null,
    /**
     * The stopped answers an edit or a regeneration replaces, forgotten once the server admits the run. Until then a
     * history read leaves them out; a run that fails before admission keeps them.
     */
    var replacedStoppedAnswerIds: Set<String> = emptySet()
) {
    var isEditAdmitted = false
    var assistantPresentationId: String? = null

    /** The answers the run's updates have written to */
    val answerMessageIds = mutableSetOf<String>()
    var hasStartedAssistant = false
    var hasDeliveredToSupport = false
    var hasReceivedStreamEvent = false
    var hasFailed = false
    var shouldResendSupportConflict = false
    var failureCode: String? = null
    var shouldResyncThread = false

    /** Set when a limit stopped the run before it started, so it can go again once the limit resets */
    var limitRetry: AgentLimitRetry? = null
    var runId: String? = null
        private set

    fun bind(clientRunId: String, runId: String?): Boolean {
        if (clientRunId != this.clientRunId) return false
        val currentRunId = this.runId
        if (currentRunId != null && runId != null && currentRunId != runId) return false
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
    /** The wallet the question was asked for, the only one the SDK sends it again for */
    val authority: AgentV2AuthorityBinding,
    val inputPresentationId: String? = null,
    val failureMessageId: String? = null,
    val editedMessage: AgentMessage? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val regenerationTargetId: String? = null,
    val replacedStoppedAnswerIds: Set<String> = emptySet(),
    /**
     * The limit blocked new questions when it held this one back, so the questions queued behind
     * it wait for it, and it goes first, by itself, once the limit resets
     */
    val isHoldingQueue: Boolean = false
) {
    val expiresAt: Long
        get() = minOf(
            (resetAt ?: failedAt) + FAILED_RUN_RETRY_GRACE_MS,
            failedAt + FAILED_RUN_RETRY_MAX_TTL_MS
        )
}

internal fun AgentV2Update.RunFailed.toLimitRetry(
    hasReceivedStreamEvent: Boolean,
    failedAt: Long,
    authority: AgentV2AuthorityBinding
): AgentLimitRetry? {
    if (!retryable || hasReceivedStreamEvent) return null
    val isRateLimit = when {
        code == "rate_limited" -> true
        code == "user_quota_exhausted" && runId == null -> false
        else -> return null
    }
    return AgentLimitRetry(clientRunId, isRateLimit, resetAt, failedAt, authority)
}
