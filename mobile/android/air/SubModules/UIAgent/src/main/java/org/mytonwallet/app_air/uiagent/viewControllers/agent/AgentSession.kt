package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2ChatActivityGroup
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadActivityTracker
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

object AgentSession {
    private const val RECENT_CHAT_LIMIT = 8

    internal val chatActivityGroup = AgentV2ChatActivityGroup()
    internal val cachedHistories = AgentCachedHistories(
        CoroutineScope(SupervisorJob() + Dispatchers.Main),
        readCachedMessages = LiveAgentV2Client()::getCachedMessages
    )
    private val scrollPositions = mutableMapOf<String, AgentVM.ScrollPosition>()
    private val sessions = AgentThreadSessions<AgentVM>(
        shouldRetain = { it.shouldRetainSession },
        setIdleHandler = { model, handler -> model.onSessionIdle = handler },
        destroy = { model ->
            val threadId = model.currentThread.id
            model.scrollPosition?.let { scrollPositions[threadId] = it }
            model.onDestroy()
        },
        recentLimit = RECENT_CHAT_LIMIT,
        canKeep = { it.canStayLoaded }
    )

    /**
     * The chat of [thread]: the loaded one, as a chat closed lately stays, refreshed in place when [thread] is newer
     * than what it shows, or a new one. A new chat of a thread opened by its id can show the thread's cached messages
     * while its history loads, from its first frame when [cachedHistories] holds them; a loaded chat keeps its own.
     */
    fun acquire(thread: AgentV2ThreadSummary, canShowCachedMessages: Boolean = false): AgentVM =
        sessions.acquire(thread.id, keepsRecent = true) {
            AgentVM(
                scrollPositions[thread.id],
                initialThread = thread,
                canShowCachedMessages = canShowCachedMessages
            )
        }.also { it.refreshThreadIfNeeded(thread) }

    /** The chats closed lately stop staying loaded, as when the wallet's accounts are reset */
    internal fun forgetRecentChats() {
        sessions.forgetRecent()
    }

    /** A model [create] makes goes with its last owner, as its maker owns its lifetime */
    internal fun acquire(thread: AgentV2ThreadSummary, create: () -> AgentVM): AgentVM =
        sessions.acquire(thread.id, create = create)

    internal fun acquireOpening(
        thread: AgentV2ThreadSummary,
        initialMessages: List<AgentMessage>,
        entryPoint: AgentV2EntryPoint
    ): AgentVM = sessions.acquire(thread.id, keepsRecent = true) {
        AgentVM(
            scrollPositions[thread.id],
            initialThread = thread,
            initialMessages = initialMessages,
            initialOpeningEntryPoint = entryPoint
        )
    }.also {
        it.acceptOpening(initialMessages, entryPoint)
    }

    fun release(viewModel: AgentVM) {
        val threadId = viewModel.currentThread.id
        sessions.release(threadId, viewModel)
    }

    /** Deletion stops the model even if the server refuses, so reopening must build a new one. */
    internal fun deleteChat(viewModel: AgentVM, onFailure: (Throwable) -> Unit) {
        sessions.evict(viewModel.currentThread.id, viewModel)
        viewModel.deleteChat(onFailure)
    }

    /** The chat of [threadId] while it is loaded */
    internal fun findLoadedModel(threadId: String): AgentVM? =
        sessions.getModels().firstOrNull { it.currentThread.id == threadId }

    /** The loaded chats' own account of whether they are answering, for the list's statuses */
    internal fun getLoadedChats(): List<AgentThreadActivityTracker.LoadedChat> =
        // A chat still loading doesn't know yet whether its thread is answering
        sessions.getModels().filter { it.state != AgentVM.State.LOADING }.map { model ->
            val answeringText = model.answeringText
            AgentThreadActivityTracker.LoadedChat(
                threadId = model.currentThread.id,
                isAnswering = answeringText != null,
                text = answeringText
            )
        }
}

/**
 * One model per thread while anyone owns it. The [recentLimit] threads left last keep theirs loaded, as iOS keeps 8, so
 * that reopening one shows it at once: those whose model was made to be kept and that [canKeep] lets stay.
 */
internal class AgentThreadSessions<Model : Any>(
    private val shouldRetain: (Model) -> Boolean,
    private val setIdleHandler: (Model, (() -> Unit)?) -> Unit,
    private val destroy: (Model) -> Unit,
    private val recentLimit: Int = 0,
    private val canKeep: (Model) -> Boolean = { true }
) {
    private class Entry<Model>(val model: Model, val keepsRecent: Boolean, var ownerCount: Int = 1)

    private val entries = mutableMapOf<String, Entry<Model>>()

    // The threads whose models stay loaded after their last owner left, the latest last
    private val recent = LinkedHashSet<String>()

    fun acquire(threadId: String, keepsRecent: Boolean = false, create: () -> Model): Model {
        val entry = entries[threadId]
        if (entry != null) {
            entry.ownerCount++
            setIdleHandler(entry.model, null)
            return entry.model
        }
        return create().also { entries[threadId] = Entry(it, keepsRecent) }
    }

    fun getModels(): List<Model> = entries.values.map { it.model }

    fun release(threadId: String, model: Model) {
        val entry = entries[threadId] ?: return
        if (entry.model !== model || entry.ownerCount == 0) return
        entry.ownerCount--
        if (entry.ownerCount != 0) return
        recent.remove(threadId)
        if (recentLimit > 0 && entry.keepsRecent && canKeep(model)) {
            recent.add(threadId)
            while (recent.size > recentLimit) {
                val oldest = recent.first()
                recent.remove(oldest)
                entries[oldest]?.let { leave(oldest, it) }
            }
            if (threadId in recent) return
        }
        leave(threadId, entry)
    }

    /** Later releases do nothing; the caller stops [model]. */
    fun evict(threadId: String, model: Model) {
        val entry = entries[threadId] ?: return
        if (entry.model !== model) return
        setIdleHandler(model, null)
        entries.remove(threadId)
        recent.remove(threadId)
    }

    /** The models kept for recent threads go as they would have when their last owner left */
    fun forgetRecent() {
        val threadIds = recent.toList()
        recent.clear()
        threadIds.forEach { threadId -> entries[threadId]?.let { leave(threadId, it) } }
    }

    // An unowned model that isn't kept: destroyed, or once its background work ends
    private fun leave(threadId: String, entry: Entry<Model>) {
        if (entry.ownerCount != 0) return
        if (shouldRetain(entry.model)) {
            setIdleHandler(entry.model) { destroyIfUnused(threadId, entry) }
        } else {
            destroyIfUnused(threadId, entry)
        }
    }

    private fun destroyIfUnused(threadId: String, entry: Entry<Model>) {
        if (entries[threadId] !== entry || entry.ownerCount != 0 ||
            shouldRetain(entry.model) || threadId in recent
        ) {
            return
        }
        setIdleHandler(entry.model, null)
        entries.remove(threadId)
        destroy(entry.model)
    }
}
