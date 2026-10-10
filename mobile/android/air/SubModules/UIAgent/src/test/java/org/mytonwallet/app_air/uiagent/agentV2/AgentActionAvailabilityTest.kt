package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation

class AgentActionAvailabilityTest {
    @Test
    fun invalidationDiscardsLateResultsAndAllowsFreshChecks() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val response = CompletableDeferred<AgentV2ActionPresentation>()
        val availability = AgentActionAvailability { _, _ ->
            started.complete(Unit)
            withContext(NonCancellable) { response.await() }
        }
        val actions = listOf(AgentV2Action("send", "send", "Send"))
        val pending = async { availability.filterAvailable("message", actions) }
        started.await()
        availability.invalidate()
        response.complete(AgentV2ActionPresentation.Send("active"))
        assertTrue(pending.await().isEmpty())
        assertEquals(actions, availability.filterAvailable("message", actions))
    }
}
