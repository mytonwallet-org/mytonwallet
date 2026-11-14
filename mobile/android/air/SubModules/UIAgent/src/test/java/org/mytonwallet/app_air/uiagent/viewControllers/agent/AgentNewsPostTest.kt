package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.agentV2.mapAgentV2Message
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsMenuSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentNewsCopyText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentNewsMenuSources
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentNewsSourceUrl
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentNewsShareText
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2FollowUp
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
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
    private val firstUser = AgentMessage(
        id = "legacy-post",
        sdkMessageId = "legacy-post",
        role = AgentMessageRole.USER,
        text = news.headline
    )

    @Test
    fun shareUsesTheShownHeadlineAndNewsLinkWhileCopyKeepsTheFullPost() {
        for (locale in listOf("ru", "en")) {
            val request = AgentNewsChatRequest(eventId = news.eventId, locale = locale)
            val post = checkNotNull(
                agentNewsPostMessages(emptyList(), null, news, request).single().newsPost
            )

            assertEquals(
                "News headline\nhttps://my.tt/agent?news=42&lang=$locale&utm_source=pulse_share",
                buildAgentNewsShareText(post)
            )
            assertEquals(
                "News headline\n\nFull news body\n\nhttps://example.com/story",
                agentNewsCopyText(post)
            )
        }
    }

    @Test
    fun menuListsEachSourceTheAppCanOpenOnceByItsNameOrSite() {
        val post = AgentNewsPostContent(
            news.copy(
                sources = listOf(
                    AgentV2NewsFeedItem.Source(name = " CoinDesk ", url = "https://coindesk.com/a"),
                    AgentV2NewsFeedItem.Source(name = "coindesk", url = "https://coindesk.com/b"),
                    AgentV2NewsFeedItem.Source(url = "https://www.theblock.co/c"),
                    AgentV2NewsFeedItem.Source(url = "https://WWW.Decrypt.co/d"),
                    AgentV2NewsFeedItem.Source(name = "Unsafe", url = "javascript:alert(1)")
                )
            )
        )

        assertEquals(
            listOf(
                AgentNewsMenuSource("CoinDesk", "https://coindesk.com/a"),
                AgentNewsMenuSource("theblock.co", "https://www.theblock.co/c"),
                AgentNewsMenuSource("Decrypt.co", "https://WWW.Decrypt.co/d")
            ),
            agentNewsMenuSources(post)
        )
    }

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
            sources = news.sources,
            discussionNaming = AgentV2NewsFeedItem.DiscussionNaming(
                title = "News discussion",
                followups = listOf("Why does this matter?", "Explain the impact")
            )
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
        assertEquals(
            request.discussionNaming?.followups,
            preview.message.followups.map { it.text }
        )
        assertTrue(
            agentNewsPostMessages(emptyList(), null, null, request.copy(discussionNaming = null))
                .single().message.followups.isEmpty()
        )
        assertTrue(
            agentNewsPostMessages(emptyList(), null, news, request)
                .single().message.followups.isEmpty()
        )
        val localUser = firstUser.copy(id = "local-question", sdkMessageId = null)
        assertSame(
            localUser,
            agentNewsPostMessages(listOf(localUser), null, null, request).last().message
        )
        assertSame(
            localUser,
            agentNewsPostMessages(listOf(localUser), null, news, request).last().message
        )
        assertTrue(saved.newsPost)
        assertEquals(preview.message.id, loaded.message.id)
        assertEquals(preview.message.date, loaded.message.date)
        assertEquals("saved-post", loaded.message.sdkMessageId)
        assertTrue(loaded.message.matchesMessageId(saved.id))
        assertEquals(
            AgentNewsPostContent(news.copy(imageUrl = request.imageUrl), request.locale),
            loaded.newsPost
        )
        assertFalse(loaded.message.isStreaming)
        assertFalse(loaded.message.isComplete)
        assertNull(loaded.message.feedback)
        assertEquals(listOf(followup), loaded.message.followups)
        assertSame(loaded.message, listOf(loaded.message).findFollowupOwner())
    }

    @Test
    fun postKeepsTheFeedsPictureOnceTheThreadsCardComesSoTheFlownInCardDoesNotReload() {
        val request = AgentNewsChatRequest(
            eventId = news.eventId,
            locale = "en",
            headline = news.headline,
            imageUrl = "https://example.com/feed.jpg"
        )
        val thread = news.copy(imageUrl = "https://example.com/thread.jpg")

        assertEquals(
            request.imageUrl,
            agentNewsPostMessages(emptyList(), null, thread, request).single().newsPost?.imageUrl
        )
        assertEquals(
            request.imageUrl,
            agentNewsPostMessages(emptyList(), null, news, request).single().newsPost?.imageUrl
        )
        // A chat opened from the list, or for other news, shows the thread's own
        val threadPost = AgentNewsPostContent(thread)
        assertEquals(
            threadPost,
            agentNewsPostMessages(emptyList(), null, thread, null).single().newsPost
        )
        assertEquals(
            threadPost,
            agentNewsPostMessages(emptyList(), null, thread, request.copy(eventId = 7))
                .single()
                .newsPost
        )
        assertEquals(
            AgentNewsPostContent(thread, request.locale),
            agentNewsPostMessages(emptyList(), null, thread, request.copy(imageUrl = null))
                .single()
                .newsPost
        )
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
        assertEquals(AgentNewsPostContent(news), items.first().newsPost)
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
        assertEquals(AgentNewsPostContent(news), items.first().newsPost)
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
        assertEquals(AgentNewsPostContent(news), items.first().newsPost)
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
        assertEquals(AgentNewsPostContent(news), local.newsPost)
        assertNull(local.message.sdkMessageId)
        assertFalse(local.message.isStreaming)
        assertEquals(
            emptyList<AgentTimelineItem.Message>(),
            agentNewsPostMessages(emptyList(), "older", news, null)
        )

        // A news chat opened by the item's id alone, as from a push, shows its post once the thread brings it
        assertTrue(
            agentNewsPostMessages(emptyList(), null, null, AgentNewsChatRequest(42)).isEmpty()
        )

        val partialHistory = agentNewsPostMessages(listOf(firstUser), "older", news, null).single()
        assertSame(firstUser, partialHistory.message)
        assertNull(partialHistory.newsPost)
        val ordinary = agentNewsPostMessages(listOf(firstUser), null, null, null).single()
        assertSame(firstUser, ordinary.message)
        assertNull(ordinary.newsPost)
    }

    @Test
    fun digestThreadShowsItsServerPostWithTheDigestsHeadlinesWithoutPictureOrSource() {
        // Its headlines are all its news, so the post has no line of the news it leaves out
        val digest = AgentV2ThreadDigestCard(
            "en:2026-11-08T18:00:00.000Z",
            "2026-11-08T18:00:00.000Z",
            2,
            listOf(
                AgentV2NewsDigestHeadline(1, "Binance restored its tokens"),
                AgentV2NewsDigestHeadline(2, "BlackRock sold Bitcoin")
            )
        )
        val followup = AgentV2FollowUp("more", "suggested_prompt", "What else happened?")
        val naming = AgentV2NewsFeedItem.DiscussionNaming(
            title = "Digest discussion",
            icon = "📰",
            followups = listOf("What matters most?", "Explain the impact")
        )
        val preview = agentNewsPostMessages(
            emptyList(),
            null,
            null,
            null,
            digest,
            discussionNaming = naming
        ).single()
        assertEquals(AgentNewsPostContent(digest), preview.newsPost)
        assertEquals(naming.followups, preview.message.followups.map { it.text })
        assertTrue(preview.message.followups.all { it.kind == "suggested_prompt" })
        assertTrue(
            agentNewsPostMessages(emptyList(), null, null, null, digest)
                .single().message.followups.isEmpty()
        )
        val stored = AgentMessage(
            id = "server-post",
            sdkMessageId = "server-post",
            role = AgentMessageRole.ASSISTANT,
            text = "Daily digest",
            followups = listOf(followup),
            newsPost = true
        )
        val question = firstUser.copy(id = "question", text = "Why?")
        val items = agentNewsPostMessages(
            listOf(stored, question),
            null,
            null,
            null,
            digest,
            discussionNaming = naming
        )
        val post = checkNotNull(items.first().newsPost)
        val title = LocaleController.getString("\$agent_digest_title")

        assertEquals(AgentNewsPostContent(digest), post)
        assertTrue(post.isDigest)
        assertEquals(title, post.headline)
        // The headlines are listed as on the digest's card, and copied one per line
        assertNull(post.body)
        assertEquals(digest.top, post.digestHeadlines)
        assertNull(post.digestRemainder)
        assertNull(post.imageUrl)
        assertNull(agentNewsSourceUrl(post))
        assertNull(buildAgentNewsShareText(post))
        assertEquals(
            "$title\n\n• Binance restored its tokens\n• BlackRock sold Bitcoin",
            agentNewsCopyText(post)
        )
        assertEquals("server-post", items.first().message.sdkMessageId)
        assertEquals(preview.message.id, items.first().message.id)
        assertEquals(listOf(followup), items.first().message.followups)
        assertEquals(parseAgentV2Timestamp(digest.windowEnd), items.first().message.date)
        assertEquals(listOf(question), items.drop(1).map { it.message })
        // A thread about a news item shows the news, whatever else it carries
        assertEquals(
            AgentNewsPostContent(news),
            agentNewsPostMessages(emptyList(), null, news, null, digest).single().newsPost
        )
    }

    @Test
    fun omitShareForNewsWithNonPositiveEventIds() {
        for (eventId in listOf(0, -1)) {
            assertNull(
                buildAgentNewsShareText(AgentNewsPostContent(news.copy(eventId = eventId), "en"))
            )
        }
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

    @Test
    fun suggestionsComingWithinASecondHaveNoPlaceholdersAndLaterOnesHaveThem() {
        val timers = FakeTimers()
        var changeCount = 0
        val wait = AgentNewsFollowupWait(timers::postDelayed, timers::removeCallbacks) {
            changeCount++
        }

        // Suggestions that come within 1 s find no placeholders to replace
        assertFalse(wait.arePlaceholdersDue())
        assertEquals(
            listOf(AgentNewsFollowupWait.PLACEHOLDER_DELAY_MS, AgentNewsFollowupWait.TIMEOUT_MS),
            timers.delays
        )
        assertFalse(wait.arePlaceholdersDue())
        assertEquals(0, changeCount)

        // Later ones replace the placeholders that came in after 1 s
        timers.runUntil(AgentNewsFollowupWait.PLACEHOLDER_DELAY_MS)
        assertEquals(1, changeCount)
        assertTrue(wait.arePlaceholdersDue())

        timers.runUntil(AgentNewsFollowupWait.TIMEOUT_MS)
        assertTrue(wait.isExpired)
        assertFalse(wait.arePlaceholdersDue())
    }

    @Test
    fun aChatLeftWithinASecondShowsNoPlaceholders() {
        val timers = FakeTimers()
        val wait = AgentNewsFollowupWait(timers::postDelayed, timers::removeCallbacks) {
            error("A chat left changes nothing")
        }
        assertFalse(wait.arePlaceholdersDue())

        wait.cancel()
        assertTrue(timers.delays.isEmpty())
        assertFalse(wait.arePlaceholdersDue())
    }

    private class FakeTimers {
        private val pending = mutableListOf<Pair<Runnable, Long>>()
        val delays: List<Long> get() = pending.map { it.second }

        fun postDelayed(runnable: Runnable, delay: Long) {
            pending += runnable to delay
        }

        fun removeCallbacks(runnable: Runnable) {
            pending.removeAll { it.first === runnable }
        }

        fun runUntil(time: Long) {
            val due = pending.filter { it.second <= time }
            pending.removeAll(due)
            due.forEach { it.first.run() }
        }
    }
}
