package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.view.View
import java.net.URI
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsSourceLinks
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.helpers.ShareHelpers
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers

internal fun agentNewsSourceUrl(post: AgentNewsPostContent): String? =
    post.sources?.firstOrNull()?.url?.takeIf(AgentNewsSourceLinks::isOpenable)

/** A source the menu's Sources lists: its name, or its site without "www.", and its link */
internal data class AgentNewsMenuSource(val name: String, val url: String)

/** The sources the app can open, in the API's order, each once */
internal fun agentNewsMenuSources(post: AgentNewsPostContent): List<AgentNewsMenuSource> {
    val names = mutableSetOf<String>()
    return post.sources.orEmpty().mapNotNull { source ->
        if (!AgentNewsSourceLinks.isOpenable(source.url)) return@mapNotNull null
        val name = source.name?.trim()?.takeIf { it.isNotEmpty() }
            ?: runCatching { URI(source.url).host }.getOrNull()
                ?.let { if (it.startsWith("www.", ignoreCase = true)) it.drop(4) else it }
                ?.takeIf { it.isNotEmpty() }
        if (name == null || !names.add(name.lowercase())) return@mapNotNull null
        AgentNewsMenuSource(name, source.url)
    }
}

internal fun agentNewsCopyText(post: AgentNewsPostContent): String = listOfNotNull(
    post.headline,
    post.body?.replace("**", "") ?: post.digestText,
    post.sources?.firstOrNull()?.url
).joinToString("\n\n")

internal fun buildAgentNewsShareText(post: AgentNewsPostContent): String? {
    val eventId = post.eventId?.takeIf { it > 0 } ?: return null
    val link = ExplorerHelpers.buildAgentNewsShareUrl(
        eventId,
        post.locale ?: LocaleController.activeLanguage.langCode
    )
    return "${post.headline}\n$link"
}

/** Sources opens the list of the post's sources, each opening its link; [view] plays Copy's haptic */
internal fun buildAgentNewsMenuItems(
    view: View,
    post: AgentNewsPostContent,
    onOpenSource: ((url: String) -> Unit)?,
    onCopied: (() -> Unit)?
): List<WMenuPopup.Item> = buildList {
    val context = view.context
    val sources = agentNewsMenuSources(post)
    if (sources.isNotEmpty()) {
        val sourceItems = sources.map { source ->
            WMenuPopup.Item(null, source.name) { onOpenSource?.invoke(source.url) }
        }
        add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    WMenuPopup.Item.Config.Icon(
                        R.drawable.ic_link,
                        tintColor = WColor.SecondaryText
                    ),
                    LocaleController.getString("\$agent_news_sources"),
                    subItems = sourceItems
                )
            )
        )
    }
    add(
        WMenuPopup.Item(R.drawable.ic_copy_30, LocaleController.getString("Copy")) {
            if (ClipboardHelpers.copyToClipboard(context, "Message", agentNewsCopyText(post))) {
                Haptics.play(view, HapticType.LIGHT_TAP)
                onCopied?.invoke()
            }
        }
    )
    val shareText = buildAgentNewsShareText(post)
    if (shareText != null) {
        add(
            WMenuPopup.Item(R.drawable.ic_share, LocaleController.getString("Share")) {
                ShareHelpers.shareText(context, shareText, post.headline)
            }
        )
    }
}
