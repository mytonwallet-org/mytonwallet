package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

class AgentPromptQueueTest {
    @Test
    fun preservesFifoUntilAcceptanceThenDrainsExactlyOnce() {
        val queue = AgentPromptQueue()
        val accepted = mutableListOf<Pair<List<AgentMessage>, AgentV2EntryPoint>>()
        val first = listOf(AgentMessage(role = AgentMessageRole.USER, text = "first"))
        val second = listOf(AgentMessage(role = AgentMessageRole.USER, text = "second"))
        val hintEntryPoint = AgentV2EntryPoint(
            kind = "emptyState",
            surface = "agentTab",
            hintId = "learn.swap",
            catalogVersion = "agent-starter-hints-v1"
        )
        var ready = false
        val accept: (
            List<AgentMessage>,
            AgentV2EntryPoint,
            String?,
            AgentV2AuthorityBinding?
        ) -> Boolean = { messages, entryPoint, _, _ ->
            if (ready) accepted.add(messages to entryPoint)
            ready
        }
        queue.enqueue(first, AgentV2EntryPoint())
        queue.enqueue(second, hintEntryPoint)
        queue.submit(accept)
        assertTrue(accepted.isEmpty())
        ready = true
        queue.submit(accept, AgentVM.State.LOADING)
        queue.submit(accept, AgentVM.State.CONSENT_REQUIRED)
        assertTrue(accepted.isEmpty())
        queue.submit(accept)
        queue.submit(accept)
        assertEquals(listOf(first to AgentV2EntryPoint(), second to hintEntryPoint), accepted)
        val third = listOf(AgentMessage(role = AgentMessageRole.USER, text = "third"))
        queue.enqueue(third, AgentV2EntryPoint())
        queue.submit(accept, AgentVM.State.RUNNING)
        queue.submit(accept, AgentVM.State.RUNNING)
        assertEquals(
            listOf(
                first to AgentV2EntryPoint(),
                second to hintEntryPoint,
                third to AgentV2EntryPoint()
            ),
            accepted
        )
    }
}
