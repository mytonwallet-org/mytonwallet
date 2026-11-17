package org.mytonwallet.app_air.uiagent.agentV2

import java.util.Date
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsChatRequest
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

private const val DIGEST_DISCUSSION_ICON = "🗓"

internal data class AgentChatHeader(val title: String, val icon: String?)

internal data class AgentThreadListTexts(val title: String, val preview: String?)

/**
 * Whether the user has written in the thread, by the SDK's `getIsAgentV2ThreadStarted`: a news or digest discussion
 * holds its post alone, one message, until then. The chat list leaves such discussions out, and Discuss offers to discuss them.
 */
internal fun isAgentV2ThreadStarted(thread: AgentV2ThreadSummary): Boolean =
    !thread.hasPost || thread.messageCount > 1

internal fun resolveAgentChatHeader(
    thread: AgentV2ThreadSummary?,
    firstMessage: String?,
    news: AgentNewsChatRequest?,
    digestId: String?,
    digestPreview: AgentV2ThreadDigestCard?,
    isDeferredDiscussion: Boolean,
    newChatTitle: String,
    formatDigestTitle: (String) -> String?
): AgentChatHeader {
    val digestTitle = (thread?.digest ?: digestPreview)?.let {
        formatDigestTitle(it.windowEnd)
    }
    val headline = news?.headline
    val discussionNaming = news?.discussionNaming
    val title = if (thread?.digest != null) {
        resolveAgentThreadTitle(thread, firstMessage, newChatTitle) { digestTitle }
    } else if (thread?.title.isNullOrBlank() && digestTitle != null) {
        digestTitle
    } else if (thread == null && isDeferredDiscussion && discussionNaming != null) {
        discussionNaming.title
    } else if (!headline.isNullOrBlank() && thread?.title.isNullOrBlank()) {
        headline
    } else {
        thread?.let { resolveAgentThreadTitle(it, firstMessage, newChatTitle) { digestTitle } }
            ?: firstMessage.orEmpty()
    }
    val icon = when {
        thread != null -> thread.icon
        digestId != null -> DIGEST_DISCUSSION_ICON
        else -> discussionNaming?.icon ?: news?.icon
    }?.trim()?.takeIf { it.isNotEmpty() }
    return AgentChatHeader(title, icon)
}

internal fun resolveAgentThreadListTexts(
    item: AgentV2ThreadListItem,
    newChatTitle: String,
    formatDigestTitle: (String) -> String?
): AgentThreadListTexts {
    val thread = item.thread
    val title = thread.title?.takeIf { it.isNotBlank() }
        ?: thread.digest?.windowEnd?.let(formatDigestTitle)
    val preview = item.preview?.takeIf { it.isNotBlank() }
    return AgentThreadListTexts(
        title = title ?: preview ?: newChatTitle,
        preview = preview.takeIf { title != null }
    )
}

fun resolveAgentThreadTitle(
    thread: AgentV2ThreadSummary,
    firstMessage: String? = null,
    newChatTitle: String = LocaleController.getString("New Chat")
): String = resolveAgentThreadTitle(
    thread,
    firstMessage,
    newChatTitle
) { thread.digest?.windowEnd?.let(::formatAgentDigestDiscussionTitle) }

private fun resolveAgentThreadTitle(
    thread: AgentV2ThreadSummary,
    firstMessage: String?,
    newChatTitle: String,
    getDigestTitle: () -> String?
): String = thread.title?.takeIf { it.isNotBlank() }
    ?: getDigestTitle()
    ?: firstMessage?.trim()?.takeIf { it.isNotEmpty() }
    ?: newChatTitle

internal fun formatAgentDigestDiscussionTitle(windowEnd: String): String? {
    val date = parseAgentV2Timestamp(windowEnd) ?: return null
    val day = AgentThreadDateFormatting.formatDayText(
        date,
        Date(),
        LocaleController.activeLanguage.langCode
    )
    return LocaleController.getString("\$agent_digest_discussion_title").replace("%date%", day)
}

internal val AgentV2ThreadSummary.hasPost: Boolean
    get() = news != null || digest != null
