package org.mytonwallet.app_air.uiagent.agentV2

import java.util.Date
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunActivityEvent

internal data class AgentV2ConsentCopy(
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

/** The message a support request sends, which the chat keeps as the user's */
internal fun getAgentSupportRequestText(): String =
    LocaleController.getString("\$agent_support_request_message")

internal fun getAgentAnalyzingRequestText(): String =
    LocaleController.getString("\$agent_activity_analyzing_request")

internal fun getAgentWritingAnswerText(): String =
    LocaleController.getString("\$agent_activity_writing")

/** The step a run reports; null for a step this version doesn't know */
internal fun getAgentV2RunActivityText(event: AgentV2RunActivityEvent): String? {
    val key = when (event.code) {
        "request.planning" -> "planning"
        "web.searching" -> "web_searching"
        "web.reading_sources" -> "web_reading_sources"
        "help.searching" -> "help_searching"
        "data.reading_market" -> "market_data"
        "analysis.checking_freshness" -> "checking_freshness"
        "analysis.computing" -> "computing"
        "answer.writing" -> "writing"
        else -> return null
    }
    if (event.status != "completed") return LocaleController.getString("\$agent_activity_$key")
    if (event.code != "web.reading_sources") {
        return LocaleController.getString("\$agent_activity_${key}_completed")
    }
    val sourceCount = event.detail?.takeIf { it.kind == "source_count" }?.count
        ?: return LocaleController.getString(
            "\$agent_activity_web_reading_sources_completed_generic"
        )
    return LocaleController.getStringWithKeyValues(
        "\$agent_activity_web_reading_sources_completed",
        listOf("%count%" to sourceCount.toString())
    )
}

internal fun agentActionUnavailableText(reason: String?): String {
    val key = when (reason) {
        "viewOnlyWallet" -> "\$action_not_available_view_mode"
        else -> "This action is no longer available."
    }
    return LocaleController.getString(key)
}

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

internal fun agentV2ErrorText(code: String?, resetAt: Date?): String {
    if (code == "user_quota_exhausted" && resetAt != null && resetAt.after(Date())) {
        return LocaleController.getStringWithKeyValues(
            "\$agent_daily_limit_resets_at",
            listOf(
                "%time%" to formatAgentChatTime(
                    ApplicationContextHolder.applicationContext,
                    resetAt
                )
            )
        )
    }
    return agentV2ErrorText(code)
}

internal fun agentV2ErrorText(code: String?): String = LocaleController.getString(
    when (code) {
        "invalid_event" -> "\$agent_error_invalid_response"

        "client_update_required" -> "\$agent_error_update_required"

        "network_error" -> "\$agent_connection_lost"

        "user_quota_exhausted" -> "\$agent_daily_limit_reached"

        "support_escalation_rate_limited" -> "\$agent_support_rate_limited"

        "rate_limited", "agent_capacity_exhausted", "run_budget_exceeded", "output_limit_reached",
        "context_too_large_retryable", "device_token_rate_limited" -> "\$agent_error_limit"

        "provider_unavailable", "provider_timeout" -> "\$agent_capacity_limit_unknown"

        "device_token_missing", "device_token_invalid", "device_token_expired",
        "profile_id_invalid", "profile_deleted" -> "\$agent_error_session"

        "action_unsupported", "tool_unsupported" -> "\$agent_error_tool"

        "recording_too_large" -> "\$agent_error_recording_too_large"

        "audio_unreadable" -> "\$agent_error_audio_unreadable"

        "transcription_unavailable" -> "\$agent_error_transcription_unavailable"

        else -> "\$agent_error_generic"
    }
)

/** What TalkBack announces for a recording that produced no transcript; on screen its circle turns red */
internal fun getAgentDictationFailureText(failure: AgentDictationFailure): String = when (failure) {
    AgentDictationFailure.TooShort -> LocaleController.getString("\$agent_dictation_too_short")

    AgentDictationFailure.NoSpeech -> LocaleController.getString("\$agent_dictation_no_speech")

    AgentDictationFailure.MicrophoneDenied ->
        LocaleController.getString("\$agent_dictation_microphone_denied_device")

    is AgentDictationFailure.Error -> agentV2ErrorText(failure.code)
}
