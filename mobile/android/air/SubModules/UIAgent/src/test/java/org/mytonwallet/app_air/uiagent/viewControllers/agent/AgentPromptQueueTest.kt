package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

class AgentPromptQueueTest {
    @Test
    fun preservesFifoUntilAppearanceAndAcceptanceThenDrainsExactlyOnce() {
        val queue = AgentPromptQueue()
        val accepted = mutableListOf<Pair<String, AgentV2EntryPoint>>()
        val hintEntryPoint = AgentV2EntryPoint(
            kind = "emptyState",
            surface = "agentTab",
            hintId = "learn.swap",
            catalogVersion = "agent-starter-hints-v1"
        )
        var ready = false
        val accept: (String, AgentV2EntryPoint) -> Boolean = { text, entryPoint ->
            if (ready) accepted.add(text to entryPoint)
            ready
        }
        queue.enqueue("first", AgentV2EntryPoint(), shouldWaitForAppearance = true)
        queue.enqueue("second", hintEntryPoint)
        queue.submit(false, accept)
        assertTrue(accepted.isEmpty())
        queue.submit(true, accept)
        assertTrue(accepted.isEmpty())
        ready = true
        queue.submit(true, accept)
        queue.submit(true, accept)
        assertEquals(listOf("first" to AgentV2EntryPoint(), "second" to hintEntryPoint), accepted)
    }
}
