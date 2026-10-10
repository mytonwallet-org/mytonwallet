package org.mytonwallet.app_air.uiagent.agentV2

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentContextPublicationStateTest {
    @Test
    fun accountTransitionsAndRestartRejectOldCompletions() {
        val state = AgentContextPublicationState()
        state.start()
        val firstAccount = checkNotNull(state.capture())
        repeat(2) {
            state.beginAccountChange()
            assertTrue(state.isAccountChanging.value)
            assertFalse(state.complete(firstAccount))
            state.completeAccountChange()
        }
        assertFalse(state.complete(firstAccount))
        val restoredAccount = checkNotNull(state.capture())
        assertTrue(restoredAccount.shouldPublishAuthority)
        assertTrue(state.complete(restoredAccount))
        state.request()
        val failedAttempt = checkNotNull(state.capture())
        assertTrue(state.hasPendingUpdate)
        assertNotNull(state.capture())
        state.beginAccountChange()
        state.stop()
        assertFalse(state.isAccountChanging.value)
        state.start()
        assertFalse(state.complete(failedAttempt))
        assertTrue(state.complete(checkNotNull(state.capture())))
    }
}
