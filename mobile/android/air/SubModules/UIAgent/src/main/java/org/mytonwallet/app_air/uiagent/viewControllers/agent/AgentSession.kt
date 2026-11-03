package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.agentV2.AgentV2ChatActivityGroup
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadActivityTracker
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

object AgentSession {
    internal val chatActivityGroup = AgentV2ChatActivityGroup()
    private val scrollPositions = mutableMapOf<String, AgentVM.ScrollPosition>()
    private val sessions = AgentThreadSessions<AgentVM>(
        shouldRetain = { it.shouldRetainSession },
        setIdleHandler = { model, handler -> model.onSessionIdle = handler },
        destroy = { model ->
            val threadId = model.currentThread.id
            model.scrollPosition?.let { scrollPositions[threadId] = it }
            model.onDestroy()
        }
    )

    fun acquire(thread: AgentV2ThreadSummary): AgentVM = acquire(thread) {
        AgentVM(scrollPositions[thread.id], initialThread = thread)
    }

    internal fun acquire(thread: AgentV2ThreadSummary, create: () -> AgentVM): AgentVM =
        sessions.acquire(thread.id, create)

    internal fun acquireOpening(
        thread: AgentV2ThreadSummary,
        initialMessages: List<AgentMessage>,
        entryPoint: AgentV2EntryPoint
    ): AgentVM = sessions.acquire(thread.id) {
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

internal class AgentThreadSessions<Model : Any>(
    private val shouldRetain: (Model) -> Boolean,
    private val setIdleHandler: (Model, (() -> Unit)?) -> Unit,
    private val destroy: (Model) -> Unit
) {
    private class Entry<Model>(val model: Model, var ownerCount: Int = 1)

    private val entries = mutableMapOf<String, Entry<Model>>()

    fun acquire(threadId: String, create: () -> Model): Model {
        val entry = entries[threadId]
        if (entry != null) {
            entry.ownerCount++
            setIdleHandler(entry.model, null)
            return entry.model
        }
        return create().also { entries[threadId] = Entry(it) }
    }

    fun getModels(): List<Model> = entries.values.map { it.model }

    fun release(threadId: String, model: Model) {
        val entry = entries[threadId] ?: return
        if (entry.model !== model || entry.ownerCount == 0) return
        entry.ownerCount--
        if (entry.ownerCount != 0) return
        if (shouldRetain(model)) {
            setIdleHandler(model) { destroyIfUnused(threadId, entry) }
        } else {
            destroyIfUnused(threadId, entry)
        }
    }

    /** Later releases do nothing; the caller stops [model]. */
    fun evict(threadId: String, model: Model) {
        val entry = entries[threadId] ?: return
        if (entry.model !== model) return
        setIdleHandler(model, null)
        entries.remove(threadId)
    }

    private fun destroyIfUnused(threadId: String, entry: Entry<Model>) {
        if (entries[threadId] !== entry || entry.ownerCount != 0 ||
            shouldRetain(entry.model)
        ) {
            return
        }
        setIdleHandler(entry.model, null)
        entries.remove(threadId)
        destroy(entry.model)
    }
}
