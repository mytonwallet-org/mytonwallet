package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerButtons
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentComposerButtons
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.isAgentFieldInUse

class AgentComposerButtonsTest {
    @Test
    fun stopStandsInTheSendButtonsPlaceBesideTheMicrophone() {
        assertEquals(
            AgentComposerButtons(
                isSendShown = false,
                isStopShown = true,
                isMicrophoneShown = true,
                isCircleApart = false
            ),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = false, isAnswering = true)
        )
        val pressing = agentComposerButtons(
            AgentDictationPhase.PRESSING,
            hasText = false,
            isAnswering = true
        )
        assertEquals(true, pressing.isMicrophoneShown)
        assertEquals(false, pressing.isStopShown)
        // A draft written during the answer trades Stop for its send button
        assertEquals(
            AgentComposerButtons(
                isSendShown = true,
                isStopShown = false,
                isMicrophoneShown = true,
                isCircleApart = false
            ),
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = true, isAnswering = true)
        )
    }

    @Test
    fun theSupportCircleStandsBesideTheListsEmptyFieldOnly() {
        assertEquals(
            AgentComposerButtons(
                isSendShown = false,
                isStopShown = false,
                isMicrophoneShown = true,
                isCircleApart = true
            ),
            agentComposerButtons(
                AgentDictationPhase.IDLE,
                hasText = false,
                isAnswering = false,
                isSupportOffered = true
            )
        )
        val draft = agentComposerButtons(
            AgentDictationPhase.IDLE,
            hasText = true,
            isAnswering = false,
            isSupportOffered = true
        )
        assertEquals(false, draft.isCircleApart)
        assertEquals(true, draft.isSendShown)
        val recording = agentComposerButtons(
            AgentDictationPhase.RECORDING,
            hasText = false,
            isAnswering = false,
            isSupportOffered = true
        )
        assertEquals(false, recording.isCircleApart)
        // A chat has no circle
        assertEquals(
            false,
            agentComposerButtons(AgentDictationPhase.IDLE, hasText = false, isAnswering = false)
                .isCircleApart
        )
    }

    @Test
    fun aFieldThatKeepsSendKeepsItWhileARecordingIsRecognized() {
        assertEquals(
            true,
            agentComposerButtons(
                AgentDictationPhase.RECOGNIZING,
                hasText = false,
                isAnswering = false,
                isSendAlwaysShown = true
            ).isSendShown
        )
        assertEquals(
            false,
            agentComposerButtons(
                AgentDictationPhase.RECOGNIZING,
                hasText = false,
                isAnswering = false
            ).isSendShown
        )
    }

    @Test
    fun theMicrophoneGivesWayToTheRecognition() {
        assertEquals(
            false,
            agentComposerButtons(
                AgentDictationPhase.RECOGNIZING,
                hasText = false,
                isAnswering = false
            ).isMicrophoneShown
        )
        assertEquals(
            true,
            agentComposerButtons(
                AgentDictationPhase.RECORDING,
                hasText = false,
                isAnswering = false
            ).isMicrophoneShown
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
