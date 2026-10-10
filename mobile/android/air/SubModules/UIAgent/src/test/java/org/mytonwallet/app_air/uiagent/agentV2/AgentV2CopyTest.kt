package org.mytonwallet.app_air.uiagent.agentV2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.findFollowupOwner
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2DisplayTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage

class AgentV2CopyTest {
    @Test
    fun restoresFollowupsWithTheirCanonicalMessageAndOriginalPrompt() {
        val followup = AgentV2FollowUp("next", "suggested_prompt", "Explain wallet safety.")
        val message = mapAgentV2Message(
            AgentV2PersistedMessage(
                id = "sdk-answer",
                threadId = "thread",
                role = "assistant",
                status = "complete",
                content = AgentV2MessageContent.Markdown("Keep your recovery phrase private."),
                createdAt = "2026-10-05T12:00:00.000Z",
                followups = listOf(followup)
            )
        )!!

        assertEquals("sdk-answer", message.sdkMessageId)
        assertEquals(listOf(followup), message.followups)
        assertEquals(message, listOf(message).findFollowupOwner())
    }

    @Test
    fun acceptedQuestionAndLateUpdatesCannotReviveAnOldFollowupOwner() {
        val first = AgentMessage(
            sdkMessageId = "sdk-first",
            role = AgentMessageRole.ASSISTANT,
            text = "First answer",
            followups = listOf(AgentV2FollowUp("first", "suggested_prompt", "First prompt"))
        )
        val last = first.copy(id = "local-last", sdkMessageId = "sdk-last")
        val timeline = mutableListOf(first, last)
        timeline.add(AgentMessage(role = AgentMessageRole.SYSTEM, text = "Switched account"))
        assertEquals(last, timeline.findFollowupOwner())

        timeline.add(AgentMessage(role = AgentMessageRole.USER, text = "First prompt"))
        assertNull(timeline.findFollowupOwner())
        timeline[1] = last.copy(
            followups = listOf(AgentV2FollowUp("late", "suggested_prompt", "Late prompt"))
        )
        assertNull(timeline.findFollowupOwner())

        val response = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Next answer")
        timeline.add(response)
        assertEquals(response, timeline.findFollowupOwner())
        assertTrue(timeline.findFollowupOwner()!!.followups.isEmpty())
        timeline.clear()
        assertNull(timeline.findFollowupOwner())
    }

    @Test
    fun marksAnswerLinksAroundTablesAndCopiesTheirUrls() {
        val table = AgentV2AnswerTable(
            "t1",
            AgentV2DisplayTable("display", listOf("Asset"), listOf(listOf("TON")), emptyList())
        )
        val links = listOf(
            AgentV2AnswerLink(4, 4, "https://help.mywallet.io/\u0442\u043e\u043d"),
            AgentV2AnswerLink(9, 3, "https://across.example.com/"),
            AgentV2AnswerLink(16, 4, "https://docs.example.com/"),
            AgentV2AnswerLink(18, 9, "https://past.example.com/")
        )
        val message = mapAgentV2Message(
            AgentV2PersistedMessage(
                id = "message",
                threadId = "thread",
                role = "assistant",
                status = "complete",
                content = AgentV2MessageContent.Markdown(
                    "See Help\n\nAfter Docs",
                    listOf(table),
                    listOf(AgentV2AnswerTableReference("t1", 10)),
                    links
                ),
                createdAt = "2026-08-10T12:00:00.000Z"
            )
        )!!

        val marked = message.formatText()
        assertTrue(AgentTextLinks.markedLink.findAll(marked).count() == 2)
        assertEquals(
            "See Help (https://help.mywallet.io/\u0442\u043e\u043d)\n\n" +
                "\n\n| Asset |\n| --- |\n| TON |\n\n" +
                "After Docs (https://docs.example.com/)",
            AgentTextLinks.copyText(marked)
        )
        val blocks = buildAgentV2MessageBlocks(
            message.text,
            listOf(table),
            message.tableReferences,
            links
        )
        assertTrue(blocks[1] is MarkdownParser.Block.Table)
    }

    @Test
    fun resolvesMarkedLabelsWithoutTheirEscapes() {
        val marked = AgentTextLinks.mark(
            "Use snake\\_case, 1\\. Ab, Doc\\_s",
            listOf(
                AgentV2AnswerLink(4, 11, "https://a.io/x?f={1}"),
                AgentV2AnswerLink(17, 6, "http://b.io/"),
                // The text covers only part of this label so far
                AgentV2AnswerLink(25, 9, "https://c.io/w/[x]")
            ),
            emptyList()
        ).text
        val resolved = StringBuilder(marked)
        val links = mutableListOf<Triple<Int, Int, String>>()
        val delete: (Int, Int) -> Unit = { start, end -> resolved.delete(start, end) }
        AgentTextLinks.resolve(resolved, removesLabelEscapes = true, delete) { start, end, url ->
            links += Triple(start, end, url)
        }

        assertEquals("Use snake_case, 1. Ab, Doc_s", resolved.toString())
        assertEquals(
            listOf(Triple(4, 14, "https://a.io/x?f={1}"), Triple(23, 28, "https://c.io/w/[x]")),
            links
        )
        assertEquals(
            "Use snake_case (https://a.io/x?f={1}), 1. Ab, Doc_s (https://c.io/w/[x])",
            AgentTextLinks.copyText(marked)
        )
    }

    @Test
    fun opensOnlyHttpsAnswerLinksWithAHostAndNoCredentials() {
        assertTrue(AgentTextLinks.isOpenable("https://a.io/x?f={1}"))
        assertFalse(AgentTextLinks.isOpenable("https://user:pw@a.io/"))
        assertFalse(AgentTextLinks.isOpenable("http://a.io/"))
        assertFalse(AgentTextLinks.isOpenable("https:///a"))
    }

    @Test
    fun displaysNoSearchResultsAsAnOperationalNotice() {
        assertEquals(
            LocaleController.getString("\$agent_notice_web_search_no_results"),
            agentV2SemanticText(
                mapOf("kind" to "notice", "schemaVersion" to 1, "code" to "web_search_no_results")
            )
        )
    }

    @Test
    fun preservesTextAndExplainsAnInvalidHistoryExtension() {
        val message = mapAgentV2Message(
            AgentV2PersistedMessage(
                id = "message",
                threadId = "thread",
                role = "assistant",
                status = "complete",
                content = AgentV2MessageContent.Markdown("Valid answer"),
                error = AgentV2MessageError("invalid_event", false),
                createdAt = "2026-08-10T12:00:00.000Z"
            )
        )!!
        assertEquals("Valid answer\n\n${agentV2ErrorText("invalid_event")}", message.text)
        assertFalse(message.isStreaming)
    }

    @Test
    fun restoresLiteralTablesAndSourceTextFromHistory() {
        val table = AgentV2AnswerTable(
            "t1",
            AgentV2DisplayTable(
                "display",
                listOf("Asset", "Value"),
                listOf(listOf("A & B_[token]", "123456789.000000001 TON")),
                emptyList()
            )
        )
        val source = "🪙\n\nAfter"
        val references = listOf(AgentV2AnswerTableReference("t1", 4))
        val message = mapAgentV2Message(
            AgentV2PersistedMessage(
                id = "message",
                threadId = "thread",
                role = "assistant",
                status = "complete",
                content = AgentV2MessageContent.Markdown(source, listOf(table), references),
                createdAt = "2026-08-10T12:00:00.000Z"
            )
        )!!
        assertEquals(source, message.text)
        assertEquals(listOf(table), message.answerTables)
        assertEquals(references, message.tableReferences)
        val blocks = buildAgentV2MessageBlocks(
            message.text,
            message.answerTables,
            message.tableReferences
        )
        val restored = blocks.filterIsInstance<MarkdownParser.Block.Table>().single()
        assertEquals("A & B_[token]", restored.rows[1][0].text)
        assertTrue(restored.rows[1][0].isPlainText)
        assertTrue(message.formatText().endsWith("After"))
        assertTrue(message.formatText().contains("123456789.000000001 TON"))
        val tableOnly = message.copy(
            text = "",
            tableReferences = listOf(AgentV2AnswerTableReference("t1", 0))
        )
        assertTrue(tableOnly.hasVisibleBubble)
        assertTrue(tableOnly.formatText().contains("123456789.000000001 TON"))
        assertFalse(
            tableOnly.copy(
                tableReferences = listOf(AgentV2AnswerTableReference("missing", 0))
            ).hasVisibleBubble
        )
        assertFalse(
            tableOnly.copy(
                tableReferences = listOf(AgentV2AnswerTableReference("t1", 4))
            ).hasVisibleBubble
        )
    }
}
