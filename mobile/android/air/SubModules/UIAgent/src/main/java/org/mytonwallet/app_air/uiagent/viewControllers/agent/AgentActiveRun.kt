package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.agentV2.AgentV2AuthorityBinding

internal class AgentActiveRun(
    val inputPresentationId: String,
    val authority: AgentV2AuthorityBinding,
    val editedMessage: AgentMessage? = null,
    val editFallbackMessages: List<AgentMessage>? = null,
    val regenerationTargetId: String? = null
) {
    var isEditAdmitted = false
    var assistantPresentationId: String? = null
    var hasStartedAssistant = false
    var hasFailed = false
    var failureCode: String? = null
    var shouldResyncThread = false
    var clientRunId: String? = null
        private set
    var runId: String? = null
        private set

    fun bind(clientRunId: String, runId: String?): Boolean {
        val currentClientRunId = this.clientRunId
        if (currentClientRunId != null && currentClientRunId != clientRunId) return false
        val currentRunId = this.runId
        if (currentRunId != null && runId != null && currentRunId != runId) return false
        this.clientRunId = clientRunId
        if (runId != null) this.runId = runId
        return true
    }

    fun matches(clientRunId: String, runId: String): Boolean =
        this.clientRunId == clientRunId && this.runId == runId
}
