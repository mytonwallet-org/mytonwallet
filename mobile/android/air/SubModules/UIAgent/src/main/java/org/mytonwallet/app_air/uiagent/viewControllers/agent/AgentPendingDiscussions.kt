package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.stores.AccountStore

/**
 * Deferred discussions whose first message waits for its thread, by [getAgentDeferredDiscussionKey]. Their creation
 * outlives the chat: a chat reopened meanwhile shows the message and becomes the thread's chat, and without one the
 * thread's model sends the message and the feed learns the thread. A failed creation waits for a chat to retry it.
 */
internal class AgentPendingDiscussions(
    private val scope: CoroutineScope,
    private val acquireOpening: (AgentV2ThreadSummary, AgentChatOpening) -> AgentVM,
    private val release: (AgentVM) -> Unit
) {
    private class Entry(val opening: AgentChatOpening) {
        var job: Job? = null
        var chat: ((AgentVM) -> Unit)? = null
        var onThreadCreated: ((AgentV2ThreadSummary) -> Unit)? = null
    }

    private val entries = mutableMapOf<String, Entry>()

    /** The opening of the active wallet: another wallet's message stays with its own creation */
    fun find(key: String): AgentChatOpening? = entries[key]?.opening
        ?.takeIf { it.messageAuthority?.accountId == AccountStore.activeAccountId }

    /**
     * Creates the thread of [opening]'s staged message, or joins the creation under way. [chat] takes the thread's
     * model and owns it, unless it has left; otherwise [onThreadCreated] learns the thread.
     */
    fun create(
        key: String,
        opening: AgentChatOpening,
        chat: (AgentVM) -> Unit,
        onThreadCreated: ((AgentV2ThreadSummary) -> Unit)?,
        shouldAcceptConsent: Boolean = false
    ) {
        val entry = entries[key]?.takeIf { it.opening === opening }
            ?: Entry(opening).also { entries[key] = it }
        entry.chat = chat
        entry.onThreadCreated = onThreadCreated
        if (entry.job != null) return
        entry.job = scope.launch {
            val thread = try {
                opening.create(shouldAcceptConsent)
            } finally {
                entry.job = null
            }
            thread ?: return@launch
            if (entries[key] === entry) entries.remove(key)
            val model = acquireOpening(thread, opening)
            val chat = entry.chat
            if (chat != null) {
                chat(model)
                return@launch
            }
            entry.onThreadCreated?.invoke(model.currentThread)
            release(model)
        }
    }

    fun leave(key: String, chat: (AgentVM) -> Unit) {
        val entry = entries[key] ?: return
        if (entry.chat === chat) entry.chat = null
    }

    /** A deleted opening is forgotten; its creation goes on only to delete the thread */
    fun drop(key: String, opening: AgentChatOpening) {
        val entry = entries[key]?.takeIf { it.opening === opening } ?: return
        entries.remove(key)
        entry.chat = null
        entry.onThreadCreated = null
    }

    /** The openings no chat shows stop, as when the wallet's accounts are reset */
    fun forgetLeft() {
        entries.values.removeAll { entry ->
            (entry.chat == null).also { isLeft -> if (isLeft) entry.job?.cancel() }
        }
    }
}
