package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.agentV2.hasPost
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/**
 * The SDK's cached histories of the latest chats, held in memory so that a chat opens with its history in the first
 * frame. The list reads them ahead as it loads its first page, and a chat's loaded history replaces its copy. As in the
 * SDK, it holds at most [HISTORY_LIMIT] chats and [MESSAGE_LIMIT] latest messages of each.
 *
 * A wallet reset clears the copies. The store observes it as it is used, and a new bridge, which starts without the
 * previous bridge's observers and so may have missed a reset, clears them too.
 */
internal class AgentCachedHistories(
    private val scope: CoroutineScope,
    private val getBridge: () -> Any? = { WalletCore.bridge },
    private val readCachedMessages: suspend (String) -> AgentV2CachedMessages?
) : WalletCore.EventObserver {
    // From the least to the most recently stored
    private val histories = LinkedHashMap<String, AgentV2CachedMessages>()

    // The summary each chat had in the list when its copy was read or loaded
    private val readVersions = mutableMapOf<String, ThreadVersion>()

    // The prefetch that owns each chat's started or queued read; any change of the chat's copy releases it
    private val readOwners = mutableMapOf<String, Any>()
    private var readJob: Job? = null
    private var observedBridge: Any? = null

    private data class ThreadVersion(
        val revision: Int,
        val updatedAt: String?,
        val messageCount: Int
    )

    fun get(threadId: String): AgentV2CachedMessages? {
        observeWalletEvents()
        return histories[threadId]
    }

    /**
     * Reads one by one the SDK's copies of the listed chats with messages whose summary changed since their last read.
     * Each read moves the chat to the front of the SDK's cache and of this store, so the top chat is read last and
     * leaves first.
     */
    fun prefetch(threads: List<AgentV2ThreadSummary>) {
        observeWalletEvents()
        val targets = threads.filter { it.messageCount > 0 && !it.hasPost }
            .take(HISTORY_LIMIT)
            .asReversed()
        val owner = Any()
        readJob?.cancel()
        readOwners.clear()
        targets.forEach { readOwners[it.id] = owner }
        readJob = scope.launch {
            for (thread in targets) {
                val version = thread.version
                if (readOwners[thread.id] !== owner) continue
                if (readVersions[thread.id] == version) {
                    readOwners.remove(thread.id)
                    continue
                }
                val cached = try {
                    readCachedMessages(thread.id)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    null
                }
                currentCoroutineContext().ensureActive()
                if (readOwners[thread.id] !== owner) continue
                readOwners.remove(thread.id)
                if (cached == null || cached.thread.id != thread.id) {
                    histories.remove(thread.id)
                } else {
                    store(cached)
                }
                readVersions[thread.id] = version
            }
        }
    }

    /** Replaces the chat's copy with its loaded latest page */
    fun storeLoadedPage(
        thread: AgentV2ThreadSummary,
        messages: List<AgentV2PersistedMessage>,
        hasOlder: Boolean
    ) {
        observeWalletEvents()
        readOwners.remove(thread.id)
        readVersions[thread.id] = thread.version
        if (messages.isEmpty() || thread.hasPost) {
            histories.remove(thread.id)
            return
        }
        store(
            AgentV2CachedMessages(
                thread,
                messages.takeLast(MESSAGE_LIMIT),
                hasOlder || messages.size > MESSAGE_LIMIT
            )
        )
    }

    fun remove(threadId: String) {
        readOwners.remove(threadId)
        histories.remove(threadId)
        readVersions.remove(threadId)
    }

    // A wallet reset starts another Agent identity, whose chats these copies are not
    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent == WalletEvent.AccountsReset) clear()
    }

    fun clear() {
        readJob?.cancel()
        readJob = null
        readOwners.clear()
        histories.clear()
        readVersions.clear()
    }

    private fun observeWalletEvents() {
        val bridge = getBridge()
        if (bridge !== observedBridge) clear()
        observedBridge = bridge
        WalletCore.unregisterObserver(this)
        WalletCore.registerObserver(this)
    }

    private fun store(cached: AgentV2CachedMessages) {
        histories.remove(cached.thread.id)
        histories[cached.thread.id] = cached
        if (histories.size <= HISTORY_LIMIT) return
        // An evicted chat is read again by the next prefetch, even though its summary did not change
        val evicted = histories.keys.first()
        histories.remove(evicted)
        readVersions.remove(evicted)
    }

    private val AgentV2ThreadSummary.version
        get() = ThreadVersion(revision, updatedAt, messageCount)

    private companion object {
        const val HISTORY_LIMIT = 10
        const val MESSAGE_LIMIT = 50
    }
}
