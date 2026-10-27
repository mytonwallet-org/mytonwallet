package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Test

class AgentTimelineViewportTest {
    @Test
    fun firstQuestionKeepsItsNaturalPositionBelowTheDate() {
        val question = AgentMessage(role = AgentMessageRole.USER, text = "What is TON?")
        val items = listOf(
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question)
        )
        val topPadding = 300
        val dateHeight = 82
        val naturalQuestionTop = topPadding + dateHeight

        val anchorIndex = items.agentPinAnchorIndex(1)
        val offset = agentPinnedItemOffset(items[anchorIndex], dateHeight, topPadding, 63, 1900)
        val pinnedQuestionTop = topPadding + offset + dateHeight

        assertEquals(0, anchorIndex)
        assertEquals(0, pinnedQuestionTop - naturalQuestionTop)
    }

    @Test
    fun questionInHistoryPinsItsDateAtTheContentTopEvenWithLimitedSpace() {
        val earlier = AgentMessage(role = AgentMessageRole.USER, text = "Earlier")
        val question = AgentMessage(role = AgentMessageRole.USER, text = "What is TON?")
        val items = listOf(
            AgentTimelineItem.DateHeader(Date(0)),
            AgentTimelineItem.Message(earlier),
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question)
        )
        val topPadding = 300

        val anchorIndex = items.agentPinAnchorIndex(3)
        val offset = agentPinnedItemOffset(items[anchorIndex], 82, topPadding, 63, 320)

        assertEquals(2, anchorIndex)
        assertEquals(topPadding, topPadding + offset)
    }

    @Test
    fun questionWithoutItsOwnDateKeepsTheMessageOffsetAndAnswerPreview() {
        val question = AgentMessage(role = AgentMessageRole.USER, text = "What is TON?")
        val items = listOf(
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question.copy(id = "earlier")),
            AgentTimelineItem.Message(question)
        )

        val anchorIndex = items.agentPinAnchorIndex(2)

        assertEquals(2, anchorIndex)
        assertEquals(-63, agentPinnedItemOffset(items[anchorIndex], 126, 300, 63, 1900))
        assertEquals(-200, agentPinnedItemOffset(items[anchorIndex], 1800, 300, 63, 1900))
    }
}
