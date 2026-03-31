package org.mytonwallet.app_air.uiagent.processors

import org.json.JSONObject

data class AgentUserAddress(
    val name: String,
    val addresses: List<String>,  // e.g. ["ton:UQ...", "solana:addr", "tron:addr"]
    val accountType: String? = null,  // "mnemonic", "hardware", "view"
    val isActive: Boolean = false
)

sealed class AgentStreamEvent {
    data class Metadata(val type: String, val streaming: Boolean) : AgentStreamEvent()
    data class Chunk(val text: String) : AgentStreamEvent()
    data class Results(val results: List<AgentResult>) : AgentStreamEvent()
    data class Error(val error: String, val message: String) : AgentStreamEvent()
}

data class AgentResultDeeplink(
    val title: String,
    val url: String
)

data class AgentResult(
    val type: String,
    val message: String? = null,
    val deeplinks: List<AgentResultDeeplink> = emptyList(),
    val raw: JSONObject
)

data class AgentHint(
    val id: String,
    val title: String,
    val subtitle: String,
    val prompt: String
)

interface AgentProcessor {
    suspend fun streamMessage(
        userId: String,
        message: String,
        userAddresses: List<AgentUserAddress>,
        savedAddresses: List<AgentUserAddress>,
        onEvent: (AgentStreamEvent) -> Unit,
        onDone: () -> Unit,
        onError: (Exception) -> Unit
    )

    suspend fun loadHints(langCode: String?): List<AgentHint> = emptyList()

    fun resetClientId() {}
}
