package org.mytonwallet.app_air.uiagent.viewControllers.agent

import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

private const val DIGEST_HEADLINE_SEPARATOR = " · "

internal fun agentNewsPostBodyText(news: AgentV2ThreadNewsCard): String? =
    news.body?.takeIf { it.isNotBlank() } ?: news.excerpt?.takeIf { it.isNotBlank() }

/**
 * What a news post shows, at the top of a discussion or as a feed card: a news item's, or a daily digest's, whose
 * header names the digest and its time in place of News and whose text is its title over its headlines in a line,
 * without a picture or a source
 */
internal data class AgentNewsPostContent(
    val headline: String,
    val body: String?,
    val imageUrl: String?,
    val sources: List<AgentV2NewsFeedItem.Source>?,
    val publishedAt: String,
    val isDigest: Boolean = false,
    /** The source name a news card stored before it kept links */
    val legacySource: String? = null
) {
    constructor(news: AgentV2ThreadNewsCard) : this(
        headline = news.headline,
        body = agentNewsPostBodyText(news),
        imageUrl = news.imageUrl,
        sources = news.sources,
        publishedAt = news.publishedAt,
        legacySource = news.source
    )

    constructor(digest: AgentV2ThreadDigestCard) : this(
        headline = LocaleController.getString("\$agent_digest_title"),
        body = digest.top.joinToString(DIGEST_HEADLINE_SEPARATOR) { it.headline }
            .takeIf { it.isNotEmpty() },
        imageUrl = null,
        sources = null,
        publishedAt = digest.windowEnd,
        isDigest = true
    )
}

internal fun AgentNewsChatRequest.newsPostCard() = AgentV2ThreadNewsCard(
    eventId = eventId,
    headline = headline,
    excerpt = excerpt,
    imageUrl = imageUrl,
    publishedAt = publishedAt.orEmpty(),
    body = body,
    sources = sources
)

/**
 * The chat's messages with its post first: the news item's, or a digest's, which stands where a news item's does with
 * the digest's card in place of the news. A preview of the news shows its post until the thread loads, once it has
 * what the post shows.
 */
internal fun agentNewsPostMessages(
    messages: List<AgentMessage>,
    historyCursor: String?,
    threadNews: AgentV2ThreadNewsCard?,
    request: AgentNewsChatRequest?,
    threadDigest: AgentV2ThreadDigestCard? = null
): List<AgentTimelineItem.Message> {
    val news = threadNews?.let { keepFeedPicture(it, request) } ?: request?.takeIf {
        it.headline.isNotBlank() && it.publishedAt?.let(::parseAgentV2Timestamp) != null
    }?.newsPostCard()
    val digest = threadDigest.takeIf { news == null }
    val content = news?.let(::AgentNewsPostContent) ?: digest?.let(::AgentNewsPostContent)
    val explicitPost = messages.firstOrNull { it.newsPost }
    if (content == null || (!historyCursor.isNullOrEmpty() && explicitPost == null)) {
        return messages.map { AgentTimelineItem.Message(it) }
    }
    val storedPost = explicitPost ?: news?.let { card ->
        messages.firstOrNull {
            it.role == AgentMessageRole.USER
        }?.takeIf { it.text == card.headline }
    }
    val post = AgentMessage(
        id = news?.let { "news-post-${it.eventId}" } ?: "digest-post-${digest!!.id}",
        sdkMessageId = storedPost?.let { it.sdkMessageId ?: it.id },
        role = AgentMessageRole.ASSISTANT,
        text = "**${content.headline}**" +
            ((if (news != null) news.body else content.body)?.let { "\n\n$it" } ?: ""),
        followups = explicitPost?.followups.orEmpty(),
        date = parseAgentV2Timestamp(content.publishedAt) ?: Date(0),
        newsPost = true
    )
    return listOf(AgentTimelineItem.Message(post, content)) +
        messages.filterNot { it.id == storedPost?.id }.map { AgentTimelineItem.Message(it) }
}

/**
 * The thread's card of the news a chat was opened for from the feed, with the picture the feed showed: decoded already,
 * it stays through the card's flight into the chat and after, instead of loading again when the thread's card names it
 * otherwise or not at all
 */
private fun keepFeedPicture(
    news: AgentV2ThreadNewsCard,
    request: AgentNewsChatRequest?
): AgentV2ThreadNewsCard {
    if (request == null || request.eventId != news.eventId) return news
    val imageUrl = request.imageUrl?.takeIf { it.isNotBlank() } ?: return news
    return if (imageUrl == news.imageUrl) news else news.copy(imageUrl = imageUrl)
}

internal fun agentNewsAllowsSubmission(
    request: AgentNewsChatRequest?,
    state: AgentVM.State
): Boolean = request == null || state == AgentVM.State.LOADING ||
    state == AgentVM.State.READY || state == AgentVM.State.RUNNING

/**
 * The wait for a News post's suggestions. Placeholders stand in for them once they have taken [PLACEHOLDER_DELAY_MS],
 * fading in then, so suggestions that come sooner show without them; after [TIMEOUT_MS] the post shows none. The
 * wait starts when the chat first asks for it, and [cancel] ends it with the chat.
 */
internal class AgentNewsFollowupWait(
    private val postDelayed: (Runnable, Long) -> Unit,
    private val removeCallbacks: (Runnable) -> Unit,
    private val onChange: () -> Unit
) {
    private var timers: List<Runnable>? = null
    private var isLong = false

    var isExpired = false
        private set

    /** Starts the wait, unless it has, and tells whether placeholders stand in for the suggestions by now */
    fun arePlaceholdersDue(): Boolean {
        if (timers == null) start()
        return isLong && !isExpired
    }

    fun cancel() {
        timers?.forEach(removeCallbacks)
    }

    private fun start() {
        val placeholders = Runnable {
            isLong = true
            onChange()
        }
        val expiry = Runnable {
            isExpired = true
            onChange()
        }
        timers = listOf(placeholders, expiry)
        postDelayed(placeholders, PLACEHOLDER_DELAY_MS)
        postDelayed(expiry, TIMEOUT_MS)
    }

    companion object {
        const val PLACEHOLDER_DELAY_MS = 1_000L
        const val TIMEOUT_MS = 25_000L
    }
}
