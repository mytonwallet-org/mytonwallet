package org.mytonwallet.app_air.walletcore.moshi.agentV2

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonClass
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import org.mytonwallet.app_air.walletcore.pushNotifications.AGENT_NEWS_DIGEST_MINUTES

@JsonClass(generateAdapter = true)
data class AgentV2HostContextUpdate(val authorityChanged: Boolean, val generation: Int)

@JsonClass(generateAdapter = true)
data class AgentV2NewsFeedItem(
    val eventId: Int,
    val deliveredAt: String,
    val headline: String,
    val body: String,
    val imageUrl: String? = null,
    val sources: List<Source>,
    val discussion: Discussion? = null,
    val discussionNaming: DiscussionNaming? = null
) {
    @JsonClass(generateAdapter = true)
    data class Source(val name: String? = null, val url: String)

    @JsonClass(generateAdapter = true)
    data class Discussion(val threadId: String, val icon: String? = null)

    data class DiscussionNaming(
        val title: String,
        val icon: String? = null,
        val followups: List<String>
    )
}

internal object AgentV2DiscussionNamingAdapter :
    JsonAdapter<AgentV2NewsFeedItem.DiscussionNaming>() {
    override fun fromJson(reader: JsonReader): AgentV2NewsFeedItem.DiscussionNaming? {
        val value = reader.readJsonValue() as? Map<*, *> ?: return null
        val title = value["title"] as? String ?: return null
        val icon = value["icon"]
        if (icon != null && icon !is String) return null
        val followups = value["followups"] as? List<*> ?: return null
        return AgentV2NewsFeedItem.DiscussionNaming(
            title,
            icon,
            followups.map { it as? String ?: return null }
        )
    }

    override fun toJson(writer: JsonWriter, value: AgentV2NewsFeedItem.DiscussionNaming?) {
        if (value == null) {
            writer.nullValue()
            return
        }
        writer.beginObject()
        writer.name("title").value(value.title)
        writer.name("icon").value(value.icon)
        writer.name("followups").beginArray()
        value.followups.forEach { writer.value(it) }
        writer.endArray()
        writer.endObject()
    }
}

@JsonClass(generateAdapter = true)
data class AgentV2NewsFeedPage(
    val locale: String,
    val items: List<AgentV2NewsFeedItem>,
    val nextCursor: String? = null,
    val digests: List<AgentV2NewsFeedDigest>? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2NewsDigestHeadline(
    val eventId: Int,
    val headline: String,
    /** The news item's picture, as the feed shows it */
    val imageUrl: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2NewsFeedDigest(
    val id: String,
    val deliveredAt: String,
    val top: List<AgentV2NewsDigestHeadline>,
    val total: Int,
    val discussion: AgentV2NewsFeedItem.Discussion? = null,
    val discussionNaming: AgentV2NewsFeedItem.DiscussionNaming? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2NewsFeedRequest(
    val lang: String,
    val cursor: String? = null,
    val digestHour: Int? = null,
    val digestMinute: Int? = null,
    val timeZone: String? = null,
    val view: String? = null
) {
    init {
        require((digestHour == null) == (timeZone == null))
        require(digestHour == null || digestHour in 0..23)
        require(digestMinute == null || digestHour != null)
        require(digestMinute == null || digestMinute in AGENT_NEWS_DIGEST_MINUTES)
        require(view == null || view == "digests")
    }
}

@JsonClass(generateAdapter = true)
data class AgentV2ThreadDigestCard(
    val id: String,
    val windowEnd: String,
    val total: Int,
    val top: List<AgentV2NewsDigestHeadline>
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadNewsCard(
    val eventId: Int,
    val headline: String,
    val excerpt: String? = null,
    val imageUrl: String? = null,
    val publishedAt: String,
    val source: String? = null,
    val body: String? = null,
    val sources: List<AgentV2NewsFeedItem.Source>? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadNewsRequest(val eventId: Int, val locale: String)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadDigestRequest(val id: String)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadCreateRequest(
    val news: AgentV2ThreadNewsRequest? = null,
    val digest: AgentV2ThreadDigestRequest? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadSupport(val state: String, val lastOperatorMessageAt: String? = null)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadSummary(
    val id: String,
    val revision: Int,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val lastActivityAt: String? = null,
    val clearedAt: String? = null,
    val messageCount: Int = 0,
    val title: String? = null,
    val icon: String? = null,
    val hasCustomTitle: Boolean? = null,
    val isPinned: Boolean? = null,
    val news: AgentV2ThreadNewsCard? = null,
    val digest: AgentV2ThreadDigestCard? = null,
    val support: AgentV2ThreadSupport? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadListRequest(
    val cursor: String? = null,
    val limit: Int? = null,
    val query: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadListItem(val thread: AgentV2ThreadSummary, val preview: String? = null)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadListResponse(
    val threads: List<AgentV2ThreadListItem>,
    val nextCursor: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadCreateResponse(val thread: AgentV2ThreadSummary, val created: Boolean)

class AgentV2ThreadUpdate private constructor(
    val title: String?,
    val isPinned: Boolean?,
    internal val hasTitle: Boolean
) {
    constructor(title: String?, isPinned: Boolean? = null) : this(title, isPinned, true)

    constructor(isPinned: Boolean) : this(null, isPinned, false)
}

@JsonClass(generateAdapter = true)
data class AgentV2ThreadDeleteResponse(val threadId: String, val duplicate: Boolean)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadResponse(val thread: AgentV2ThreadSummary)

@JsonClass(generateAdapter = true)
data class AgentV2ProblemReportResponse(val reportId: String, val duplicate: Boolean)

@JsonClass(generateAdapter = true)
data class AgentV2TranscriptionRequest(
    val audio: String,
    val format: String = "m4a",
    val lang: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2TranscriptionResponse(val outcome: String, val text: String? = null)

/** The answer's rating after the request; without `feedback` the answer has none */
@JsonClass(generateAdapter = true)
data class AgentV2AnswerFeedbackResponse(val feedback: String? = null)

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
data class AgentV2OperatorAuthor(
    val operatorId: String,
    val name: String,
    val avatarUrl: String? = null
)

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
    val followups: List<AgentV2FollowUp>? = null,
    /** `like` or `dislike` on a rated complete answer */
    val feedback: String? = null,
    val newsPost: Boolean? = null,
    val text: String? = null,
    val author: AgentV2OperatorAuthor? = null,
    val code: String? = null,
    val reason: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2ThreadHydration(
    val thread: AgentV2ThreadSummary,
    val messages: List<AgentV2PersistedMessage>,
    val nextCursor: String? = null
)

@JsonClass(generateAdapter = true)
data class AgentV2CachedMessages(
    val thread: AgentV2ThreadSummary,
    val messages: List<AgentV2PersistedMessage>,
    val hasOlder: Boolean
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
    val catalogVersion: String? = null,
    val eventId: Int? = null
) {
    companion object {
        private const val SUPPORT_REQUEST_KIND = "supportRequest"

        /** The server opens a support ticket with the run's message, without the model */
        fun supportRequest(source: AgentV2SupportRequestSource) =
            AgentV2EntryPoint(kind = SUPPORT_REQUEST_KIND, source = source.value)

        fun isSupportRequest(entryPoint: AgentV2EntryPoint?) =
            entryPoint?.kind == SUPPORT_REQUEST_KIND
    }
}

/** Where the user asked for a support operator */
enum class AgentV2SupportRequestSource(val value: String) {
    STARTER_HINT("starterHint"),
    HEADER("header"),

    // The protocol's source for a chat menu's item, which this app doesn't offer
    MENU("menu")
}

@JsonClass(generateAdapter = true)
data class AgentV2RunResult(
    val clientRunId: String,
    val runId: String? = null,
    val inputMessageId: String? = null,
    val state: String
)

/** A step of a run, such as a web search; the backend reports when it starts and completes */
@JsonClass(generateAdapter = true)
data class AgentV2RunActivityEvent(
    val runId: String,
    val sequence: Int,
    val code: String,
    val status: String,
    val detail: Detail? = null
) {
    @JsonClass(generateAdapter = true)
    data class Detail(val kind: String, val count: Int)
}

/** While `capacity_exhausted`, no run starts until `resetAt` (Unix ms) when it is known */
@JsonClass(generateAdapter = true)
data class AgentV2Availability(val state: String, val resetAt: Long? = null)

@JsonClass(generateAdapter = true)
data class AgentV2UserQuota(val limit: Int, val used: Int, val remaining: Int, val resetAt: String)

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

    /** Without a `reason` the action is no longer available */
    @JsonClass(generateAdapter = true)
    data class Inactive(val reason: String? = null) : AgentV2ResolvedAction()
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
    data class ToolActivityChanged(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val toolCallId: String,
        val toolName: String,
        val operation: String? = null,
        val status: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RunActivityChanged(
        val clientRunId: String,
        val runId: String,
        override val threadId: String,
        val event: AgentV2RunActivityEvent
    ) : AgentV2Update()

    /** A failure of the answer `messageId` when it names one; a limit lasts until `resetAt` (Unix ms) */
    @JsonClass(generateAdapter = true)
    data class RunFailed(
        val clientRunId: String,
        val runId: String? = null,
        override val threadId: String? = null,
        val code: String,
        val retryable: Boolean,
        val messageId: String? = null,
        val resetAt: Long? = null
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RunCancelled(
        val clientRunId: String,
        val runId: String,
        override val threadId: String
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class AvailabilityChanged(
        val availability: AgentV2Availability,
        override val threadId: String? = null
    ) : AgentV2Update()

    /** Without a `quota` the user's quota is unknown */
    @JsonClass(generateAdapter = true)
    data class UserQuotaChanged(
        val quota: AgentV2UserQuota? = null,
        override val threadId: String? = null
    ) : AgentV2Update()

    /** Without a thread, a change that does not `preservesActiveRuns` ends every run */
    @JsonClass(generateAdapter = true)
    data class WalletAuthorityChanged(
        override val threadId: String? = null,
        val preservesActiveRuns: Boolean = false
    ) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class WalletContextChanged(override val threadId: String? = null) : AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class ThreadChanged(override val threadId: String, val thread: AgentV2ThreadSummary) :
        AgentV2Update()

    @JsonClass(generateAdapter = true)
    data class RuntimeReady(val generation: Int, override val threadId: String? = null) :
        AgentV2Update()
}
