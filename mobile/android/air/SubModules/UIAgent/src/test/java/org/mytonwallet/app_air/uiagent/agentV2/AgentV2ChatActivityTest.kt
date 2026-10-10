package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class AgentV2ChatActivityTest {
    @Test
    fun keepsTheChatActiveOnlyWhileItIsVisibleInTheForegroundAfterConsent() = runBlocking {
        val calls = mutableListOf<Boolean>()
        coroutineScope {
            val activity = AgentV2ChatActivity(this) { calls += it }
            activity.setVisible(true)
            activity.setConsentAccepted(true)
            activity.onRuntimeReady()
            activity.setInBackground(true)
            activity.onRuntimeReady()
            activity.setInBackground(false)
            activity.stop()
            activity.setVisible(true)
        }

        assertEquals(listOf(true, true, false, true, false), calls)
    }
}
