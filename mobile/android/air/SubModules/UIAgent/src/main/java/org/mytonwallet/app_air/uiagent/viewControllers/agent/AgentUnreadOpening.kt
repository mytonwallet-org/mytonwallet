package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadReadState
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/**
 * Whether a chat opened by its id opens at its first unread message. A summary from the cached list may predate an
 * answer, so a chat opened from such a row that shows its cached copy learns from its loaded thread whether it is
 * unread, and counts as seen only after that.
 */
internal class AgentUnreadOpening(
    thread: AgentV2ThreadSummary?,
    hasOpening: Boolean,
    isSummaryCached: Boolean,
    private val readState: AgentThreadReadState
) {
    val canShowCachedMessages =
        thread != null && canShowAgentCachedMessages(thread, hasOpening, readState)
    private val openedSeenMessageCount =
        thread?.takeIf { !hasOpening }?.let(readState::getSeenMessageCountIfUnread)
    private val shouldCheckLoadedThread = isSummaryCached && canShowCachedMessages
    private var isResolved = false

    /** The chat waits to count as seen until its loaded thread tells whether it is unread */
    val isAwaitingLoadedThread: Boolean get() = shouldCheckLoadedThread && !isResolved

    /**
     * The seen message count to open at, once the chat has loaded its newest messages, which a support chat loads after
     * it shows what it holds; null when it opens as usual
     */
    fun resolveSeenMessageCount(model: AgentVM): Int? {
        if (isResolved || !model.hasLoadedNewestMessages) return null
        isResolved = true
        return openedSeenMessageCount
            ?: model.currentThread.takeIf { shouldCheckLoadedThread }
                ?.let(readState::getSeenMessageCountIfUnread)
    }
}
