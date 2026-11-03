package org.mytonwallet.app_air.uiagent.search

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.sortAgentThreads
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListResponse
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore

const val MAX_RECENT_AGENT_THREADS = 9

data class AgentThreadSearchResult(
    val thread: AgentV2ThreadSummary,
    val title: String,
    val subtitle: String,
    val icon: String? = thread.icon
)

object AgentSearchSuggestions : WalletCore.EventObserver, WalletCore.UpdatesObserver {
    private var observingRecent = false
    private var recentAccountId: String? = null
    private val client by lazy { LiveAgentV2Client() }
    private val threadSearch by lazy {
        AgentThreadSearchProvider(
            hasConsent = { client.consent() },
            loadThreads = { cursor, limit, query -> client.listThreads(cursor, limit, query) },
            fallbackTitle = { LocaleController.getString("New Chat") }
        )
    }

    fun cachedRecent(): List<AgentThreadSearchResult> {
        observeRecent()
        return threadSearch.cachedRecent.orEmpty()
    }

    suspend fun recent(): List<AgentThreadSearchResult> {
        observeRecent()
        return threadSearch.search()
    }

    fun observeRecent() {
        if (observingRecent && recentAccountId != AccountStore.activeAccountId) resetRecent()
        recentAccountId = AccountStore.activeAccountId
        observingRecent = true
        WalletCore.unregisterObserver(this)
        WalletCore.registerObserver(this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
    }

    private fun resetRecent() {
        threadSearch.resetRecent()
        if (!observingRecent) return
        observingRecent = false
        recentAccountId = null
        WalletCore.unregisterObserver(this)
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp,
            WalletEvent.AccountsReset -> resetRecent()

            is WalletEvent.AgentThreadDeleted -> threadSearch.removeRecent(walletEvent.threadId)

            else -> Unit
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        if ((update as? ApiUpdate.ApiUpdateAgentV2)?.update is AgentV2Update.RuntimeReady) {
            resetRecent()
        }
    }

    suspend fun search(query: String): List<AgentThreadSearchResult> = threadSearch.search(query)

    suspend fun suggested(): List<AgentHint> = runAgentSearchRequest {
        val response = client.hints(LocaleController.activeLanguage.langCode)
        response.items.mapNotNull { hint ->
            localizedAgentV2Hint(hint.id)?.copy(catalogVersion = response.catalogVersion)
        }
    }.orEmpty()
}

internal class AgentThreadSearchProvider(
    private val hasConsent: suspend () -> Boolean,
    private val loadThreads: suspend (String?, Int, String?) -> AgentV2ThreadListResponse,
    private val fallbackTitle: () -> String,
    private val debounceMillis: Long = SEARCH_DEBOUNCE_MS
) {
    var cachedRecent: List<AgentThreadSearchResult>? = null
        private set
    private var recentContext = Any()

    fun resetRecent() {
        recentContext = Any()
        cachedRecent = null
    }

    fun removeRecent(threadId: String) {
        recentContext = Any()
        cachedRecent = cachedRecent?.filterNot { it.thread.id == threadId }
    }

    suspend fun search(query: String? = null): List<AgentThreadSearchResult> {
        val context = recentContext
        val isRecent = query.isNullOrBlank()
        if (!isRecent) delay(debounceMillis)
        val result = runAgentSearchRequest {
            if (!hasConsent()) return@runAgentSearchRequest emptyList()
            val page = loadThreads(null, THREAD_PAGE_SIZE, query?.takeIf { it.isNotBlank() })
            val distinctThreads = page.threads.distinctBy { it.thread.id }
            val orderedThreads = if (isRecent) {
                sortAgentThreads(distinctThreads).take(MAX_RECENT_AGENT_THREADS)
            } else {
                distinctThreads.sortedByDescending { parseThreadActivity(it.thread.lastActivityAt) }
            }
            orderedThreads
                .map { item ->
                    val thread = item.thread
                    AgentThreadSearchResult(
                        thread = thread,
                        title = resolveAgentThreadTitle(thread, newChatTitle = fallbackTitle()),
                        subtitle = item.preview.orEmpty().trim().replace(whitespaceRegex, " "),
                        icon = thread.icon
                    )
                }
        }
        if (recentContext !== context) throw CancellationException()
        if (isRecent && result != null) cachedRecent = result
        return result ?: if (isRecent) cachedRecent.orEmpty() else emptyList()
    }
}

private const val THREAD_PAGE_SIZE = 30
private const val SEARCH_DEBOUNCE_MS = 250L
private val whitespaceRegex = Regex("\\s+")

private fun parseThreadActivity(value: String?): Long =
    value?.let(::parseAgentV2Timestamp)?.time ?: Long.MIN_VALUE

private suspend fun <T> runAgentSearchRequest(block: suspend () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (_: Exception) {
    null
}
