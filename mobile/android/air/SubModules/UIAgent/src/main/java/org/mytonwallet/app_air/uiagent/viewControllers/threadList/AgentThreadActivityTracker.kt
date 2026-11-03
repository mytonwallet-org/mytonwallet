package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import org.mytonwallet.app_air.uiagent.agentV2.getAgentAnalyzingRequestText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentV2RunActivityText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentWritingAnswerText
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunActivityEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update

/**
 * What the Agent is doing in each thread while it answers, from the SDK's run updates: the analysis until its first
 * step, each step the backend reports, then the writing of the answer until it completes or the run ends
 */
internal class AgentThreadActivityTracker(
    private val analyzingText: () -> String = ::getAgentAnalyzingRequestText,
    private val writingText: () -> String = ::getAgentWritingAnswerText,
    private val stepText: (AgentV2RunActivityEvent) -> String? = ::getAgentV2RunActivityText
) {
    private data class Entry(val runId: String?, val text: String, val updatedAt: Long)

    /** A loaded chat's own account of its answer */
    data class LoadedChat(val threadId: String, val isAnswering: Boolean, val text: String?)

    private val entries = mutableMapOf<String, Entry>()

    // Runs whose answer completed or that ended, oldest first: their late step updates are ignored
    private val finishedRunIds = ArrayDeque<String>()

    val answeringThreadIds: Set<String> get() = entries.keys.toSet()

    fun getText(threadId: String): String? = entries[threadId]?.text

    /** Applies a run update and returns the threads whose status changed */
    fun handle(update: AgentV2Update, nowMs: Long): Set<String> = when (update) {
        is AgentV2Update.RunStarted -> {
            finishedRunIds.remove(update.runId)
            set(update.threadId, update.runId, analyzingText(), nowMs)
        }

        is AgentV2Update.RunActivityChanged -> {
            val text = stepText(update.event)
            val isCurrent = update.event.runId == update.runId && update.runId !in finishedRunIds
            if (isCurrent && text != null) {
                set(update.threadId, update.runId, text, nowMs)
            } else {
                emptySet()
            }
        }

        is AgentV2Update.MessageStarted -> {
            // A run that goes on to another message is answering again
            finishedRunIds.remove(update.runId)
            emptySet()
        }

        is AgentV2Update.TextDelta -> {
            finishedRunIds.remove(update.runId)
            set(update.threadId, update.runId, writingText(), nowMs)
        }

        is AgentV2Update.SemanticContentAvailable -> {
            finishedRunIds.remove(update.runId)
            set(update.threadId, update.runId, writingText(), nowMs)
        }

        is AgentV2Update.MessageCompleted -> finish(update.threadId, update.runId)

        is AgentV2Update.RunCancelled -> finish(update.threadId, update.runId)

        is AgentV2Update.RunFailed -> update.threadId?.let { finish(it, update.runId) }.orEmpty()

        // Losing the wallet's authority without a thread ends every run
        is AgentV2Update.WalletAuthorityChanged ->
            if (update.threadId == null && !update.preservesActiveRuns) removeAll() else emptySet()

        else -> emptySet()
    }

    /** Takes each loaded chat's word on whether it is answering, and drops threads that went quiet without one */
    fun sync(chats: List<LoadedChat>, nowMs: Long): Set<String> {
        val changed = mutableSetOf<String>()
        val loadedThreadIds = chats.mapTo(mutableSetOf()) { it.threadId }
        for (chat in chats) {
            if (!chat.isAnswering) {
                if (entries.remove(chat.threadId) != null) changed.add(chat.threadId)
            } else if (!entries.containsKey(chat.threadId) && !chat.text.isNullOrEmpty()) {
                entries[chat.threadId] = Entry(null, chat.text, nowMs)
                changed.add(chat.threadId)
            }
        }
        val iterator = entries.iterator()
        while (iterator.hasNext()) {
            val (threadId, entry) = iterator.next()
            if (threadId !in loadedThreadIds && nowMs - entry.updatedAt > STALE_INTERVAL_MS) {
                iterator.remove()
                changed.add(threadId)
            }
        }
        return changed
    }

    fun remove(threadId: String): Set<String> =
        if (entries.remove(threadId) == null) emptySet() else setOf(threadId)

    fun removeAll(): Set<String> {
        val threadIds = entries.keys.toSet()
        entries.clear()
        return threadIds
    }

    private fun set(threadId: String, runId: String, text: String, nowMs: Long): Set<String> {
        val previous = entries[threadId]
        entries[threadId] = Entry(runId, text, nowMs)
        return if (previous?.text == text) emptySet() else setOf(threadId)
    }

    private fun finish(threadId: String, runId: String?): Set<String> {
        if (runId != null && runId !in finishedRunIds) {
            finishedRunIds.addLast(runId)
            while (finishedRunIds.size > FINISHED_RUN_LIMIT) finishedRunIds.removeFirst()
        }
        // A newer run of the thread keeps its status
        val entry = entries[threadId] ?: return emptySet()
        if (runId != null && entry.runId != null && entry.runId != runId) return emptySet()
        entries.remove(threadId)
        return setOf(threadId)
    }

    private companion object {
        // A thread without updates for this long and without a loaded chat to vouch for its run is no longer answering
        const val STALE_INTERVAL_MS = 3 * 60 * 1000L
        const val FINISHED_RUN_LIMIT = 64
    }
}
