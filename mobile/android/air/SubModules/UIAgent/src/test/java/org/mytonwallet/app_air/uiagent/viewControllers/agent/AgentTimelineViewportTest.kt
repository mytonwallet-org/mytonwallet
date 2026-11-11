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
        val offset = agentPinnedItemOffset(items[anchorIndex], dateHeight, topPadding, 1900)
        val pinnedQuestionTop = topPadding + offset + dateHeight

        assertEquals(0, anchorIndex)
        assertEquals(0, pinnedQuestionTop - naturalQuestionTop)
    }

    @Test
    fun sentQuestionLeavesTheLastLineOfTheMessageAboveInView() {
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "TON is a blockchain.")
        val question = AgentMessage(role = AgentMessageRole.USER, text = "What is TON?")
        val first = listOf(
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question)
        )
        val followUp = listOf(
            AgentTimelineItem.DateHeader(answer.date),
            AgentTimelineItem.Message(answer),
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question)
        )

        assertEquals(0, first.agentPinPreviousLineReveal(first.agentPinAnchorIndex(1), 38))
        assertEquals(38, followUp.agentPinPreviousLineReveal(followUp.agentPinAnchorIndex(3), 38))
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
        val offset = agentPinnedItemOffset(items[anchorIndex], 82, topPadding, 320)

        assertEquals(2, anchorIndex)
        assertEquals(topPadding, topPadding + offset)
    }

    @Test
    fun questionWithoutItsOwnDatePinsAtTheContentTopAndKeepsTheAnswerPreview() {
        val question = AgentMessage(role = AgentMessageRole.USER, text = "What is TON?")
        val items = listOf(
            AgentTimelineItem.DateHeader(question.date),
            AgentTimelineItem.Message(question.copy(id = "earlier")),
            AgentTimelineItem.Message(question)
        )

        val anchorIndex = items.agentPinAnchorIndex(2)

        assertEquals(2, anchorIndex)
        assertEquals(0, agentPinnedItemOffset(items[anchorIndex], 126, 300, 1900))
        assertEquals(-200, agentPinnedItemOffset(items[anchorIndex], 1800, 300, 1900))
    }

    @Test
    fun questionSentWhileSupportHasTheChatGoesToTheEndInsteadOfPinning() {
        assertEquals(AgentSentQuestionPlacement.PIN, getAgentSentQuestionPlacement(false))
        assertEquals(AgentSentQuestionPlacement.END, getAgentSentQuestionPlacement(true))
    }

    @Test
    fun newMessagesAreFollowedOnlyFromTheEndAndPastAPinOnceTheyOutgrowItsReserve() {
        assertEquals(
            AgentNewMessagesFollow.END,
            getAgentNewMessagesFollow(wasAtEnd = true, isPinned = false, latestRowOverhang = 120)
        )
        assertEquals(
            AgentNewMessagesFollow.NONE,
            getAgentNewMessagesFollow(wasAtEnd = false, isPinned = false, latestRowOverhang = 120)
        )
        assertEquals(
            AgentNewMessagesFollow.NONE,
            getAgentNewMessagesFollow(wasAtEnd = true, isPinned = true, latestRowOverhang = 0)
        )
        assertEquals(
            AgentNewMessagesFollow.RELEASE_PIN_AND_END,
            getAgentNewMessagesFollow(wasAtEnd = true, isPinned = true, latestRowOverhang = 40)
        )
        assertEquals(
            AgentNewMessagesFollow.NONE,
            getAgentNewMessagesFollow(wasAtEnd = false, isPinned = true, latestRowOverhang = 40)
        )
    }
}
