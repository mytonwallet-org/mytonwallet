package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import java.util.UUID
import org.mytonwallet.app_air.uiagent.agentV2.agentV2AnswerTableText
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp

enum class AgentMessageRole {
    ASSISTANT,
    USER,
    SYSTEM
}

data class AgentDeeplink(val title: String, val url: String? = null, val actionId: String? = null)

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
    val deeplinks: List<AgentDeeplink> = emptyList()
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

internal fun List<AgentMessage>.findFollowupOwner(): AgentMessage? =
    lastOrNull { it.role != AgentMessageRole.SYSTEM }
        ?.takeIf { it.role == AgentMessageRole.ASSISTANT }

sealed class AgentTimelineItem {
    data class DateHeader(val date: Date) : AgentTimelineItem()
    data class Message(val message: AgentMessage) : AgentTimelineItem()
    data class Hints(val hints: List<AgentHint>, val followupMessageId: String? = null) :
        AgentTimelineItem()
}
