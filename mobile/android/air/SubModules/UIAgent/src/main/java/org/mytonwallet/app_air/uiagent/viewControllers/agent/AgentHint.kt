package org.mytonwallet.app_air.uiagent.viewControllers.agent

data class AgentHint(
    val id: String,
    val title: String,
    val subtitle: String,
    val prompt: String,
    val catalogVersion: String? = null
)
