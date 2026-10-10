package org.mytonwallet.app_air.walletcore.moshi.agentV2

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AgentV2HostContextUpdate(val authorityChanged: Boolean, val generation: Int)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadSummary(val id: String, val revision: Int)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadResponse(val thread: AgentV2ThreadSummary)

@JsonClass(generateAdapter = true)
data class AgentV2ProblemReportResponse(val reportId: String, val duplicate: Boolean)

@JsonClass(generateAdapter = true)
data class AgentV2MutationError(val code: String, val retryable: Boolean)

@JsonClass(generateAdapter = true)
data class AgentV2MutationResult<T>(
    val ok: Boolean,
    val value: T? = null,
    val error: AgentV2MutationError? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2MessageError(
    val code: String,
    val retryable: Boolean,
    val retryAfterMs: Int? = null,
    val resetAt: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2AnswerTable(val id: String, val content: AgentV2DisplayTable)

@JsonClass(generateAdapter = true)
data class AgentV2DisplayTable(
    val kind: String,
    val headers: List<String>,
    val rows: List<List<String>>,
    val notes: List<String>
)

@JsonClass(generateAdapter = true)
data class AgentV2AnswerTableReference(val tableId: String, val textOffset: Int)

/** A link over a label of answer text; offsets are UTF-16 and share the space of table references */
@JsonClass(generateAdapter = true)
data class AgentV2AnswerLink(val textOffset: Int, val textLength: Int, val url: String)

sealed class AgentV2MessageContent {
    @JsonClass(generateAdapter = true)
    data class Markdown(
        val text: String,
        val tables: List<AgentV2AnswerTable> = emptyList(),
        val tableReferences: List<AgentV2AnswerTableReference> = emptyList(),
        val links: List<AgentV2AnswerLink> = emptyList()
    ) : AgentV2MessageContent()

    @JsonClass(generateAdapter = true)
    data class Semantic(val content: Map<String, Any>? = null) : AgentV2MessageContent()
}

@JsonClass(generateAdapter = true)
data class AgentV2Action(val id: String, val kind: String, val title: String)

@JsonClass(generateAdapter = true)
data class AgentV2FollowUp(val id: String, val kind: String, val text: String)

@JsonClass(generateAdapter = true)
data class AgentV2FollowUpReference(val messageId: String, val followupId: String)

@JsonClass(generateAdapter = true)
data class AgentV2PersistedMessage(
    val id: String,
    val threadId: String,
    val role: String,
    val status: String,
    val content: AgentV2MessageContent? = null,
    val createdAt: String,
    val runId: String? = null,
    val error: AgentV2MessageError? = null,
    val actions: List<AgentV2Action>? = null,
    val followups: List<AgentV2FollowUp>? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadHydration(
    val thread: AgentV2ThreadSummary,
    val messages: List<AgentV2PersistedMessage>,
    val nextCursor: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2StarterHint(val id: String, val requiredCapabilities: List<String>? = null)

@JsonClass(generateAdapter = true)
data class AgentV2HintsResponse(
    val protocolVersion: Int,
    val catalogVersion: String,
    val items: List<AgentV2StarterHint>
)

@JsonClass(generateAdapter = true)
data class AgentV2AssetRef(val slug: String, val chain: String, val tokenAddress: String? = null)

@JsonClass(generateAdapter = true)
data class AgentV2EntryPoint(
    val kind: String = "agentTab",
    val chartId: String? = null,
    val range: String? = null,
    val accountScope: String? = null,
    val source: String? = null,
    val asset: AgentV2AssetRef? = null,
    val query: String? = null,
    val surface: String? = null,
    val hintId: String? = null,
    val catalogVersion: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2RunResult(
    val clientRunId: String,
    val runId: String? = null,
    val inputMessageId: String? = null,
    val state: String
)

sealed class AgentV2ActionPresentation {
    @JsonClass(generateAdapter = true)
    data class Send(val status: String) : AgentV2ActionPresentation()

    @JsonClass(generateAdapter = true)
    class Inactive : AgentV2ActionPresentation()
}

sealed class AgentV2ResolvedAction {
    @JsonClass(generateAdapter = true)
    data class OpenReceive(val chain: String) : AgentV2ResolvedAction()

    @JsonClass(generateAdapter = true)
    data class OpenStaking(
        val productId: String,
        val tokenSlug: String,
        val amount: StakeAmount? = null
    ) : AgentV2ResolvedAction() {
        @JsonClass(generateAdapter = true)
        data class StakeAmount(val kind: String, val value: String? = null)
    }

    @JsonClass(generateAdapter = true)
    data class OpenSwap(
        val tokenInSlug: String? = null,
        val tokenOutSlug: String? = null,
        val amount: String? = null,
        val amountSide: String? = null
    ) : AgentV2ResolvedAction()

    @JsonClass(generateAdapter = true)
    data class SendForm(
        val url: String,
        // Send opens with the most the wallet can send of the asset, as its Max button does
        val isMaxAmount: Boolean = false
    ) : AgentV2ResolvedAction()

    @JsonClass(generateAdapter = true)
    data class OpenDapp(val url: String) : AgentV2ResolvedAction()

    @JsonClass(generateAdapter = true)
    class Inactive : AgentV2ResolvedAction()
}

sealed class AgentV2Update {
    abstract val threadId: String?

    @JsonClass(generateAdapter = true)
    data class RunStarted(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val threadRevision: Int,
        val inputMessageId: String? = null
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class MessageStarted(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val contentKind: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class TextDelta(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val delta: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class AnswerTablesChanged(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val tables: List<AgentV2AnswerTable>,
        val tableReferences: List<AgentV2AnswerTableReference>
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class AnswerLinkAdded(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val link: AgentV2AnswerLink
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class MessageContentEnded(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class MessageCompleted(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val finishReason: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class ActionAvailable(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val action: AgentV2Action
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class FollowupsAvailable(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val items: List<AgentV2FollowUp>
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class SemanticContentAvailable(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val messageId: String,
        val content: Map<String, Any>
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RunFailed(
        val clientRunId: String,
        val runId: String? = null,
        override val threadId: String? = null,
        val code: String,
        val retryable: Boolean
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RunCancelled(
        val clientRunId: String,
        val runId: String,
        override val threadId: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class WalletAuthorityChanged(override val threadId: String? = null) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class ThreadChanged(override val threadId: String, val thread: AgentV2ThreadSummary) :
        AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RuntimeReady(val generation: Int, override val threadId: String? = null) :
        AgentV2Update()
}
