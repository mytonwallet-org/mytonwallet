package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.view.View
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentNewsPostBodyText
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsSourceLinks
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.helpers.ShareHelpers
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

internal fun agentNewsSourceUrl(news: AgentV2ThreadNewsCard): String? =
    news.sources?.firstOrNull()?.url?.takeIf(AgentNewsSourceLinks::isOpenable)

internal fun agentNewsCopyText(news: AgentV2ThreadNewsCard): String = listOfNotNull(
    news.headline,
    agentNewsPostBodyText(news)?.replace("**", ""),
    news.sources?.firstOrNull()?.url
).joinToString("\n\n")

/** [view] plays Copy's haptic. */
internal fun buildAgentNewsMenuItems(
    view: View,
    news: AgentV2ThreadNewsCard,
    onOpenSource: ((url: String) -> Unit)?,
    onCopied: (() -> Unit)?
): List<WMenuPopup.Item> = buildList {
    val context = view.context
    agentNewsSourceUrl(news)?.let { url ->
        val title = LocaleController.getString("\$agent_news_open_source")
        add(WMenuPopup.Item(R.drawable.ic_link, title) { onOpenSource?.invoke(url) })
    }
    add(
        WMenuPopup.Item(R.drawable.ic_copy_30, LocaleController.getString("Copy")) {
            if (ClipboardHelpers.copyToClipboard(context, "Message", agentNewsCopyText(news))) {
                Haptics.play(view, HapticType.LIGHT_TAP)
                onCopied?.invoke()
            }
        }
    )
    add(
        WMenuPopup.Item(R.drawable.ic_share, LocaleController.getString("Share")) {
            val title = LocaleController.getString("Share")
            ShareHelpers.shareText(context, agentNewsCopyText(news), title)
        }
    )
}
