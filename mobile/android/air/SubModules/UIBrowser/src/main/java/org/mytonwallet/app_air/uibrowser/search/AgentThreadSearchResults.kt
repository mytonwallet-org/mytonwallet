package org.mytonwallet.app_air.uibrowser.search

import org.mytonwallet.app_air.uiagent.search.AgentThreadSearchResult
import org.mytonwallet.app_air.uiagent.search.MAX_RECENT_AGENT_THREADS

internal fun selectVisibleAgentThreads(
    resultKeyword: String?,
    query: String,
    threads: List<AgentThreadSearchResult>
): List<AgentThreadSearchResult> = when {
    resultKeyword != query -> emptyList()
    query.isEmpty() -> threads.take(MAX_RECENT_AGENT_THREADS)
    else -> threads
}
