package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import java.util.UUID
import org.mytonwallet.app_air.uiagent.agentV2.agentV2AnswerTableText
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

enum class AgentMessageRole {
    ASSISTANT,
    USER,
    SYSTEM
}

data class AgentDeeplink(val title: String, val url: String? = null, val actionId: String? = null)

/** The user's rating of a complete answer, spelled as the server stores it */
enum class AgentAnswerFeedback(val wireValue: String) {
    LIKE("like"),
    DISLIKE("dislike");

    companion object {
        fun fromWireValue(value: String?) = entries.firstOrNull { it.wireValue == value }
    }
}

data class AgentMessage(
    val id: String = UUID.randomUUID().toString(),
    val sdkMessageId: String? = null,
    val role: AgentMessageRole,
    val text: String,
    val answerTables: List<AgentV2AnswerTable> = emptyList(),
    val tableReferences: List<AgentV2AnswerTableReference> = emptyList(),
    /** Links over labels of `text`, which arrive before the text that carries them */
    val links: List<AgentV2AnswerLink> = emptyList(),
    val followups: List<AgentV2FollowUp> = emptyList(),
    val date: Date = Date(),
    val isStreaming: Boolean = false,
    val isAwaitingSemanticContent: Boolean = false,
    /** The step the Agent reports while it works on this answer, before its text arrives */
    val activityText: String? = null,
    /** A system line that tells why the Agent could not answer */
    val isFailure: Boolean = false,
    /** Why the server stores this answer as failed, which shows as a failure line after it */
    val failureText: String? = null,
    val deeplinks: List<AgentDeeplink> = emptyList(),
    /** The server stores the answer as complete, so the user can rate it */
    val isComplete: Boolean = false,
    val feedback: AgentAnswerFeedback? = null,
    val newsPost: Boolean = false
) {
    val hasText: Boolean
        get() = text.isNotEmpty() || tableReferences.any { reference ->
            reference.textOffset == 0 && answerTables.any { it.id == reference.tableId }
        }

    /** The text with its tables spliced in and its links marked for `MarkdownParser` */
    fun formatText(): String = if (tableReferences.isEmpty() && links.isEmpty()) {
        text
    } else {
        agentV2AnswerTableText(text, answerTables, tableReferences, links)
    }

    val hasVisibleBubble: Boolean
        get() = role != AgentMessageRole.ASSISTANT || hasText || isStreaming

    val hasVisibleContent: Boolean
        get() = hasVisibleBubble || deeplinks.isNotEmpty() || followups.isNotEmpty()
}

internal fun AgentMessage.matchesMessageId(messageId: String) =
    id == messageId || sdkMessageId == messageId

private const val FAILURE_LINE_ID_SUFFIX = ":failure"

/**
 * The messages that show, each failure the server stores with an answer as a line after it. The chat's own line of a
 * failure, which shows the chat's status with its Retry, comes right after the answer of the run that failed, so the
 * stored line of that answer doesn't show next to it.
 */
internal fun List<AgentTimelineItem.Message>.insertFailureLines(): List<AgentTimelineItem.Message> {
    val shown = ArrayList<AgentTimelineItem.Message>(size)
    // Walking from the end, whether the next message that shows is the chat's own failure line
    var isBeforeOwnFailure = false
    for (item in asReversed()) {
        val message = item.message
        val failureLine = message.failureText?.takeUnless { isBeforeOwnFailure }?.let { text ->
            AgentMessage(
                id = message.id + FAILURE_LINE_ID_SUFFIX,
                role = AgentMessageRole.SYSTEM,
                text = text,
                date = message.date,
                isFailure = true
            )
        }
        if (!message.hasVisibleContent && failureLine == null) continue
        failureLine?.let { shown.add(AgentTimelineItem.Message(it)) }
        if (message.hasVisibleContent) shown.add(item)
        isBeforeOwnFailure = message.isFailure
    }
    shown.reverse()
    return shown
}

internal fun List<AgentMessage>.findFollowupOwner(): AgentMessage? =
    lastOrNull { it.role != AgentMessageRole.SYSTEM }
        ?.takeIf { it.role == AgentMessageRole.ASSISTANT }

sealed class AgentTimelineItem {
    data class DateHeader(val date: Date) : AgentTimelineItem()

    data object UnreadDivider : AgentTimelineItem()
    data class Message(val message: AgentMessage, val newsPost: AgentV2ThreadNewsCard? = null) :
        AgentTimelineItem()
    data class Hints(
        val hints: List<AgentHint>,
        val followupMessageId: String? = null,
        val isLoading: Boolean = false
    ) : AgentTimelineItem()
}
