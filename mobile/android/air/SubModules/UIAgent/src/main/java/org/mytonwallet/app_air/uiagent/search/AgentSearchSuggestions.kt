package org.mytonwallet.app_air.uiagent.search

import kotlinx.coroutines.CancellationException
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2SemanticText
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage

object AgentSearchSuggestions {
    private const val SEARCH_ITEMS_LIMIT = 9
    private const val MESSAGE_PAGE_SIZE = 100
    private val client by lazy { LiveAgentV2Client() }

    suspend fun recent(): List<AgentHint> {
        if (!hasConsent()) return emptyList()
        return runAgentSearchRequest {
            val thread = client.defaultThread().thread
            val messages = client.messages(thread.id, null, MESSAGE_PAGE_SIZE).messages
            buildRecentAgentSearchSuggestions(messages, SEARCH_ITEMS_LIMIT)
        }.orEmpty()
    }

    suspend fun suggested(): List<AgentHint> = runAgentSearchRequest {
        val response = client.hints(LocaleController.activeLanguage.langCode)
        response.items.mapNotNull { hint ->
            localizedAgentV2Hint(hint.id)?.copy(catalogVersion = response.catalogVersion)
        }
    }.orEmpty()

    private suspend fun hasConsent() = runAgentSearchRequest { client.consent() } == true
}

private val whitespaceRegex = Regex("\\s+")

private fun buildRecentAgentSearchSuggestions(
    messages: List<AgentV2PersistedMessage>,
    limit: Int
): List<AgentHint> {
    val assistantReplies = mutableListOf<Pair<String?, String>>()
    return messages.asReversed()
        .asSequence()
        .mapNotNull { message ->
            val text = extractAgentSearchText(message)
            when (message.role) {
                "assistant" -> {
                    if (text.isNotEmpty()) assistantReplies.add(message.runId to text)
                    null
                }

                "user" -> {
                    val assistantReply = assistantReplies.firstOrNull { (runId) ->
                        message.runId != null && message.runId == runId
                    }?.second ?: assistantReplies.firstOrNull()?.second.orEmpty()
                    assistantReplies.clear()
                    if (text.isEmpty()) {
                        null
                    } else {
                        AgentHint(
                            id = message.id,
                            title = text,
                            subtitle = assistantReply,
                            prompt = text
                        )
                    }
                }

                else -> null
            }
        }
        .distinctBy { it.prompt.lowercase() }
        .take(limit)
        .toList()
}

private fun extractAgentSearchText(message: AgentV2PersistedMessage): String {
    val text = when (val content = message.content) {
        is AgentV2MessageContent.Markdown -> content.text.toProcessedSpannableStringBuilder()
        is AgentV2MessageContent.Semantic -> agentV2SemanticText(content.content)
        null -> return ""
    }
    return text.trim().replace(whitespaceRegex, " ")
}

private suspend fun <T> runAgentSearchRequest(block: suspend () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (_: Exception) {
    null
}
