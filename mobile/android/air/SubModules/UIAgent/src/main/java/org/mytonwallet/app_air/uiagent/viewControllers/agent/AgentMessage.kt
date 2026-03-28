package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import java.util.UUID

enum class AgentMessageRole {
    ASSISTANT,
    USER,
    SYSTEM
}

data class AgentDeeplink(
    val title: String,
    val url: String
)

data class AgentMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: AgentMessageRole,
    val text: String,
    val date: Date = Date(),
    val isStreaming: Boolean = false,
    val deeplinks: List<AgentDeeplink> = emptyList(),
)

sealed class AgentTimelineItem {
    data class DateHeader(val date: Date) : AgentTimelineItem()
    data class Message(val message: AgentMessage) : AgentTimelineItem()
}
