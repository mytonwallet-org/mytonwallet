package org.mytonwallet.app_air.uiagent.agentV2

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

fun resolveAgentThreadTitle(
    thread: AgentV2ThreadSummary,
    firstMessage: String? = null,
    newChatTitle: String = LocaleController.getString("New Chat")
): String = thread.title?.takeIf { it.isNotBlank() }
    ?: firstMessage?.trim()?.takeIf { it.isNotEmpty() }
    ?: newChatTitle
