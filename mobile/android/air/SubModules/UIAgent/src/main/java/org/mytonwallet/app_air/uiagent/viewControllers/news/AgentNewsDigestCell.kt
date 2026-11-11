package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_TAIL_WIDTH
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBubbleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest

/** What a daily digest's card in the News feed shows */
internal data class AgentNewsDigestCardContent(
    val title: String,
    /** How many news the digest covers and when it came */
    val meta: String,
    val headlines: List<AgentV2NewsDigestHeadline>,
    /** The news the digest covers beyond its headlines, which are above in the feed */
    val remainder: String?
) {
    /** [time] is when the digest came, as the feed's news cards show theirs */
    constructor(digest: AgentV2NewsFeedDigest, time: String) : this(
        title = LocaleController.getString("\$agent_digest_title"),
        meta = LocaleController.getPlural(digest.total, "\$agent_digest_meta")
            .replace("%time%", time),
        headlines = digest.top,
        remainder = (digest.total - digest.top.size).takeIf { it > 0 }
            ?.let { LocaleController.getPlural(it, "\$agent_digest_more") }
    )
}

/**
 * A daily digest in the News feed, in the bubble the feed's news cards have: its title, how many news it covers and
 * when it came, its top headlines, each opening its news item's discussion, the news it leaves out, and the Discuss
 * strip, which opens the digest's own discussion
 */
@SuppressLint("ViewConstructor")
internal class AgentNewsDigestCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val bubbleDrawable = AgentBubbleDrawable(isOutgoing = false)
    private val bubble = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        background = bubbleDrawable
        setPaddingRelative(AGENT_BUBBLE_TAIL_WIDTH.dp, 0, 0, 0)
    }
    private val titleLabel = WLabel(context).apply {
        setStyle(TITLE_TEXT_SIZE, WFont.Medium)
        setLineHeight(TITLE_LINE_HEIGHT)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val metaLabel = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val header = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        setPaddingRelative(
            HORIZONTAL_PADDING.dp,
            HEADER_TOP.dp,
            HORIZONTAL_PADDING.dp,
            HEADER_BOTTOM.dp
        )
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = true
        ViewCompat.setAccessibilityHeading(this, true)
        addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            metaLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = META_GAP.dp
            }
        )
    }

    // The headlines' arrows stand where the Discuss strip's does, nearer the side than the text
    private val headlinesView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        setPaddingRelative(HORIZONTAL_PADDING.dp, 0, 0, 0)
    }
    private val remainderLabel = WLabel(context).apply {
        setStyle(REMAINDER_TEXT_SIZE)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        setPaddingRelative(
            HEADLINE_TEXT_START.dp,
            REMAINDER_TOP.dp,
            HORIZONTAL_PADDING.dp,
            REMAINDER_BOTTOM.dp
        )
    }
    private val headlineRows = mutableListOf<HeadlineRow>()
    private val separators = mutableListOf<View>()

    val discussStrip = AgentNewsDiscussStrip(context)

    /** A tap on a headline, which opens its news item's discussion */
    var onHeadlineClick: ((AgentV2NewsDigestHeadline) -> Unit)? = null

    /** The digest's bubble without its tail, where the skeleton's placeholder lands */
    val postView: View get() = bubble

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        bubble.addView(header, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bubble.addView(headlinesView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bubble.addView(remainderLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bubble.addView(discussStrip, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(bubble, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(bubble, ROW_MARGIN)
            toBottom(bubble, ROW_MARGIN)
            toStart(bubble, LEADING_INSET)
            toEnd(bubble, TRAILING_INSET)
        }
        updateTheme()
    }

    fun configure(content: AgentNewsDigestCardContent) {
        titleLabel.text = content.title
        metaLabel.text = content.meta
        header.contentDescription = "${content.title}, ${content.meta}"
        configureHeadlines(content.headlines)
        remainderLabel.text = content.remainder
        remainderLabel.isGone = content.remainder == null
        // Without the remainder line the last headline's room ends the list
        headlinesView.setPaddingRelative(
            HORIZONTAL_PADDING.dp,
            0,
            0,
            if (content.remainder == null) HEADLINES_BOTTOM.dp else 0
        )
        discussStrip.configureDiscuss(content.title)
    }

    override fun updateTheme() {
        bubbleDrawable.setBubbleColor(agentIncomingBubbleColor)
        titleLabel.setTextColor(WColor.PrimaryText)
        metaLabel.setTextColor(WColor.SecondaryText)
        remainderLabel.setTextColor(WColor.SecondaryText)
        headlineRows.forEach(HeadlineRow::updateTheme)
        separators.forEach { it.setBackgroundColor(WColor.Separator.color) }
        discussStrip.updateTheme()
    }

    // One row for each headline, a separator between rows; the rows a digest leaves out stay for the next one
    private fun configureHeadlines(headlines: List<AgentV2NewsDigestHeadline>) {
        while (headlineRows.size < headlines.size) {
            if (headlineRows.isNotEmpty()) {
                val separator = View(context).apply { id = generateViewId() }
                separator.setBackgroundColor(WColor.Separator.color)
                separators.add(separator)
                headlinesView.addView(
                    separator,
                    LinearLayout.LayoutParams(MATCH_PARENT, 1).apply {
                        marginEnd = HORIZONTAL_PADDING.dp
                    }
                )
            }
            val row = HeadlineRow(context)
            headlineRows.add(row)
            headlinesView.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        headlineRows.forEachIndexed { index, row ->
            val headline = headlines.getOrNull(index)
            row.isGone = headline == null
            separators.getOrNull(index - 1)?.isGone = headline == null
            if (headline == null) return@forEachIndexed
            row.configure(headline.headline)
            row.setOnClickListener { onHeadlineClick?.invoke(headline) }
        }
    }

    /** A headline with its bullet by its first line and the disclosure arrow, dimmed while pressed */
    @SuppressLint("ViewConstructor", "ClickableViewAccessibility")
    private class HeadlineRow(context: Context) :
        WView(context),
        WThemedView {
        private val bulletDrawable = GradientDrawable().apply { shape = GradientDrawable.OVAL }
        private val bullet = View(context).apply {
            id = generateViewId()
            background = bulletDrawable
        }
        private val label = WLabel(context).apply {
            setStyle(HEADLINE_TEXT_SIZE)
            setLineHeight(HEADLINE_LINE_HEIGHT)
            isSingleLine = false
            maxLines = Int.MAX_VALUE
        }
        private val chevron = ImageView(context).apply {
            id = generateViewId()
            setImageResource(R.drawable.ic_menu_arrow_right)
            scaleType = ImageView.ScaleType.CENTER
        }
        private val content = WView(context).apply {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        init {
            minimumHeight = MIN_HEIGHT.dp
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
            isFocusable = true
            isClickable = true
            content.addView(bullet, ConstraintLayout.LayoutParams(BULLET.dp, BULLET.dp))
            content.addView(label, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            content.addView(chevron, ConstraintLayout.LayoutParams(CHEVRON_BOX.dp, CHEVRON_BOX.dp))
            content.setConstraints {
                toStart(bullet)
                // The bullet stands by the headline's first line
                toTop(bullet, (HEADLINE_LINE_HEIGHT - BULLET) / 2)
                startToEnd(label, bullet, BULLET_GAP.toFloat())
                endToStart(label, chevron)
                toTop(label)
                toBottom(label)
                toEnd(chevron, CHEVRON_END)
                toCenterY(chevron)
            }
            addView(content, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toStart(content)
                toEnd(content)
                toTop(content, VERTICAL_INSET.toFloat())
                toBottom(content, VERTICAL_INSET.toFloat())
            }
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        content.animate().cancel()
                        content.alpha = PRESSED_ALPHA
                    }

                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                        content.animate().alpha(1f).setDuration(PRESS_RELEASE_MS).start()
                }
                false
            }
            updateTheme()
        }

        fun configure(headline: String) {
            label.text = headline
            contentDescription = headline
        }

        override fun updateTheme() {
            bulletDrawable.setColor(WColor.Tint.color)
            label.setTextColor(WColor.PrimaryText)
            chevron.setColorFilter(WColor.Tint.color)
        }
    }

    private companion object {
        // In dp: as the feed's news cards, whose bubbles start 10 from the side and their bodies 16
        const val LEADING_INSET = 10f
        const val TRAILING_INSET = 16f
        const val ROW_MARGIN = 6f
        const val HORIZONTAL_PADDING = 16
        const val HEADER_TOP = 12
        const val HEADER_BOTTOM = 4
        const val META_GAP = 2
        const val TITLE_TEXT_SIZE = 17f
        const val TITLE_LINE_HEIGHT = 22f
        const val META_TEXT_SIZE = 13f
        const val HEADLINES_BOTTOM = 4
        const val REMAINDER_TEXT_SIZE = 15f
        const val REMAINDER_TOP = 2
        const val REMAINDER_BOTTOM = 12

        // A headline row: its text after the bullet, the arrow at the end as the Discuss strip's
        const val MIN_HEIGHT = 44
        const val VERTICAL_INSET = 10
        const val HEADLINE_TEXT_SIZE = 16f
        const val HEADLINE_LINE_HEIGHT = 21f
        const val BULLET = 6
        const val BULLET_GAP = 10
        const val CHEVRON_BOX = 24
        const val CHEVRON_END = 9f
        const val PRESSED_ALPHA = 0.4f
        const val PRESS_RELEASE_MS = 200L

        // The remainder line starts where the headlines' text does
        const val HEADLINE_TEXT_START = HORIZONTAL_PADDING + BULLET + BULLET_GAP
    }
}
