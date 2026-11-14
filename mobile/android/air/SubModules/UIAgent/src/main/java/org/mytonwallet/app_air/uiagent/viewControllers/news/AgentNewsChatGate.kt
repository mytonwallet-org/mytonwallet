package org.mytonwallet.app_air.uiagent.viewControllers.news

import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/** A chat the feed opens over itself, so Back returns to the feed */
internal sealed interface AgentNewsChatTarget {
    /** A news item the feed has loaded, which opens as its card does */
    data class FeedNews(val item: AgentV2NewsFeedItem) : AgentNewsChatTarget

    /** A news item the feed hasn't loaded, from a digest's headline */
    data class News(val headline: AgentV2NewsDigestHeadline) : AgentNewsChatTarget

    /** A digest's discussion the user has written in, which opens as it is */
    data class Discussion(val thread: AgentV2ThreadSummary) : AgentNewsChatTarget

    /**
     * A visit to a digest's discussion, which starts it or finds the one it has, showing the digest's post from the
     * feed's copy of it until its thread comes
     */
    data class Digest(
        val id: String,
        val preview: AgentV2ThreadDigestCard? = null,
        val discussionNaming: AgentV2NewsFeedItem.DiscussionNaming? = null,
        val shouldDeferCreation: Boolean = false
    ) : AgentNewsChatTarget
}

/** A digest's headline opens its news item's discussion, as the item's card does when the feed has the item */
internal fun resolveAgentDigestHeadlineTarget(
    headline: AgentV2NewsDigestHeadline,
    items: List<AgentV2NewsFeedItem>
): AgentNewsChatTarget = items.firstOrNull { it.eventId == headline.eventId }
    ?.let(AgentNewsChatTarget::FeedNews)
    ?: AgentNewsChatTarget.News(headline)

/**
 * A digest's Discuss opens its discussion as it is once [findStartedThread] finds the user has written there, otherwise
 * a visit to it
 */
internal fun resolveAgentDigestDiscussionTarget(
    digest: AgentV2NewsFeedDigest,
    findStartedThread: (String) -> AgentV2ThreadSummary?
): AgentNewsChatTarget = digest.discussion?.threadId?.let(findStartedThread)
    ?.let(AgentNewsChatTarget::Discussion)
    ?: AgentNewsChatTarget.Digest(
        digest.id,
        AgentV2ThreadDigestCard(digest.id, digest.deliveredAt, digest.total, digest.top),
        digest.discussionNaming,
        shouldDeferCreation = digest.discussion == null
    )

/**
 * One chat opens from the feed at a time: taps while one opens do nothing until the feed shows again, and an opening
 * that could not open its chat, or threw, releases the tap, so it can be repeated
 */
internal class AgentNewsChatGate {
    private var isOpening = false

    /** Runs [open] unless a chat is opening; [open] tells whether it opened one */
    fun open(open: () -> Boolean) {
        if (isOpening) return
        isOpening = true
        try {
            isOpening = open()
        } catch (error: Throwable) {
            isOpening = false
            throw error
        }
    }

    fun release() {
        isOpening = false
    }
}
