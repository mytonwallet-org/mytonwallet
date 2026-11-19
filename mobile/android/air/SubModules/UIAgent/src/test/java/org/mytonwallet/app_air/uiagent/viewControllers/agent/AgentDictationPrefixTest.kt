package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.getAgentDictationPrefix
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.sendAgentDictationText

class AgentDictationPrefixTest {
    @Test
    fun rejectedDictationSendKeepsTheDraftAndTranscriptInTheField() {
        var draft = "Existing draft"
        val sent = mutableListOf<String>()

        sendAgentDictationText(draft, "Recognized speech", { draft = it }) { question ->
            assertEquals(question, draft)
            sent.add(question)
            false
        }

        assertEquals(listOf("Existing draft Recognized speech"), sent)
        assertEquals("Existing draft Recognized speech", draft)
    }

    @Test
    fun acceptedDictationSendClearsTheFieldAfterSendingTheDraftAndTranscript() {
        var draft = "Existing draft"
        val sent = mutableListOf<String>()

        sendAgentDictationText(draft, "Recognized speech", { draft = it }) { question ->
            assertEquals("Existing draft Recognized speech", draft)
            sent.add(question)
            true
        }

        assertEquals(listOf("Existing draft Recognized speech"), sent)
        assertEquals("", draft)
    }

    @Test
    fun aTranscriptGoesAfterTheDraftASpaceApartAsOnIos() {
        assertEquals("Раз, два ", getAgentDictationPrefix("Раз, два"))
        // A draft that ends in a space or a line break keeps it
        assertEquals("Раз, два ", getAgentDictationPrefix("Раз, два "))
        assertEquals("Раз,\n", getAgentDictationPrefix("Раз,\n"))
        // A blank draft gives way to the transcript
        assertEquals("", getAgentDictationPrefix(""))
        assertEquals("", getAgentDictationPrefix(" \n "))
    }
}
