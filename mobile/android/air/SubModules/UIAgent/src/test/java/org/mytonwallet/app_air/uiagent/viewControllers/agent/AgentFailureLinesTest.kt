package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.mapAgentV2Message
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage

class AgentFailureLinesTest {
    private val question = AgentMessage(id = "question", role = AgentMessageRole.USER, text = "Hi")
    private val storedFailure = checkNotNull(
        mapAgentV2Message(
            AgentV2PersistedMessage(
                id = "answer",
                threadId = "thread",
                role = "assistant",
                status = "error",
                error = AgentV2MessageError("network_error", true),
                createdAt = "2026-10-26T12:00:00.000Z"
            )
        )
    )
    private val liveFailure = AgentMessage(
        id = "live",
        role = AgentMessageRole.SYSTEM,
        text = agentV2ErrorText("network_error"),
        isFailure = true
    )

    private fun show(vararg messages: AgentMessage) = messages
        .map { AgentTimelineItem.Message(it) }
        .insertFailureLines()
        .map { it.message }

    @Test
    fun storedFailureShowsAsLine() {
        val shown = show(question, storedFailure)

        assertEquals(listOf("question", "answer:failure"), shown.map { it.id })
        assertEquals(agentV2ErrorText("network_error"), shown.last().text)
        assertEquals(true, shown.last().isFailure)
        assertEquals(AgentMessageRole.SYSTEM, shown.last().role)
    }

    @Test
    fun chatsOwnLineOfAFailureTakesThePlaceOfTheStoredOneOfItsRun() {
        val shown = show(question, storedFailure, liveFailure)

        assertEquals(listOf("question", "live"), shown.map { it.id })
    }

    @Test
    fun liveFailureOfALaterRunAndAStoredFailureOfAnEarlierOneBothShow() {
        val laterQuestion = question.copy(id = "later")

        val shown = show(question, storedFailure, laterQuestion, liveFailure)

        assertEquals(listOf("question", "answer:failure", "later", "live"), shown.map { it.id })
    }

    @Test
    fun partialAnswerKeepsItsTextAndShowsItsFailureAsLineAfterIt() {
        val partial = storedFailure.copy(text = "Partial answer")

        val shown = show(question, partial)

        assertEquals(listOf("question", "answer", "answer:failure"), shown.map { it.id })
        assertEquals("Partial answer", shown[1].text)
    }
}
