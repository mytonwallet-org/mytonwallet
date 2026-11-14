package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import java.util.Date
import java.util.Locale
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsIconView
import org.mytonwallet.app_air.uiagent.viewControllers.news.formatAgentNewsUnreadCount
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem

@SuppressLint("ViewConstructor")
internal class AgentNewsCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val icon = AgentNewsIconView(context)
    val rowView = AgentThreadRowView(context, icon).apply {
        id = UIComponentsR.id.agent_news_row
    }
    var onTap: (() -> Unit)? = null

    init {
        addView(rowView, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(rowView)
            toEnd(rowView)
            toTop(rowView)
            toBottom(rowView)
        }
        rowView.setOnClickListener { onTap?.invoke() }
        rowView.isLongClickable = false
        updateTheme()
    }

    /**
     * Shows the latest news, or [latestDigest] when the Digests view shows it: its first headline with its picture, the
     * digest's time and the count of the new digests
     */
    fun configure(
        latest: AgentV2NewsFeedItem?,
        latestDigest: AgentV2NewsFeedDigest?,
        unreadCount: Int,
        is24HourFormat: Boolean
    ) {
        val headline = latestDigest?.top?.firstOrNull()
        val deliveredAt = latestDigest?.deliveredAt ?: latest?.deliveredAt
        val time = deliveredAt?.let {
            AgentThreadDateFormatting.formatRowTimestamp(
                parseAgentV2Timestamp(it) ?: Date(0),
                Date(),
                shouldShowDateWhenNotToday = true,
                is24HourFormat = is24HourFormat,
                locale = Locale.forLanguageTag(LocaleController.activeLanguage.langCode)
            )
        }.orEmpty()
        val preview = if (latestDigest != null) headline?.headline else latest?.headline
        val imageUrl = if (latestDigest != null) headline?.imageUrl else latest?.imageUrl
        rowView.setTexts(
            title = LocaleController.getString("News"),
            preview = preview ?: LocaleController.getString("Crypto Market News"),
            time = time,
            previewImageUrl = imageUrl?.takeIf { it.isNotBlank() }
        )
        rowView.isUnread = unreadCount > 0
        rowView.unreadCountText = formatAgentNewsUnreadCount(unreadCount)
        val unreadKey = if (latestDigest != null) {
            "\$agent_news_unread_digests_count"
        } else {
            "\$agent_news_unread_count"
        }
        rowView.contentDescription = listOfNotNull(
            LocaleController.getString("News"),
            rowView.previewText,
            time.takeIf { it.isNotEmpty() },
            LocaleController.getPlural(unreadCount, unreadKey).takeIf { unreadCount > 0 }
        ).joinToString(", ")
        updateTheme()
    }

    override fun updateTheme() {
        rowView.updateTheme()
        icon.updateTheme()
    }
}
