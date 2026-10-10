package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation

internal class AgentActionAvailability(
    private val loadPresentation: suspend (String, String) -> AgentV2ActionPresentation
) {
    private val pendingChecks = mutableSetOf<Job>()
    var context = Any()
        private set

    suspend fun filterAvailable(
        messageId: String,
        actions: List<AgentV2Action>
    ): List<AgentV2Action> {
        val expectedContext = context
        val available = actions.filter { action ->
            context === expectedContext &&
                (action.kind != "send" || isSendActive(messageId, action.id))
        }
        return available.takeIf { context === expectedContext }.orEmpty()
    }

    private suspend fun isSendActive(messageId: String, actionId: String): Boolean = try {
        coroutineScope {
            val request = currentCoroutineContext().job
            pendingChecks.add(request)
            try {
                val presentation = loadPresentation(messageId, actionId)
                presentation is AgentV2ActionPresentation.Send && presentation.status == "active"
            } finally {
                pendingChecks.remove(request)
            }
        }
    } catch (e: CancellationException) {
        currentCoroutineContext().ensureActive()
        false
    } catch (_: Throwable) {
        false
    }

    fun invalidate() {
        context = Any()
        pendingChecks.toList().forEach { it.cancel() }
        pendingChecks.clear()
    }
}
