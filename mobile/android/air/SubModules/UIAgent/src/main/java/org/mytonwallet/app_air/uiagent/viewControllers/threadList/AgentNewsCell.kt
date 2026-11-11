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

    fun configure(latest: AgentV2NewsFeedItem?, unreadCount: Int, is24HourFormat: Boolean) {
        val time = latest?.let {
            AgentThreadDateFormatting.formatRowTimestamp(
                parseAgentV2Timestamp(it.deliveredAt) ?: Date(0),
                Date(),
                shouldShowDateWhenNotToday = true,
                is24HourFormat = is24HourFormat,
                locale = Locale.forLanguageTag(LocaleController.activeLanguage.langCode)
            )
        }.orEmpty()
        rowView.setTexts(
            title = LocaleController.getString("News"),
            preview = latest?.headline ?: LocaleController.getString("Crypto Market News"),
            time = time,
            previewImageUrl = latest?.imageUrl?.takeIf { it.isNotBlank() }
        )
        rowView.isUnread = unreadCount > 0
        rowView.unreadCountText = formatAgentNewsUnreadCount(unreadCount)
        rowView.contentDescription = listOfNotNull(
            LocaleController.getString("News"),
            rowView.previewText,
            time.takeIf { it.isNotEmpty() },
            LocaleController.getPlural(unreadCount, "\$agent_news_unread_count")
                .takeIf { unreadCount > 0 }
        ).joinToString(", ")
        updateTheme()
    }

    override fun updateTheme() {
        rowView.updateTheme()
        icon.updateTheme()
    }
}
