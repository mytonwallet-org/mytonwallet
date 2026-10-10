package org.mytonwallet.app_air.uiagent.agentV2

import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

internal data class AgentV2ConsentCopy(
    val subtitle: String,
    val features: List<String>,
    val disclosureTitle: String,
    val disclosure: String,
    val searchDisclosure: String,
    val allowButton: String
)

internal fun agentV2ConsentCopy(): AgentV2ConsentCopy {
    val appName = ApplicationContextHolder.applicationContext.getString(
        BaseR.string.app_locale_name_key
    )

    fun localized(key: String): String = LocaleController.getStringWithKeyValues(
        key,
        listOf("%app_name%" to appName)
    )

    return AgentV2ConsentCopy(
        subtitle = localized("\$agent_consent_subtitle"),
        features = listOf(
            localized("\$agent_consent_feature_answers"),
            localized("\$agent_consent_feature_actions"),
            localized("\$agent_consent_feature_context")
        ),
        disclosureTitle = localized("Data shared with Agent"),
        disclosure = localized("\$agent_consent_disclosure_text"),
        searchDisclosure = localized("\$agent_consent_search_disclosure_text"),
        allowButton = localized("\$agent_consent_allow_button")
    )
}

internal fun localizedAgentV2Hint(id: String): AgentHint? {
    val prefix = when (id) {
        "agent.capabilities" -> "capabilities"
        "portfolio.performance" -> "portfolio"
        "learn.swap" -> "swap"
        "learn.staking" -> "staking"
        "learn.security" -> "security"
        "receive.tokens" -> "receive"
        else -> return null
    }
    val title = LocaleController.getString("\$agent_hint_${prefix}_title")
    return AgentHint(id = id, title = title, subtitle = title, prompt = title)
}

internal fun agentUnavailableText(): String = LocaleController.getString("\$agent_error_generic")

internal fun agentV2SemanticText(content: Map<String, Any>?): String {
    val code = content?.get("code") as? String
    val key = when {
        (content?.get("schemaVersion") as? Number)?.toInt() != 1 -> "\$agent_error_invalid_response"
        content["kind"] != "notice" -> "\$agent_error_invalid_response"
        code == "agent_unavailable" -> "\$agent_error_generic"
        code == "content_over_budget" -> "\$agent_notice_content_over_budget"
        code == "web_search_no_results" -> "\$agent_notice_web_search_no_results"
        else -> "\$agent_error_invalid_response"
    }
    return LocaleController.getString(key)
}

internal fun agentV2ErrorText(code: String?): String = LocaleController.getString(
    when (code) {
        "invalid_event" -> "\$agent_error_invalid_response"

        "client_update_required" -> "\$agent_error_update_required"

        "network_error" -> "\$agent_connection_interrupted"

        "provider_unavailable", "provider_timeout" -> "\$agent_capacity_limit_unknown"

        "device_token_missing", "device_token_invalid", "device_token_expired",
        "profile_id_invalid", "profile_deleted" -> "\$agent_error_session"

        "action_unsupported", "tool_unsupported" -> "\$agent_error_tool"

        else -> "\$agent_error_generic"
    }
)
