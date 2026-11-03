package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.mapAgentV2Message
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

class AgentNewsPostTest {
    private val news = AgentV2ThreadNewsCard(
        eventId = 42,
        headline = "News headline",
        publishedAt = "2026-10-20T12:00:00Z",
        body = "Full **news** body",
        sources = listOf(
            AgentV2NewsFeedItem.Source(name = "Source", url = "https://example.com/story")
        )
    )
    private val firstUser = AgentMessage(role = AgentMessageRole.USER, text = news.headline)

    @Test
    fun postBodyFallsBackToVisibleExcerptWhenBodyIsEmpty() {
        val card = news.copy(body = "", excerpt = "Visible **excerpt**")

        assertEquals("Visible **excerpt**", agentNewsPostBodyText(card))
    }

    @Test
    fun previewImmediatelyShowsFullFeedPostAndStoredPostReplacesItInTheSameRow() {
        val request = AgentNewsChatRequest(
            eventId = news.eventId,
            locale = "en",
            headline = news.headline,
            excerpt = "Feed excerpt",
            imageUrl = "https://example.com/feed.jpg",
            publishedAt = news.publishedAt,
            body = news.body,
            sources = news.sources
        )
        val preview = agentNewsPostMessages(emptyList(), null, null, request).single()
        val followup = AgentV2FollowUp("impact", "suggested_prompt", "Why does this matter?")
        val saved = checkNotNull(
            mapAgentV2Message(
                AgentV2PersistedMessage(
                    id = "saved-post",
                    threadId = "thread",
                    role = "assistant",
                    status = "complete",
                    content = AgentV2MessageContent.Markdown(
                        "**${news.headline}**\n\n${news.body}"
                    ),
                    createdAt = news.publishedAt,
                    followups = listOf(followup),
                    newsPost = true
                )
            )
        )
        val loaded = agentNewsPostMessages(listOf(saved), null, news, request).single()

        assertEquals(news.body, preview.newsPost?.body)
        assertEquals(news.sources, preview.newsPost?.sources)
        assertTrue(preview.message.followups.isEmpty())
        assertTrue(saved.newsPost)
        assertEquals(preview.message.id, loaded.message.id)
        assertEquals(preview.message.date, loaded.message.date)
        assertEquals("saved-post", loaded.message.sdkMessageId)
        assertTrue(loaded.message.matchesMessageId(saved.id))
        assertSame(news, loaded.newsPost)
        assertFalse(loaded.message.isStreaming)
        assertFalse(loaded.message.isComplete)
        assertNull(loaded.message.feedback)
        assertEquals(listOf(followup), loaded.message.followups)
        assertSame(loaded.message, listOf(loaded.message).findFollowupOwner())
    }

    @Test
    fun explicitPostTakesPrecedenceOverAUserQuestionThatMatchesHeadline() {
        val post = AgentMessage(
            role = AgentMessageRole.ASSISTANT,
            text = "**${news.headline}**\n\n${news.body}",
            newsPost = true
        )
        val question = firstUser.copy(id = "question")
        val items = agentNewsPostMessages(listOf(post, question), null, news, null)

        assertEquals(2, items.size)
        assertSame(news, items.first().newsPost)
        assertSame(question, items.last().message)
        assertNull(items.last().newsPost)
    }

    @Test
    fun explicitPostRemainsTheFirstPostRowWhenEarlierHistoryIsAvailable() {
        val saved = AgentMessage(
            id = "saved-post",
            sdkMessageId = "saved-post",
            role = AgentMessageRole.ASSISTANT,
            text = "**${news.headline}**\n\n${news.body}",
            isComplete = true,
            feedback = AgentAnswerFeedback.LIKE,
            newsPost = true
        )
        val answer = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Discussion answer")
        val question = firstUser.copy(id = "question")
        val messages = listOf(answer, saved, question)
        val items = agentNewsPostMessages(messages, "older", news, null)
        val withoutCursor = agentNewsPostMessages(messages, null, news, null)

        assertEquals(3, items.size)
        assertEquals(1, items.count { it.newsPost != null })
        assertSame(news, items.first().newsPost)
        assertEquals(withoutCursor.first().message.id, items.first().message.id)
        assertEquals(withoutCursor.first().message.date, items.first().message.date)
        assertEquals(saved.sdkMessageId, items.first().message.sdkMessageId)
        assertTrue(items.first().message.newsPost)
        assertFalse(items.first().message.isComplete)
        assertNull(items.first().message.feedback)
        assertEquals(listOf(answer, question), items.drop(1).map { it.message })
        assertTrue(items.drop(1).all { it.newsPost == null })
        assertTrue(items.drop(1).none { it.message.matchesMessageId(saved.id) })
    }

    @Test
    fun legacyFirstUserHeadlineBecomesThePostAndOtherMessagesStayInOrder() {
        val assistant = AgentMessage(role = AgentMessageRole.ASSISTANT, text = "Old analysis")
        val secondUser = firstUser.copy(id = "second")
        val items =
            agentNewsPostMessages(listOf(firstUser, assistant, secondUser), null, news, null)

        assertEquals(3, items.size)
        assertSame(news, items.first().newsPost)
        assertEquals(firstUser.id, items.first().message.sdkMessageId)
        assertEquals(AgentMessageRole.ASSISTANT, items.first().message.role)
        assertTrue(items.first().message.followups.isEmpty())
        assertEquals(listOf(assistant, secondUser), items.drop(1).map { it.message })
        assertTrue(items.drop(1).all { it.newsPost == null })
    }

    @Test
    fun legacyHeadlineMustMatchExactlyAndOnlyTheFirstUserCanBeReplaced() {
        val edited = firstUser.copy(text = "${news.headline} ")
        val matchingLater = firstUser.copy(id = "later")
        val items = agentNewsPostMessages(listOf(edited, matchingLater), null, news, null)

        assertEquals(3, items.size)
        assertNull(items.first().message.sdkMessageId)
        assertEquals(listOf(edited, matchingLater), items.drop(1).map { it.message })
    }

    @Test
    fun emptyThreadUsesLocalPostAndEarlierHistorySuppressesPostInsertion() {
        val local = agentNewsPostMessages(emptyList(), null, news, null).single()
        assertSame(news, local.newsPost)
        assertNull(local.message.sdkMessageId)
        assertFalse(local.message.isStreaming)
        assertEquals(
            emptyList<AgentTimelineItem.Message>(),
            agentNewsPostMessages(emptyList(), "older", news, null)
        )

        val partialHistory = agentNewsPostMessages(listOf(firstUser), "older", news, null).single()
        assertSame(firstUser, partialHistory.message)
        assertNull(partialHistory.newsPost)
        val ordinary = agentNewsPostMessages(listOf(firstUser), null, null, null).single()
        assertSame(firstUser, ordinary.message)
        assertNull(ordinary.newsPost)
    }

    @Test
    fun newsAllowsSubmissionWhileKnownThreadLoadsWithoutRestrictingOtherChats() {
        val request = AgentNewsChatRequest(42, "en", news.headline)

        assertEquals(
            listOf(AgentVM.State.LOADING, AgentVM.State.READY, AgentVM.State.RUNNING),
            AgentVM.State.entries.filter { agentNewsAllowsSubmission(request, it) }
        )
        assertEquals(
            AgentVM.State.entries,
            AgentVM.State.entries.filter { agentNewsAllowsSubmission(null, it) }
        )
    }
}
