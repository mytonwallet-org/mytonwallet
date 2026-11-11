package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableString
import android.text.Spanned
import android.text.format.DateFormat
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import java.net.URI
import java.text.SimpleDateFormat
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
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem

private const val MAX_SHOWN_SOURCES = 3
private const val SOURCES_PLACEHOLDER = "%sources%"

/**
 * A news item's text in its bubble, the same in the feed's card and in the discussion's post, so
 * the card lands on the post's text: the headline, the body a blank line under it, the sources
 * under the body, and the time at the bubble's trailing corner, where a message shows its time.
 * It spans the bubble's width: the text keeps 16 dp from the bubble's sides and the time 12 dp
 * from its trailing side, the same on iOS and the web.
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
    private val sources = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        movementMethod = ExtraHitLinkMovementMethod(LINK_HIT_SLOP.dp, LINK_HIT_SLOP.dp)
    }
    private val time = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        setSingleLine()
    }
    private var bodyMarkdown: String? = null
    private var bodyId = ""
    private var sourceLine: AgentNewsSourceLine? = null

    var textCache: AgentMessageTextCache? = null

    /** Opens a source that the line shows as a link */
    var onOpenSource: ((url: String) -> Unit)? = null

    val bodyText: CharSequence get() = body.text
    val sourceLineText: CharSequence get() = sources.text
    val timeText: CharSequence get() = time.text

    /** The source line, whose taps and long presses away from its links belong to the bubble */
    val sourceLabel: TextView get() = sources

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
            sources,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = META_GAP.dp
                marginEnd = (TEXT_INSET - TIME_END_INSET).dp
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

    fun configure(
        id: String,
        headlineText: String,
        body: String?,
        sources: List<AgentNewsSource>,
        timeText: String
    ) {
        headline.text = headlineText
        bodyId = id
        bodyMarkdown = body
        renderBody()
        sourceLine = buildAgentNewsSourceLine(sources)
        renderSourceLine()
        time.text = timeText
    }

    // What the source line was last rendered from: binding and theming a card at once sets its text once
    private var renderedSourceLine: Pair<AgentNewsSourceLine?, Int>? = null

    // The links take the line's grey, so they are drawn again with the theme
    private fun renderSourceLine() {
        val line = sourceLine
        val color = WColor.SecondaryText.color
        val rendered = line to color
        if (rendered == renderedSourceLine) return
        renderedSourceLine = rendered
        sources.isGone = line == null
        time.updateLayoutParams<LayoutParams> {
            topMargin = (if (line == null) META_GAP else SOURCES_TIME_GAP).dp
        }
        if (line == null) {
            sources.text = null
            return
        }
        sources.text = SpannableString(line.text).apply {
            line.links.forEach { link ->
                setSpan(
                    WClickableSpan(link.url, color) { onOpenSource?.invoke(it) },
                    link.start,
                    link.end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
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
        sources.setTextColor(WColor.SecondaryText)
        time.setTextColor(WColor.SecondaryText)
        renderBody()
        renderSourceLine()
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
        private const val SOURCES_TIME_GAP = 4
        private const val LINK_HIT_SLOP = 2

        /**
         * A discussion post's time: today the time, this year the day and time, earlier with the
         * year; short months go as in the chat list, as "20 ноя"
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

/** A source the line shows: its name, and its URL when the line may open it */
internal data class AgentNewsSource(val name: String, val url: String?)

/** The source line's text and where in it each source that opens lies */
internal data class AgentNewsSourceLine(val text: String, val links: List<Link>) {
    data class Link(val start: Int, val end: Int, val url: String)
}

/**
 * The first sources in the API's order, each by its name or else its URL's host, without those
 * that have neither or that repeat a shown name; a card without them shows its stored source name
 */
internal fun makeAgentNewsSources(
    sources: List<AgentV2NewsFeedItem.Source>?,
    legacySource: String?
): List<AgentNewsSource> {
    val shown = mutableListOf<AgentNewsSource>()
    for (source in sources.orEmpty()) {
        if (shown.size == MAX_SHOWN_SOURCES) break
        val name = source.name?.trim()?.takeIf { it.isNotEmpty() }
            ?: findAgentNewsSourceHost(source.url)
            ?: continue
        if (shown.any { it.name.equals(name, ignoreCase = true) }) continue
        shown += AgentNewsSource(name, source.url.takeIf(AgentNewsSourceLinks::isOpenable))
    }
    if (shown.isEmpty()) {
        legacySource?.trim()?.takeIf { it.isNotEmpty() }?.let { shown += AgentNewsSource(it, null) }
    }
    return shown
}

/** "Sources: A, B", with a link on each source that opens; null when there are none */
internal fun buildAgentNewsSourceLine(sources: List<AgentNewsSource>): AgentNewsSourceLine? {
    if (sources.isEmpty()) return null
    val template = if (sources.size == 1) {
        LocaleController.getString("\$agent_news_source")
    } else {
        LocaleController.getString("\$agent_news_sources")
    }
    val comma = LocaleController.getString("\$joining_comma")
    val text = StringBuilder(template.substringBefore(SOURCES_PLACEHOLDER))
    val links = mutableListOf<AgentNewsSourceLine.Link>()
    sources.forEachIndexed { index, source ->
        if (index > 0) text.append(comma)
        val start = text.length
        text.append(source.name)
        source.url?.let { links += AgentNewsSourceLine.Link(start, text.length, it) }
    }
    text.append(template.substringAfter(SOURCES_PLACEHOLDER, missingDelimiterValue = ""))
    return AgentNewsSourceLine(text.toString(), links)
}

private fun findAgentNewsSourceHost(url: String): String? =
    runCatching { URI(url).host }.getOrNull()
        ?.let { if (it.startsWith("www.", ignoreCase = true)) it.drop(4) else it }
        ?.takeIf { it.isNotEmpty() }
