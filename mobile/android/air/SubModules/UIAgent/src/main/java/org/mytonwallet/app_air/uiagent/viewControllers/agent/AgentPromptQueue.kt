package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

internal class AgentPromptQueue {
    data class Prompt(
        val messages: List<AgentMessage>,
        val entryPoint: AgentV2EntryPoint,
        val followupText: String?,
        val authority: AgentV2AuthorityBinding?
    )

    private val prompts = ArrayDeque<Prompt>()
    private var isSubmitting = false
    val isNotEmpty: Boolean get() = prompts.isNotEmpty()

    fun enqueue(
        messages: List<AgentMessage>,
        entryPoint: AgentV2EntryPoint,
        followupText: String? = null,
        authority: AgentV2AuthorityBinding? = null
    ) {
        prompts.addLast(Prompt(messages, entryPoint, followupText, authority))
    }

    fun clear() = prompts.clear()

    fun containsMessage(messageId: String): Boolean =
        prompts.any { prompt -> prompt.messages.any { it.id == messageId } }

    fun removeMessage(messageId: String) {
        prompts.removeAll { prompt -> prompt.messages.any { it.id == messageId } }
    }

    fun submit(
        accept: (
            List<AgentMessage>,
            AgentV2EntryPoint,
            String?,
            AgentV2AuthorityBinding?
        ) -> Boolean,
        state: AgentVM.State = AgentVM.State.READY
    ) {
        if (isSubmitting || (state != AgentVM.State.READY && state != AgentVM.State.RUNNING)) return
        isSubmitting = true
        try {
            while (true) {
                val prompt = prompts.firstOrNull() ?: return
                if (!accept(
                        prompt.messages,
                        prompt.entryPoint,
                        prompt.followupText,
                        prompt.authority
                    )
                ) {
                    return
                }
                if (prompts.firstOrNull() === prompt) prompts.removeFirst()
            }
        } finally {
            isSubmitting = false
        }
    }
}
