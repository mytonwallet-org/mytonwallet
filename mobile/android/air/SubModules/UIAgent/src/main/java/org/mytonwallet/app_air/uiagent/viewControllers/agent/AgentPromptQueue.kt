package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

internal class AgentPromptQueue {
    private data class Prompt(
        val text: String,
        val entryPoint: AgentV2EntryPoint,
        val shouldWaitForAppearance: Boolean
    )

    private val prompts = ArrayDeque<Prompt>()
    private var isSubmitting = false

    fun enqueue(
        text: String,
        entryPoint: AgentV2EntryPoint,
        shouldWaitForAppearance: Boolean = false
    ) {
        prompts.addLast(Prompt(text, entryPoint, shouldWaitForAppearance))
    }

    fun clear() = prompts.clear()

    fun submit(hasAppeared: Boolean, accept: (String, AgentV2EntryPoint) -> Boolean) {
        if (isSubmitting) return
        isSubmitting = true
        try {
            while (true) {
                val prompt = prompts.firstOrNull() ?: return
                if (prompt.shouldWaitForAppearance && !hasAppeared) return
                if (!accept(prompt.text, prompt.entryPoint)) return
                if (prompts.firstOrNull() === prompt) prompts.removeFirst()
            }
        } finally {
            isSubmitting = false
        }
    }
}
