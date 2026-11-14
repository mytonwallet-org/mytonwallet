package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.mytonwallet.app_air.uiagent.viewControllers.threadList.agentThreadActivityDate
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSupport
import org.mytonwallet.app_air.walletcore.stores.AccountStore

/** Contact Support, which ends the starter suggestions; the client offers it, never the server's catalog */
internal const val AGENT_SUPPORT_HINT_ID = "client.supportRequest"

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

internal fun makeAgentSupportHint(): AgentHint {
    val title = LocaleController.getString("\$agent_support_contact")
    return AgentHint(id = AGENT_SUPPORT_HINT_ID, title = title, subtitle = title, prompt = title)
}

/** The most recently active chat that support has, which Contact Support opens in place of a new chat */
internal fun findAgentSupportThread(items: List<AgentV2ThreadListItem>): AgentV2ThreadSummary? =
    items
        .map { it.thread }
        .filter { getAgentSupportLabelStyle(it.support) != null }
        .maxByOrNull(::agentThreadActivityDate)

/**
 * Asks before a chat goes to a support operator, who sees the wallet's addresses only with the user's consent and a
 * wallet. Call runs [onConfirm], which sends nothing once support can no longer be called; Cancel sends nothing.
 */
internal class AgentSupportRequestConfirmation(
    hasConsent: Boolean,
    private val onConfirm: () -> Unit
) {
    val text: String = LocaleController.getString(
        if (hasConsent && AccountStore.activeAccountId != null) {
            "\$agent_support_confirm_text"
        } else {
            "\$agent_support_confirm_text_no_wallet"
        }
    )

    fun present(viewController: WViewController) =
        present { title, text, action, onAction, cancel, onCancel ->
            viewController.showAlert(
                title,
                text,
                button = action,
                buttonPressed = onAction,
                secondaryButton = cancel,
                secondaryButtonPressed = onCancel
            )
        }

    /** Shows the sheet through [showAlert]: Call confirms, and Cancel only closes the sheet */
    internal fun present(
        showAlert: (
            title: String,
            text: String,
            action: String,
            onAction: () -> Unit,
            cancel: String,
            onCancel: (() -> Unit)?
        ) -> Unit
    ) {
        showAlert(
            LocaleController.getString("\$agent_support_confirm_title"),
            text,
            LocaleController.getString("\$agent_support_confirm_action"),
            onConfirm,
            LocaleController.getString("Cancel"),
            null
        )
    }
}

/** The source each of the chat's support entry points sends, by the id UI automation finds the entry point by */
internal fun getAgentSupportRequestSource(entryPointId: Int): AgentV2SupportRequestSource =
    when (entryPointId) {
        UIComponentsR.id.agent_support_button -> AgentV2SupportRequestSource.HEADER
        UIComponentsR.id.agent_support_hint -> AgentV2SupportRequestSource.STARTER_HINT
        else -> error("Unknown support entry point $entryPointId")
    }
