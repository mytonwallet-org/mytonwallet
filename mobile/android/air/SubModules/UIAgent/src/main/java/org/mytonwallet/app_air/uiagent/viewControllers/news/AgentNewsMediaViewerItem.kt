package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentNewsMenuItems
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MEDIA_VIEWER_CAPTION_CODE_COLOR
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MEDIA_VIEWER_CAPTION_LINK_COLOR
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerItem
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.formatMediaViewerDate
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline

internal fun agentNewsMediaViewerItem(
    window: WWindow,
    url: String,
    post: AgentNewsPostContent
): MediaViewerItem {
    val openLink: (String) -> Unit = { AgentNewsSourceLinks.open(window, window, it) }
    return MediaViewerItem(
        url = url,
        date = {
            parseAgentV2Timestamp(post.publishedAt)?.let { formatAgentNewsPictureDate(window, it) }
        },
        caption = { textSize -> buildAgentPhotoCaption(post, textSize, openLink) },
        accessibilityLabel = post.headline,
        menuItems = { host ->
            buildAgentNewsMenuItems(host, post, onOpenSource = openLink, onCopied = null)
        }
    )
}

/**
 * A digest's headline picture, dated when the digest came and captioned with the headline alone, without the menu of a
 * post
 */
internal fun agentNewsDigestMediaViewerItem(
    context: Context,
    headline: AgentV2NewsDigestHeadline,
    date: Date?,
    // Styles the caption's text, which unit tests read without Android's spans
    styleCaption: (text: String) -> CharSequence = ::buildAgentPhotoCaption
): MediaViewerItem = MediaViewerItem(
    url = headline.imageUrl!!,
    date = { date?.let { formatAgentNewsPictureDate(context, it) } },
    caption = { styleCaption(headline.headline) },
    accessibilityLabel = headline.headline
)

private fun formatAgentNewsPictureDate(context: Context, date: Date): String =
    formatMediaViewerDate(
        date,
        Date(),
        formatTime = { formatAgentChatTime(context, it) },
        formatDay = { day, withYear -> AgentNewsTextBlock.formatDay(day, withYear) }
    )

private fun buildAgentPhotoCaption(headline: String): SpannableStringBuilder {
    val caption = SpannableStringBuilder(headline)
    caption.setSpan(
        WTypefaceSpan(WFont.Medium),
        0,
        caption.length,
        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
    )
    return caption
}

private fun buildAgentPhotoCaption(
    post: AgentNewsPostContent,
    textSize: Float,
    onUrlClick: (String) -> Unit
): CharSequence {
    val caption = buildAgentPhotoCaption(post.headline)
    post.body?.let { body ->
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
