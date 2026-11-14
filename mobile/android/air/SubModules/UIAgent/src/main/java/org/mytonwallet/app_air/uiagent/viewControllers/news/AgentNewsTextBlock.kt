package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.text.format.DateFormat
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.view.isGone
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentCodeColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline

/**
 * A news item's text in its bubble, the same in the feed's card and in the discussion's post, so
 * the card lands on the post's text: the headline, the body a blank line under it, and the time at
 * the bubble's trailing corner, where a message shows its time. It spans the bubble's width: the
 * text keeps 16 dp from the bubble's sides and the time 12 dp from its trailing side, the same on
 * iOS and the web.
 * A digest's post lists the digest's headlines under its title, as its card does.
 */
@SuppressLint("ViewConstructor")
internal class AgentNewsTextBlock(context: Context) :
    LinearLayout(context),
    WThemedView {
    private val headline = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Medium)
        setLineHeight(LINE_HEIGHT)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
    }
    private val body = WLabel(context).apply {
        setStyle(TEXT_SIZE)
        setLineHeight(LINE_HEIGHT)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
    }
    private val time = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        setSingleLine()
    }

    /** Reaches the bubble's end past the block's end inset, so its arrows stand as the Discuss strip's */
    val digestHeadlines = AgentNewsDigestHeadlinesView(context).apply { isGone = true }
    private var bodyMarkdown: String? = null
    private var bodyId = ""

    var textCache: AgentMessageTextCache? = null

    val bodyText: CharSequence get() = body.text
    val timeText: CharSequence get() = time.text

    init {
        id = generateViewId()
        orientation = VERTICAL
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(
            headline,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginEnd = (TEXT_INSET - TIME_END_INSET).dp
            }
        )
        addView(
            body,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = HEADLINE_GAP.dp
                marginEnd = (TEXT_INSET - TIME_END_INSET).dp
            }
        )
        addView(
            digestHeadlines,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = DIGEST_HEADLINES_GAP.dp
                marginEnd = -TIME_END_INSET.dp
            }
        )
        addView(
            time,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END
                topMargin = META_GAP.dp
            }
        )
        setVerticalPadding(top = 0, bottom = 0)
        updateTheme()
    }

    /** The space above the headline and below the time */
    fun setVerticalPadding(top: Int, bottom: Int) {
        setPaddingRelative(TEXT_INSET.dp, top, TIME_END_INSET.dp, bottom)
    }

    fun configure(id: String, headlineText: String, body: String?, timeText: String) {
        headline.text = headlineText
        bodyId = id
        bodyMarkdown = body
        renderBody()
        time.text = timeText
    }

    /** A digest's headlines under the title, and the line of the news it leaves out */
    fun configureDigest(headlines: List<AgentV2NewsDigestHeadline>, remainder: String?) {
        digestHeadlines.configure(headlines, remainder)
        digestHeadlines.isGone = headlines.isEmpty()
    }

    // What the body was last rendered from: a card bound and themed at once parses it once
    private var renderedBody: Triple<String?, Int, Float>? = null

    private fun renderBody() {
        val text = bodyMarkdown
        val codeColor = agentCodeColor
        val rendered = Triple(text, codeColor, body.textSize)
        if (rendered == renderedBody) return
        renderedBody = rendered
        body.isGone = text.isNullOrBlank()
        body.text = text?.let { markdown ->
            val parse = {
                MarkdownParser.parse(
                    markdown,
                    codeColor = codeColor,
                    linkColor = null,
                    detectsUrls = false,
                    textSize = body.textSize
                )
            }
            val key = AgentMessageTextCache.TextKey(
                bodyId,
                markdown,
                codeColor,
                linkColor = null,
                detectsUrls = false,
                textSize = body.textSize
            )
            textCache?.getText(key, parse) ?: parse()
        }
    }

    override fun updateTheme() {
        headline.setTextColor(WColor.PrimaryText)
        body.setTextColor(WColor.PrimaryText)
        time.setTextColor(WColor.SecondaryText)
        digestHeadlines.updateTheme()
        renderBody()
    }

    companion object {
        private const val TEXT_SIZE = 17f
        private const val LINE_HEIGHT = 22f
        private const val META_TEXT_SIZE = 12f

        // In dp, from the bubble's sides: Telegram's `timeX` is 9 dp in from the background's end, whose bubble
        // is drawn 2 dp in
        private const val TEXT_INSET = 16
        private const val TIME_END_INSET = 12

        // A headline stands as far from the body as paragraphs a blank line apart do
        private const val HEADLINE_GAP = 20
        private const val META_GAP = 8
        private const val DIGEST_HEADLINES_GAP = 2

        /**
         * A discussion post's time: today the time, this year the day and time, earlier with the
         * year; short months go as in the chat list, as "20 ноя".
         */
        fun formatPostTime(context: Context, date: Date, now: Date = Date()): String {
            val time = formatAgentChatTime(context, date)
            val calendar = Calendar.getInstance().apply { this.time = date }
            val today = Calendar.getInstance().apply { this.time = now }
            val isSameYear = calendar.get(Calendar.YEAR) == today.get(Calendar.YEAR)
            val isToday = isSameYear &&
                calendar.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
            if (isToday) return time
            return "${formatDay(date, withYear = !isSameYear)}, $time"
        }

        fun formatDay(date: Date, withYear: Boolean): String {
            val locale = Locale.forLanguageTag(LocaleController.activeLanguage.langCode)
            val skeleton = if (withYear) "yMMMd" else "MMMd"
            val pattern = AgentThreadDateFormatting.removeYearSuffix(
                DateFormat.getBestDateTimePattern(locale, skeleton)
            )
            return AgentThreadDateFormatting.makeShortMonthFormat(pattern, locale).format(date)
        }
    }
}
