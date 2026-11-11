package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerButtons
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentComposerButtons
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.isAgentFieldInUse

class AgentComposerButtonsTest {
    @Test
    fun draftWhileAnsweringTradesStopForSendWithoutTheMicrophone() {
        // The circle merges into the field still holding Stop as the send button comes, and comes back with it
        assertEquals(
            AgentComposerButtons(isSendShown = false, isCircleApart = true, isStopShown = true),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = false, isAnswering = true)
        )
        assertEquals(
            AgentComposerButtons(isSendShown = true, isCircleApart = false, isStopShown = true),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = true, isAnswering = true)
        )
    }

    @Test
    fun withoutAnAnswerTheMicrophoneTradesPlacesWithSend() {
        assertEquals(
            AgentComposerButtons(isSendShown = false, isCircleApart = true, isStopShown = false),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = false, isAnswering = false)
        )
        assertEquals(
            AgentComposerButtons(isSendShown = true, isCircleApart = false, isStopShown = false),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = true, isAnswering = false)
        )
    }

    @Test
    fun theListSearchMakesWayWhileTheFieldRecordsRecognizesOrHoldsADraft() {
        val phases = AgentDictationPhase.entries
        assertEquals(
            listOf(AgentDictationPhase.RECORDING, AgentDictationPhase.RECOGNIZING),
            phases.filter { isAgentFieldInUse(it, hasDraft = false) }
        )
        // A draft keeps the search away whatever the dictation does; an empty field brings it back
        assertEquals(phases, phases.filter { isAgentFieldInUse(it, hasDraft = true) })
    }
}
