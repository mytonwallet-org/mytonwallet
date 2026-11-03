package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.text.format.DateFormat
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.view.isGone
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * A news item's text in its bubble, the same in the feed's card and in the discussion's post, so
 * the card lands on the post's text: the headline, the body a blank line under it, and "Source •
 * time" at the bubble's trailing corner, where a message shows its time
 */
@SuppressLint("ViewConstructor")
internal class AgentNewsTextBlock(context: Context) :
    LinearLayout(context),
    WThemedView {
    /** The source opens from its name; null leaves it plain */
    var onSourceClick: (() -> Unit)? = null
        set(value) {
            field = value
            if (value == null) {
                source.setOnClickListener(null)
                source.isClickable = false
            } else {
                source.setOnClickListener { value() }
            }
        }

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
    private val source = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val time = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        setSingleLine()
    }
    private var bodyMarkdown: String? = null
    private var bodyId = ""

    var textCache: AgentMessageTextCache? = null

    val bodyText: CharSequence get() = body.text
    val sourceText: CharSequence get() = source.text
    val timeText: CharSequence get() = time.text

    init {
        id = generateViewId()
        orientation = VERTICAL
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        val meta = LinearLayout(context).apply {
            id = generateViewId()
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            addView(source, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(time, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        addView(headline, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            body,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = HEADLINE_GAP.dp }
        )
        addView(
            meta,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = META_GAP.dp }
        )
        updateTheme()
    }

    fun configure(
        id: String,
        headlineText: String,
        body: String?,
        sourceName: String?,
        timeText: String
    ) {
        headline.text = headlineText
        bodyId = id
        bodyMarkdown = body
        renderBody()
        source.text = sourceName.orEmpty()
        source.isGone = sourceName.isNullOrEmpty()
        // The source truncates; the time doesn't
        time.text = if (sourceName.isNullOrEmpty()) timeText else "$SEPARATOR$timeText"
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // The source takes what the time leaves
        val width = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        val unspecified = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        time.measure(unspecified, unspecified)
        source.maxWidth = (width - time.measuredWidth).coerceAtLeast(0)
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    // What the body was last rendered from: a card bound and themed at once parses it once
    private var renderedBody: Triple<String?, Int, Float>? = null

    private fun renderBody() {
        val text = bodyMarkdown
        val codeColor = WColor.SecondaryBackground.color
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
        source.setTextColor(WColor.SecondaryText)
        time.setTextColor(WColor.SecondaryText)
        renderBody()
    }

    companion object {
        private const val TEXT_SIZE = 17f
        private const val LINE_HEIGHT = 22f
        private const val META_TEXT_SIZE = 12f

        // A headline stands as far from the body as paragraphs a blank line apart do
        private const val HEADLINE_GAP = 20
        private const val META_GAP = 8
        private const val SEPARATOR = " • "

        /**
         * A discussion post's time: today the time, this year the day and time, earlier with the
         * year; abbreviated months lose their dot
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
            val pattern = DateFormat.getBestDateTimePattern(locale, skeleton)
            return SimpleDateFormat(pattern, locale).format(date).replace(ABBREVIATION_DOT, "$1")
        }

        private val ABBREVIATION_DOT = Regex("(\\p{L})\\.")
    }
}
