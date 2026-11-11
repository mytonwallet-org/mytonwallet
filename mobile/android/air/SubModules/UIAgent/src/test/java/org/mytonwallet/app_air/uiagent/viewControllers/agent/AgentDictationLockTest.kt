package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentDictationLockProgress
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentLockShackle

class AgentDictationLockTest {
    @Test
    fun theShackleComesDownInProportionToTheFingersTravelAndShutsAtTheLock() {
        val travels = listOf(0f, 20f, 52.5f, 80f, 105f)
        val shackles = travels.map { agentLockShackle(agentDictationLockProgress(it)) }

        // Open where the finger pressed, its short leg out of the body
        assertEquals(3f, shackles.first().lift, 0f)
        assertEquals(6f, shackles.first().legGap, 0f)
        // Halfway up, halfway down
        assertEquals(1.5f, shackles[2].lift, 1e-4f)
        assertEquals(3f, shackles[2].legGap, 1e-4f)
        // Shut at the lock
        assertEquals(0f, shackles.last().lift, 0f)
        assertEquals(0f, shackles.last().legGap, 0f)
        shackles.zipWithNext { lower, higher ->
            assertTrue(higher.lift < lower.lift)
            assertTrue(higher.legGap < lower.legGap)
        }
    }

    @Test
    fun aFingerPastTheLockOrBelowWhereItPressedKeepsTheShackleWithinItsTravel() {
        assertEquals(1f, agentDictationLockProgress(160f), 0f)
        assertEquals(0f, agentDictationLockProgress(-30f), 0f)
        assertEquals(agentLockShackle(1f), agentLockShackle(agentDictationLockProgress(160f)))
    }
}
