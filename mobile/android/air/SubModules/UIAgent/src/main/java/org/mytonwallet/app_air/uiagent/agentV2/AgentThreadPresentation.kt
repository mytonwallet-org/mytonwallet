package org.mytonwallet.app_air.uiagent.agentV2

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/**
 * Whether the user has written in the thread, by the SDK's `getIsAgentV2ThreadStarted`: a news or digest discussion
 * holds its post alone, one message, until then. The chat list leaves such discussions out, and Discuss offers to discuss them.
 */
internal fun isAgentV2ThreadStarted(thread: AgentV2ThreadSummary): Boolean =
    !thread.hasPost || thread.messageCount > 1

fun resolveAgentThreadTitle(
    thread: AgentV2ThreadSummary,
    firstMessage: String? = null,
    newChatTitle: String = LocaleController.getString("New Chat")
): String = thread.title?.takeIf { it.isNotBlank() }
    ?: firstMessage?.trim()?.takeIf { it.isNotEmpty() }
    ?: newChatTitle

internal val AgentV2ThreadSummary.hasPost: Boolean
    get() = news != null || digest != null
