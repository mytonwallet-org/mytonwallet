package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport

/** Once an operator has joined the chat, every answer in it names its author, the agent's before it too */
internal fun List<AgentMessage>.hasSupportOperatorJoined(): Boolean =
    any { it.operator != null || it.supportEvent?.code == "operator_joined" }

/** The line under the chat's title while support has the chat */
internal fun getAgentSupportSubtitle(state: AgentVM.SupportState): String? = when (state) {
    AgentVM.SupportState.Waiting -> LocaleController.getString("\$agent_support_waiting")

    is AgentVM.SupportState.Operator -> state.name?.let { name ->
        LocaleController.getStringWithKeyValues(
            "\$agent_support_with_operator",
            listOf("%name%" to name)
        )
    } ?: LocaleController.getString("\$agent_support_label")

    AgentVM.SupportState.None, AgentVM.SupportState.Closed -> null
}

/** The composer's placeholder, which tells that a message goes to support while support has the chat */
internal fun getAgentComposerPlaceholder(isChatWithSupport: Boolean): String =
    LocaleController.getString(
        if (isChatWithSupport) "\$agent_support_placeholder" else "Ask anything"
    )

/** The label of a chat with support in the chat list: bright while an operator is in it, muted while it waits */
internal enum class AgentSupportLabelStyle {
    ACTIVE,
    MUTED
}

internal fun getAgentSupportLabelStyle(support: AgentV2ThreadSupport?): AgentSupportLabelStyle? =
    when (support?.state) {
        "operator" -> AgentSupportLabelStyle.ACTIVE
        "waiting" -> AgentSupportLabelStyle.MUTED
        else -> null
    }
