package org.mytonwallet.app_air.uiagent.agentV2

import android.content.ContextWrapper
import java.util.Date
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportEvent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVM
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uiagent.viewControllers.agent.findFollowupOwner
import org.mytonwallet.app_air.uiagent.viewControllers.agent.getAgentComposerPlaceholder
import org.mytonwallet.app_air.uiagent.viewControllers.agent.getAgentSupportSubtitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.hasSupportOperatorJoined
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.arrivingRichBlockIndex
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2DisplayTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageError
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2OperatorAuthor
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage

class AgentV2CopyTest {
    @Test
    fun showsTheDailyQuotaResetOnlyWhileItIsKnownAndInTheFuture() {
        val dictionary = LocaleController::class.java.getDeclaredField("dictionary").apply {
            isAccessible = true
        }
        val applicationContext = ApplicationContextHolder::class.java
            .getDeclaredField("applicationContext").apply { isAccessible = true }
        val previousDictionary = dictionary.get(null)
        val previousContext = applicationContext.get(null)
        val context = ContextWrapper(null)
        val resetAt = Date(4_102_444_800_000L)
        try {
            applicationContext.set(null, context)
            dictionary.set(
                null,
                mapOf(
                    "\$agent_daily_limit_resets_at" to
                        "Daily agent limit reached. Resets at %time%.",
                    "\$agent_daily_limit_reached" to "Daily agent limit reached"
                )
            )
            assertEquals(
                "Daily agent limit reached. Resets at ${formatAgentChatTime(context, resetAt)}.",
                agentV2ErrorText("user_quota_exhausted", resetAt)
            )
            for (unknownOrPast in listOf(null, Date(0))) {
                assertEquals(
                    "Daily agent limit reached",
                    agentV2ErrorText("user_quota_exhausted", unknownOrPast)
                )
            }
        } finally {
            dictionary.set(null, previousDictionary)
            applicationContext.set(null, previousContext)
        }
    }

    @Test
    fun restoresSupportMessagesWithoutContentAndSkipsUnknownEvents() {
        val user = AgentV2PersistedMessage(
            id = "user",
            threadId = "thread",
            role = "user",
            status = "complete",
            content = AgentV2MessageContent.Markdown("I need help"),
            createdAt = "2026-11-05T12:00:00.000Z"
        )
        val operator = AgentV2OperatorAuthor("operator", "Alex", "https://example.com/avatar.png")
        val event = user.copy(role = "event", content = null)
        val messages = listOf(
            user,
            user.copy(id = "assistant", role = "assistant"),
            user.copy(
                id = "operator",
                role = "operator",
                content = null,
                text = "**Literal** [text](https://example.com)",
                author = operator,
                feedback = "like"
            ),
            event.copy(id = "requested", code = "support_requested"),
            event.copy(id = "joined", code = "operator_joined", author = operator),
            event.copy(id = "closed", code = "support_closed", reason = "inactivity"),
            event.copy(id = "unknown", code = "future_event")
        ).mapNotNull { mapAgentV2Message(it) }

        assertEquals(
            listOf("user", "assistant", "operator", "requested", "joined", "closed"),
            messages.map { it.id }
        )
        assertEquals(AgentMessageRole.USER, messages[0].role)
        assertEquals(AgentMessageRole.ASSISTANT, messages[1].role)
        assertEquals(AgentMessageRole.OPERATOR, messages[2].role)
        assertEquals(operator, messages[2].operator)
        assertTrue(messages[2].isPlainText)
        assertEquals("**Literal** [text](https://example.com)", messages[2].formatText())
        assertTrue(messages[2].isComplete)
        assertEquals(AgentAnswerFeedback.LIKE, messages[2].feedback)
        assertTrue(messages.drop(3).none { it.isComplete })
        assertTrue(messages.drop(3).all { it.role == AgentMessageRole.SYSTEM })
        assertEquals("support_requested", messages[3].supportEvent?.code)
        assertEquals("operator_joined", messages[4].supportEvent?.code)
        assertEquals("Alex", messages[4].supportEvent?.operatorName)
        assertEquals("support_closed", messages[5].supportEvent?.code)
        assertEquals("inactivity", messages[5].supportEvent?.reason)
    }

    @Test
    fun namesAuthorsOnlyOnceAnOperatorHasJoinedTheChat() {
        val question = AgentMessage(role = AgentMessageRole.USER, text = "I need help")
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Calling support")
        val event = { code: String ->
            AgentMessage(
                role = AgentMessageRole.SYSTEM,
                text = code,
                supportEvent = AgentSupportEvent(code, operatorName = "Alex")
            )
        }
        val reply = AgentMessage(
            role = AgentMessageRole.OPERATOR,
            text = "Hi",
            operator = AgentV2OperatorAuthor("operator", "Alex")
        )

        assertFalse(listOf(question, answer, event("support_requested")).hasSupportOperatorJoined())
        assertTrue(listOf(question, answer, event("operator_joined")).hasSupportOperatorJoined())
        assertTrue(listOf(question, answer, reply).hasSupportOperatorJoined())
        assertTrue(
            listOf(question, reply, event("support_closed"), answer).hasSupportOperatorJoined()
        )
    }

    @Test
    fun describesSupportUnderTheTitleAndInTheComposerWhileItHasTheChat() {
        assertNull(getAgentSupportSubtitle(AgentVM.SupportState.None))
        assertNull(getAgentSupportSubtitle(AgentVM.SupportState.Closed))
        assertEquals(
            "\$agent_support_waiting",
            getAgentSupportSubtitle(AgentVM.SupportState.Waiting)
        )
        assertEquals(
            "\$agent_support_with_operator",
            getAgentSupportSubtitle(AgentVM.SupportState.Operator("Alex"))
        )
        assertEquals(
            "\$agent_support_label",
            getAgentSupportSubtitle(AgentVM.SupportState.Operator(null))
        )
        assertEquals("\$agent_support_placeholder", getAgentComposerPlaceholder(true))
        assertEquals("Ask anything", getAgentComposerPlaceholder(false))
    }

    @Test
    fun declaresSupportHandoffToTheAgent() {
        assertEquals(true, AGENT_UI_CAPABILITY_FLAGS["supportsSupportHandoff"])
    }

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
    fun restoresTheRatingOfAnAnswerAndLetsOnlyACompleteOneBeRated() {
        val persisted = AgentV2PersistedMessage(
            id = "sdk-answer",
            threadId = "thread",
            role = "assistant",
            status = "complete",
            content = AgentV2MessageContent.Markdown("Staking locks coins to earn a reward."),
            createdAt = "2026-10-05T12:00:00.000Z",
            followups = listOf(AgentV2FollowUp("next", "suggested_prompt", "Tell me more.")),
            feedback = "dislike"
        )

        val rated = mapAgentV2Message(persisted)!!
        val unknownRating = mapAgentV2Message(persisted.copy(feedback = "helpful"))!!
        val cancelled = mapAgentV2Message(persisted.copy(status = "cancelled", feedback = null))!!

        assertTrue(rated.isComplete)
        assertEquals(AgentAnswerFeedback.DISLIKE, rated.feedback)
        assertNull(unknownRating.feedback)
        assertFalse(cancelled.isComplete)
        // A stopped answer keeps its text without suggestions, and doesn't show when it has nothing
        assertEquals("Staking locks coins to earn a reward.", cancelled.text)
        assertTrue(cancelled.followups.isEmpty())
        assertNull(
            mapAgentV2Message(
                persisted.copy(
                    status = "cancelled",
                    content = AgentV2MessageContent.Markdown(""),
                    feedback = null
                )
            )
        )
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
    fun holdsBackABareListMarkerAfterATableWhileTheAnswerStreams() {
        val table = AgentV2AnswerTable(
            "t1",
            AgentV2DisplayTable("display", listOf("Asset"), listOf(listOf("TON")), emptyList())
        )
        val blocks = buildAgentV2MessageBlocks(
            "Fees:\n\nTotal:\n- **",
            listOf(table),
            listOf(AgentV2AnswerTableReference("t1", "Fees:\n\n".length))
        )
        assertTrue(blocks[1] is MarkdownParser.Block.Table)
        val tail = blocks.last() as MarkdownParser.Block.Text
        // While the answer streams, its last text parses as arriving, which holds back the bare marker
        assertEquals(blocks.lastIndex, arrivingRichBlockIndex(blocks, isStreaming = true))
        assertTrue(MarkdownParser.isListMarks(tail.value.lines().last()))
        // Complete, the answer's text renders as it is
        assertNull(arrivingRichBlockIndex(blocks, isStreaming = false))
        // A table the answer ends with takes no text that is still coming in
        assertNull(arrivingRichBlockIndex(blocks.take(2), isStreaming = true))
    }

    @Test
    fun keepsAnswerLinkLabelsAsTextInsideCode() {
        val blocks = buildAgentV2MessageBlocks(
            "Run:\n```\nsee Docs\n```",
            emptyList(),
            emptyList(),
            listOf(AgentV2AnswerLink(13, 4, "https://a.io/"))
        )

        assertEquals(MarkdownParser.Block.Code(null, "see Docs"), blocks[1])
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
    fun keepsTextApartFromTheFailureOfAnInvalidHistoryExtension() {
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
        assertEquals("Valid answer", message.text)
        assertEquals(agentV2ErrorText("invalid_event"), message.failureText)
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
