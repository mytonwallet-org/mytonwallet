package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Test

class AgentRowGlideTest {
    private val date = AgentTimelineItem.DateHeader(Date(0))
    private val question = AgentMessage(id = "question", role = AgentMessageRole.USER, text = "Hi")
    private val typing = AgentMessage(
        id = "answer",
        role = AgentMessageRole.ASSISTANT,
        text = "",
        isStreaming = true
    )
    private val went = AgentMessage(id = "went", role = AgentMessageRole.USER, text = "Next")
    private val waiting = AgentMessage(id = "waiting", role = AgentMessageRole.USER, text = "Last")

    private val AgentMessage.row: AgentTimelineItem
        get() = AgentTimelineItem.Message(this)

    private fun findGlideStart(
        previous: List<AgentTimelineItem>,
        items: List<AgentTimelineItem>,
        vararg waitingIds: String
    ) = agentWaitingRowsGlideStart(previous, items) { it in waitingIds }

    @Test
    fun waitingRowsGlideAsTheTypingRowAboveThemGoes() {
        val previous = listOf(date, question.row, typing.row, went.row, waiting.row)
        val items = listOf(date, question.row, went.row, waiting.row)

        assertEquals(3, findGlideStart(previous, items, went.id, waiting.id))
    }

    @Test
    fun waitingRowsGlideAsTheAnswerAboveThemEnds() {
        val writing = typing.copy(text = "TON is")
        val previous = listOf(date, question.row, writing.row, waiting.row)
        val items = listOf(date, question.row, writing.copy(isStreaming = false).row, waiting.row)

        assertEquals(3, findGlideStart(previous, items, waiting.id))
    }

    @Test
    fun waitingRowsFollowAnAnswerBeingWritten() {
        val writing = typing.copy(text = "TON")
        val previous = listOf(date, question.row, writing.row, waiting.row)
        val items = listOf(date, question.row, writing.copy(text = "TON is").row, waiting.row)

        assertEquals(-1, findGlideStart(previous, items, waiting.id))
    }

    @Test
    fun rowStillWaitingGlidesUnderTheNextTypingRowAndTheOneThatWentStays() {
        val answer = typing.copy(id = "first", text = "TON is", isStreaming = false)
        val previous = listOf(date, question.row, answer.row, went.row, waiting.row)
        val items = listOf(date, question.row, answer.row, went.row, typing.row, waiting.row)

        assertEquals(4, findGlideStart(previous, items, waiting.id))
    }

    @Test
    fun waitingQuestionGlidesWithItsDate() {
        val waitingDate = AgentTimelineItem.DateHeader(waiting.date)
        val previous = listOf(date, question.row, typing.row, waitingDate, waiting.row)
        val items = listOf(date, question.row, waitingDate, waiting.row)

        assertEquals(3, findGlideStart(previous, items, waiting.id))
    }

    @Test
    fun nothingGlidesWithoutAQuestionWaitingUnderTheChange() {
        val previous = listOf(date, question.row, went.row)
        val items = listOf(date, question.row, went.row, typing.row)

        assertEquals(-1, findGlideStart(previous, items, went.id))
        assertEquals(-1, findGlideStart(previous, items))
    }
}
