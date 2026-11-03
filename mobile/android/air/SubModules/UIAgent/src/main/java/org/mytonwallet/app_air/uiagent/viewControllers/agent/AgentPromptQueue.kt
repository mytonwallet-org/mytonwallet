package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

internal class AgentPromptQueue {
    private data class Prompt(val messages: List<AgentMessage>, val entryPoint: AgentV2EntryPoint)

    private val prompts = ArrayDeque<Prompt>()
    private var isSubmitting = false
    val isNotEmpty: Boolean get() = prompts.isNotEmpty()

    fun enqueue(messages: List<AgentMessage>, entryPoint: AgentV2EntryPoint) {
        prompts.addLast(Prompt(messages, entryPoint))
    }

    fun clear() = prompts.clear()

    fun containsMessage(messageId: String): Boolean =
        prompts.any { prompt -> prompt.messages.any { it.id == messageId } }

    fun submit(
        accept: (List<AgentMessage>, AgentV2EntryPoint) -> Boolean,
        state: AgentVM.State = AgentVM.State.READY
    ) {
        if (isSubmitting || (state != AgentVM.State.READY && state != AgentVM.State.RUNNING)) return
        isSubmitting = true
        try {
            while (true) {
                val prompt = prompts.firstOrNull() ?: return
                if (!accept(prompt.messages, prompt.entryPoint)) return
                if (prompts.firstOrNull() === prompt) prompts.removeFirst()
            }
        } finally {
            isSubmitting = false
        }
    }
}
