package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

internal fun agentNewsPostBodyText(news: AgentV2ThreadNewsCard): String? =
    news.body?.takeIf { it.isNotBlank() } ?: news.excerpt?.takeIf { it.isNotBlank() }

internal fun AgentNewsChatRequest.newsPostCard() = AgentV2ThreadNewsCard(
    eventId = eventId,
    headline = headline,
    excerpt = excerpt,
    imageUrl = imageUrl,
    publishedAt = publishedAt.orEmpty(),
    body = body,
    sources = sources
)

internal fun agentNewsPostMessages(
    messages: List<AgentMessage>,
    historyCursor: String?,
    threadNews: AgentV2ThreadNewsCard?,
    request: AgentNewsChatRequest?
): List<AgentTimelineItem.Message> {
    val news = threadNews ?: request?.newsPostCard()
    val explicitPost = messages.firstOrNull { it.newsPost }
    if (news == null || (!historyCursor.isNullOrEmpty() && explicitPost == null)) {
        return messages.map { AgentTimelineItem.Message(it) }
    }
    val storedPost = explicitPost
        ?: messages.firstOrNull { it.role == AgentMessageRole.USER }
            ?.takeIf { it.text == news.headline }
    val post = AgentMessage(
        id = "news-post-${news.eventId}",
        sdkMessageId = storedPost?.let { it.sdkMessageId ?: it.id },
        role = AgentMessageRole.ASSISTANT,
        text = "**${news.headline}**" + (news.body?.let { "\n\n$it" } ?: ""),
        followups = explicitPost?.followups.orEmpty(),
        date = parseAgentV2Timestamp(news.publishedAt) ?: Date(0),
        newsPost = true
    )
    return listOf(AgentTimelineItem.Message(post, news)) +
        messages.filterNot { it.id == storedPost?.id }.map { AgentTimelineItem.Message(it) }
}

internal fun agentNewsAllowsSubmission(
    request: AgentNewsChatRequest?,
    state: AgentVM.State
): Boolean = request == null || state == AgentVM.State.LOADING ||
    state == AgentVM.State.READY || state == AgentVM.State.RUNNING
