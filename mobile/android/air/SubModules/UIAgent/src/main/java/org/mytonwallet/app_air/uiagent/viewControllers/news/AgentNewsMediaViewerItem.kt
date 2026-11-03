package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.text.SpannableStringBuilder
import android.text.Spanned
import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentNewsPostBodyText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentNewsMenuItems
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MEDIA_VIEWER_CAPTION_CODE_COLOR
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MEDIA_VIEWER_CAPTION_LINK_COLOR
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerItem
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.formatMediaViewerDate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

internal fun agentNewsMediaViewerItem(
    window: WWindow,
    url: String,
    news: AgentV2ThreadNewsCard
): MediaViewerItem {
    val openLink: (String) -> Unit = { AgentNewsSourceLinks.open(window, window, it) }
    return MediaViewerItem(
        url = url,
        title = AgentNewsPostCell.sourceName(news),
        subtitle = {
            parseAgentV2Timestamp(news.publishedAt)?.let { date ->
                formatMediaViewerDate(
                    date,
                    Date(),
                    formatTime = { formatAgentChatTime(window, it) },
                    formatDay = { day, withYear -> AgentNewsTextBlock.formatDay(day, withYear) }
                )
            }
        },
        caption = { textSize -> buildAgentPhotoCaption(news, textSize, openLink) },
        accessibilityLabel = news.headline,
        menuItems = { host ->
            buildAgentNewsMenuItems(host, news, onOpenSource = openLink, onCopied = null)
        }
    )
}

private fun buildAgentPhotoCaption(
    news: AgentV2ThreadNewsCard,
    textSize: Float,
    onUrlClick: (String) -> Unit
): CharSequence {
    val caption = SpannableStringBuilder(news.headline)
    caption.setSpan(
        WTypefaceSpan(WFont.Medium),
        0,
        caption.length,
        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
    )
    agentNewsPostBodyText(news)?.let { body ->
        if (caption.isNotEmpty()) caption.append('\n')
        caption.append(
            MarkdownParser.parse(
                body,
                codeColor = MEDIA_VIEWER_CAPTION_CODE_COLOR,
                linkColor = MEDIA_VIEWER_CAPTION_LINK_COLOR,
                onUrlClick = onUrlClick,
                detectsUrls = false,
                textSize = textSize
            )
        )
    }
    return caption
}
