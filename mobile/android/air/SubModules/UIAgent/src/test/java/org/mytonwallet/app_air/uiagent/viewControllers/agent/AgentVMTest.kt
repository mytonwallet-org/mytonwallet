package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentVMTest {
    @Test
    fun regenerationKeepsThePromptAndRemovesOnlyTheSelectedAnswerAndItsTail() {
        val prompt = AgentMessage(role = AgentMessageRole.USER, text = "Question")
        val answer = AgentMessage(
            id = "local-answer",
            sdkMessageId = "server-answer",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val laterPrompt = AgentMessage(role = AgentMessageRole.USER, text = "Later")
        val messages = listOf(prompt, answer, laterPrompt)
        assertEquals(listOf(prompt), agentMessagesBeforeRegeneration(messages, answer.id))
        assertEquals(
            listOf(prompt),
            agentMessagesBeforeRegeneration(messages, answer.sdkMessageId!!)
        )
        assertEquals(
            listOf(prompt, laterPrompt),
            agentMessagesBeforeRegeneration(messages, answer.id, listOf(laterPrompt))
        )
        assertNull(agentMessagesBeforeRegeneration(messages, prompt.id))
        assertNull(agentMessagesBeforeRegeneration(messages, "missing"))
    }

    @Test
    fun reportsOnlyTheServerIdOfAnAnswer() {
        val boundAnswer = AgentMessage(
            id = "local-bound",
            sdkMessageId = "server-answer",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val unboundAnswer = AgentMessage(
            id = "local-unbound",
            role = AgentMessageRole.ASSISTANT,
            text = "Answer"
        )
        val messages = listOf(boundAnswer, unboundAnswer)

        assertEquals("server-answer", resolveAgentReportMessageId(messages, boundAnswer.id))
        assertNull(resolveAgentReportMessageId(messages, unboundAnswer.id))
    }

    @Test
    fun editRemovesTheOriginalPromptAndItsConversationTail() {
        val earlier = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Earlier")
        val original = AgentMessage(
            id = "local-question",
            sdkMessageId = "server-question",
            role = AgentMessageRole.USER,
            text = "Original"
        )
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Old answer")
        val later = AgentMessage(role = AgentMessageRole.USER, text = "Later question")
        val messages = listOf(earlier, original, answer, later)

        assertEquals(listOf(earlier), agentMessagesBeforeEdit(messages, original.id))
        assertEquals(listOf(earlier), agentMessagesBeforeEdit(messages, original.sdkMessageId!!))
        assertEquals(
            emptyList<AgentMessage>(),
            agentMessagesBeforeEdit(listOf(original), original.id)
        )
    }

    @Test
    fun editCannotTruncateAnAnswerOrAMissingTarget() {
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Answer")
        assertNull(agentMessagesBeforeEdit(listOf(answer), answer.id))
        assertNull(agentMessagesBeforeEdit(listOf(answer), "missing"))
    }
}
