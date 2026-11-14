package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.view.Choreographer
import android.view.View
import android.view.animation.DecelerateInterpolator
import androidx.core.graphics.ColorUtils
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Placeholder bubbles shown while a chat's messages load, after Telegram's chat loading placeholder: from the
 * bottom up, an answer and a question in turn, with a light band crossing them from the leading side. In the
 * [Style.NEWS_CARDS] style, cards of the News feed stand in their place.
 */
internal class AgentMessagesSkeletonView(
    context: Context,
    private val style: Style = Style.MESSAGES
) : View(context),
    WThemedView {
    enum class Style { MESSAGES, NEWS_CARDS }
    data class Placeholder(val frame: RectF, val isOutgoing: Boolean)
    private val placeholders = mutableListOf<Placeholder>()

    fun placeholdersInWindow(): List<Placeholder> {
        val location = IntArray(2)
        getLocationInWindow(location)
        return placeholders.map {
            Placeholder(
                RectF(it.frame).apply {
                    offset(location[0].toFloat(), location[1].toFloat())
                },
                it.isOutgoing
            )
        }
    }

    private val shapes = Path()
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shimmerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shimmerMatrix = Matrix()
    private val interpolator = DecelerateInterpolator()
    private var shimmer: LinearGradient? = null
    private var startTimeNanos = 0L
    private var isFrameScheduled = false

    // A page of the tabs laid out beside the selected one still counts as visible
    private val onScreenTracker = AgentOnScreenTracker(this) { scheduleFrameIfNeeded() }
    private val isShownOnScreen: Boolean
        get() = onScreenTracker.isOnScreen

    private val frameCallback = Choreographer.FrameCallback {
        isFrameScheduled = false
        invalidate()
        scheduleFrameIfNeeded()
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = LocaleController.getString("Loading...")
        updateTheme()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        buildShapes(w, h)
    }

    override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
        val hasChanged = left != paddingLeft || top != paddingTop || right != paddingRight ||
            bottom != paddingBottom
        super.setPadding(left, top, right, bottom)
        if (hasChanged && width > 0) buildShapes(width, height)
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        onScreenTracker.setVisibilityAggregated(isVisible)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        onScreenTracker.attach()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        onScreenTracker.detach()
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawPath(shapes, fillPaint)
        val shimmer = shimmer ?: return
        if (!isMoving) return
        val elapsed = (System.nanoTime() - startTimeNanos) / NANOS_PER_MS
        val cycle = (elapsed % SHIMMER_PERIOD_MS) / SHIMMER_PERIOD_MS
        val progress = interpolator.getInterpolation(cycle)
        val band = SHIMMER_BAND.dp.toFloat()
        val travel = -band + (width + band) * progress
        val offset = if (LocaleController.isRTL) width - travel - band else travel
        shimmerMatrix.setTranslate(offset, 0f)
        shimmer.setLocalMatrix(shimmerMatrix)
        canvas.save()
        canvas.clipPath(shapes)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), shimmerPaint)
        canvas.restore()
    }

    override fun updateTheme() {
        fillPaint.color = agentIncomingBubbleColor
        val peak = ColorUtils.setAlphaComponent(
            Color.WHITE,
            ((if (ThemeManager.isDark) DARK_PEAK else LIGHT_PEAK) * 255).roundToInt()
        )
        shimmer = LinearGradient(
            0f,
            0f,
            SHIMMER_BAND.dp.toFloat(),
            0f,
            intArrayOf(Color.TRANSPARENT, peak, Color.TRANSPARENT),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        ).also { shimmerPaint.shader = it }
        invalidate()
    }

    private val isMoving: Boolean
        get() = isShownOnScreen && isAttachedToWindow && WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    private fun scheduleFrameIfNeeded() {
        if (!isMoving || isFrameScheduled) return
        if (startTimeNanos == 0L) startTimeNanos = System.nanoTime()
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    // Bubbles from the bottom up, the lowest an answer, with the real bubbles' insets
    private fun buildShapes(width: Int, height: Int) {
        shapes.rewind()
        placeholders.clear()
        if (style == Style.NEWS_CARDS) {
            buildCards(width, height)
            return
        }
        val columnWidth = width - 2 * SIDE_INSET.dp
        var bottom = height.toFloat()
        for (index in WIDTH_FRACTIONS.indices) {
            val isIncoming = index % 2 == 0
            val bubbleWidth =
                (columnWidth * WIDTH_FRACTIONS[index]).roundToInt() + AGENT_BUBBLE_TAIL_WIDTH.dp
            val bubbleHeight = HEIGHTS[index].dp
            val top = bottom - bubbleHeight
            if (top + bubbleHeight < 0f) break
            val drawable = AgentBubbleDrawable(isOutgoing = !isIncoming)
            drawable.setBounds(0, 0, bubbleWidth, bubbleHeight)
            val isOnLeft = isIncoming != LocaleController.isRTL
            val left = if (isOnLeft) {
                BUBBLE_EDGE_INSET.dp.toFloat()
            } else {
                width - BUBBLE_EDGE_INSET.dp - bubbleWidth.toFloat()
            }
            val outline = drawable.buildOutlinePath()
            placeholders.add(Placeholder(RectF(left, top, left + bubbleWidth, bottom), !isIncoming))
            outline.offset(left, top)
            shapes.addPath(outline)
            bottom = top - GAP.dp
        }
        invalidate()
    }

    // Tall and short cards in turn from the bottom up, each the Agent's bubble with its tail and inset as the feed's
    // cards are
    private fun buildCards(width: Int, height: Int) {
        val cardWidth =
            width - paddingLeft - paddingRight - CARD_LEADING_INSET.dp - CARD_TRAILING_INSET.dp
        var bottom = height.toFloat()
        var index = 0
        while (bottom > 0f && cardWidth > 0) {
            val cardHeight = CARD_HEIGHTS[index % CARD_HEIGHTS.size].dp
            val top = bottom - cardHeight
            val left = if (LocaleController.isRTL) {
                (width - paddingRight - CARD_LEADING_INSET.dp - cardWidth).toFloat()
            } else {
                (paddingLeft + CARD_LEADING_INSET.dp).toFloat()
            }
            val drawable = AgentBubbleDrawable(isOutgoing = false)
            drawable.setBounds(0, 0, cardWidth, cardHeight)
            val outline = drawable.buildOutlinePath()
            outline.offset(left, top)
            shapes.addPath(outline)
            placeholders.add(Placeholder(RectF(left, top, left + cardWidth, bottom), false))
            bottom = top - CARD_GAP.dp
            index++
        }
        invalidate()
    }

    private companion object {
        // As the feed's cards: the tail's side, and the other
        const val CARD_LEADING_INSET = 10
        const val CARD_TRAILING_INSET = 16
        const val CARD_GAP = 14
        val CARD_HEIGHTS = intArrayOf(380, 204)
        const val NANOS_PER_MS = 1_000_000f
        const val SHIMMER_PERIOD_MS = 1600f
        const val SHIMMER_BAND = 280
        const val LIGHT_PEAK = 0.7f
        const val DARK_PEAK = 0.14f
        const val SIDE_INSET = 10
        const val BUBBLE_EDGE_INSET = 10f
        const val GAP = 12

        // The Agent's answers run several paragraphs and the user's questions a line or two, so the Agent's bubbles
        // are tall and wide and the user's short and narrow
        val WIDTH_FRACTIONS = floatArrayOf(
            0.86f,
            0.56f,
            0.92f,
            0.44f,
            0.80f,
            0.60f,
            0.86f,
            0.48f
        )
        val HEIGHTS = intArrayOf(248, 56, 216, 40, 264, 56, 232, 40)
    }
}
