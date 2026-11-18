package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Rect
import android.graphics.Shader
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsFlightSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMenuRows
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMenuTouch
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentMenuBackdrop
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentMenuPlacement
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentMessageMenuHeader
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.buildAgentNewsMenuItems
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.getAgentListRows
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.setMessageMenuTapListener
import org.mytonwallet.app_air.uiagent.viewControllers.agent.makeAgentBubbleFlightSnapshot
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_TAIL_WIDTH
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBubbleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard

// The digest's top in the look of the Agent's suggestions, as on iOS and the web: a light sheen and
// the Agent's gradient, melting into the card's fill toward the headlines, and the title in the
// suggestions' gradient. Each pair is for the light theme, then the dark one.
private const val DIGEST_GLOW_HEIGHT = 150f
private val DIGEST_GLOW_POSITIONS = floatArrayOf(0f, 0.48f, 1f)
private val DIGEST_GLOW_LIGHT = intArrayOf(0x1F0088FF, 0x2E00BEFF, 0x24B656FF)
private val DIGEST_GLOW_DARK = intArrayOf(0x2E0088FF, 0x3D00BEFF, 0x33B656FF)
private const val DIGEST_SHEEN_LIGHT = 0xB3FFFFFF.toInt()
private const val DIGEST_SHEEN_DARK = 0x00FFFFFF
private val DIGEST_TITLE_LIGHT =
    intArrayOf(0xFF005DAF.toInt(), 0xFF007BA5.toInt(), 0xFF7D2EBA.toInt())
private val DIGEST_TITLE_DARK =
    intArrayOf(0xFF6DADE6.toInt(), 0xFF5EB6D4.toInt(), 0xFFC48CEE.toInt())
private val DIGEST_TITLE_POSITIONS = floatArrayOf(0f, 0.4f, 1f)

// How much of the title's gradient the news count takes, as much contrast as the grey has
private const val DIGEST_META_ALPHA_LIGHT = 0.65f
private const val DIGEST_META_ALPHA_DARK = 0.9f

/** What a daily digest's card in the News feed shows */
internal data class AgentNewsDigestCardContent(
    val title: String,
    /** How many news the digest covers */
    val meta: String,
    val headlines: List<AgentV2NewsDigestHeadline>,
    /** The news the digest covers beyond its headlines, which are above in the feed unless it lists digests only */
    val remainder: String?,
    /** When the digest came, as the feed's news cards show theirs */
    val time: String,
    /** What the card's menu copies and shares, as the digest's post's menu does */
    val post: AgentNewsPostContent,
    val date: Date?
) {
    constructor(
        digest: AgentV2NewsFeedDigest,
        time: String,
        isInDigestsView: Boolean = false
    ) : this(
        title = LocaleController.getString("\$agent_digest_title"),
        meta = LocaleController.getPlural(digest.total, "\$agent_digest_meta"),
        headlines = digest.top,
        remainder = (digest.total - digest.top.size).takeIf { it > 0 }
            ?.let {
                LocaleController.getPlural(
                    it,
                    if (isInDigestsView) "\$agent_digest_more_count" else "\$agent_digest_more"
                )
            },
        time = time,
        post = AgentNewsPostContent(
            AgentV2ThreadDigestCard(digest.id, digest.deliveredAt, digest.total, digest.top)
        ),
        date = parseAgentV2Timestamp(digest.deliveredAt)
    )
}

/**
 * A daily digest in the News feed, in the bubble the feed's news cards have, topped in the look of
 * the suggestions: its title, how many news it covers, its top headlines, each opening its news
 * item's discussion, the news it leaves out, the time it came in the bubble's trailing corner, as a
 * news card's, and the Discuss strip, which opens the digest's own discussion. A tap or a long press
 * on the bubble opens its menu, as on a news card.
 */
@SuppressLint("ViewConstructor")
internal class AgentNewsDigestCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView,
    AgentNewsFlightSource {
    private val bubbleDrawable = AgentBubbleDrawable(isOutgoing = false).apply {
        glowPositions = DIGEST_GLOW_POSITIONS
        glowHeight = DIGEST_GLOW_HEIGHT.dp
    }
    private var titleGradientColors = DIGEST_TITLE_LIGHT
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
        // The gradient paints over an opaque color
        setTextColor(Color.BLACK)
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            updateTitleShader()
            // The count's gradient runs across the title
            updateMetaShader()
        }
    }
    private var metaGradientAlpha = DIGEST_META_ALPHA_LIGHT
    private val metaLabel = WLabel(context).apply {
        setStyle(META_TEXT_SIZE)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setTextColor(Color.BLACK)
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> updateMetaShader() }
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
    private val headlinesView = AgentNewsDigestHeadlinesView(context)
    private val timeLabel = WLabel(context).apply {
        setStyle(TIME_TEXT_SIZE)
        setSingleLine()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    val discussStrip = AgentNewsDiscussStrip(context)

    /** A tap on a headline, which opens its news item's discussion */
    var onHeadlineClick: ((AgentV2NewsDigestHeadline) -> Unit)?
        get() = headlinesView.onHeadlineClick
        set(value) {
            headlinesView.onHeadlineClick = value
        }

    /** A tap on a headline's picture, which opens the digest's pictures in the media viewer */
    var onPictureClick: ((AgentNewsDigestPictures) -> Unit)?
        get() = headlinesView.onPictureClick
        set(value) {
            headlinesView.onPictureClick = value
        }

    /** The digest's bubble without its tail, where the skeleton's placeholder lands */
    val postView: View get() = bubble

    private val menuTouch = AgentMenuTouch()
    private var menuContent: AgentNewsDigestCardContent? = null

    /** Rows where the menu leaves the bubble undimmed */
    var menuRows: AgentMenuRows = { getAgentListRows(this) }
    var onPopupVisibilityChanged: ((visible: Boolean) -> Unit)? = null
    var onCopied: (() -> Unit)? = null
    var canOpenMenuOnTap: () -> Boolean = { true }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        bubble.addView(header, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bubble.addView(
            headlinesView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginStart = HORIZONTAL_PADDING.dp
            }
        )
        bubble.addView(
            timeLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END
                marginEnd = TIME_END_INSET.dp
                bottomMargin = TIME_BOTTOM.dp
            }
        )
        bubble.addView(discussStrip, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(bubble, LayoutParams(0, WRAP_CONTENT))
        bubble.setOnLongClickListener {
            showMenu()
            true
        }
        bubble.setMessageMenuTapListener {
            if (canOpenMenuOnTap()) showMenu()
        }
        setConstraints {
            toTop(bubble, ROW_MARGIN)
            toBottom(bubble, ROW_MARGIN)
            toStart(bubble, LEADING_INSET)
            toEnd(bubble, TRAILING_INSET)
        }
        updateTheme()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        menuTouch.track(this, event)
        return super.dispatchTouchEvent(event)
    }

    fun configure(content: AgentNewsDigestCardContent) {
        menuContent = content
        titleLabel.text = content.title
        updateTitleShader()
        metaLabel.text = content.meta
        updateMetaShader()
        timeLabel.text = content.time
        header.contentDescription = "${content.title}, ${content.meta}, ${content.time}"
        headlinesView.configure(content.headlines, content.remainder)
        // Without the remainder line the last headline's room stands over the time
        headlinesView.setPaddingRelative(
            0,
            0,
            0,
            if (content.remainder == null) HEADLINES_BOTTOM.dp else REMAINDER_TIME_GAP.dp
        )
        discussStrip.configureDiscuss(content.title)
    }

    private fun showMenu() {
        val content = menuContent ?: return
        val actions = listOf(buildAgentMessageMenuHeader(context, content.date ?: Date())) +
            buildAgentNewsMenuItems(this, content.post, onOpenSource = null, onCopied = onCopied)
        onPopupVisibilityChanged?.invoke(true)
        WMenuPopup.present(
            bubble,
            actions,
            positioning = WMenuPopup.Positioning.BELOW,
            backdropStyle = WMenuPopup.BackdropStyle.Dimmed,
            windowBackgroundStyle = buildAgentMenuBackdrop(
                bubbleDrawable.buildCutoutPath(bubble),
                menuRows()
            ),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false) },
            placement = buildAgentMenuPlacement(this, bubble, menuTouch.take(bubble))
        )
    }

    fun makePictureSource(headline: AgentV2NewsDigestHeadline): MediaViewerVC.Source? =
        headlinesView.makePictureSource(headline, menuRows())

    override fun makeFlightSnapshot(): Pair<Bitmap, Rect>? = makeAgentBubbleFlightSnapshot(bubble)

    override fun setFlightSourceHidden(isHidden: Boolean) {
        bubble.alpha = if (isHidden) 0f else 1f
    }

    private fun updateTitleShader() {
        applyTextGradient(titleLabel, titleGradientColors)
    }

    private fun updateMetaShader() {
        val alpha = (255 * metaGradientAlpha).toInt()
        val colors = IntArray(titleGradientColors.size) {
            ColorUtils.setAlphaComponent(titleGradientColors[it], alpha)
        }
        // Across the title, so the count takes the title's colours where the two lines overlap
        applyTextGradient(metaLabel, colors, widthSource = titleLabel)
    }

    // The suggestions' gradient across the longest line of widthSource, the label's own by default, from where the
    // label's lines start
    private fun applyTextGradient(label: WLabel, colors: IntArray, widthSource: WLabel = label) {
        val layout = widthSource.layout ?: return
        val textWidth = (0 until layout.lineCount).maxOfOrNull { layout.getLineWidth(it) } ?: return
        if (textWidth <= 0f) return
        val start = if (LocaleController.isRTL) {
            (label.width - label.paddingRight).toFloat()
        } else {
            label.paddingLeft.toFloat()
        }
        val end = start + if (LocaleController.isRTL) -textWidth else textWidth
        label.paint.shader = LinearGradient(
            start,
            0f,
            end,
            0f,
            colors,
            DIGEST_TITLE_POSITIONS,
            Shader.TileMode.CLAMP
        )
        label.invalidate()
    }

    override fun updateTheme() {
        val isDark = ThemeManager.isDark
        bubbleDrawable.setBubbleColor(agentIncomingBubbleColor)
        bubbleDrawable.glowColors = if (isDark) DIGEST_GLOW_DARK else DIGEST_GLOW_LIGHT
        bubbleDrawable.glowSheenColor = if (isDark) DIGEST_SHEEN_DARK else DIGEST_SHEEN_LIGHT
        titleGradientColors = if (isDark) DIGEST_TITLE_DARK else DIGEST_TITLE_LIGHT
        metaGradientAlpha = if (isDark) DIGEST_META_ALPHA_DARK else DIGEST_META_ALPHA_LIGHT
        updateTitleShader()
        updateMetaShader()
        timeLabel.setTextColor(WColor.SecondaryText)
        headlinesView.updateTheme()
        discussStrip.updateTheme()
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

        // As over and under a news card's time, which ends 12 from the bubble's side
        const val REMAINDER_TIME_GAP = 8
        const val TIME_END_INSET = 12
        const val TIME_BOTTOM = 7
        const val TIME_TEXT_SIZE = 12f
    }
}
