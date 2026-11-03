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
 * [Style.NEWS_CARDS] style, cards of the News feed stand in their place. [Style.SUGGESTION] fills one hint chip.
 */
internal class AgentMessagesSkeletonView(
    context: Context,
    private val style: Style = Style.MESSAGES
) : View(context),
    WThemedView {
    enum class Style { MESSAGES, NEWS_CARDS, SUGGESTION }
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
    private var isShownOnScreen = false

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
        isShownOnScreen = isVisible
        scheduleFrameIfNeeded()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
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
        if (style == Style.SUGGESTION) {
            shapes.addRoundRect(
                0f,
                0f,
                width.toFloat(),
                height.toFloat(),
                SUGGESTION_RADIUS.dp,
                SUGGESTION_RADIUS.dp,
                Path.Direction.CW
            )
            invalidate()
            return
        }
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

    // Tall and short cards in turn from the bottom up, inset as the feed's cards are
    private fun buildCards(width: Int, height: Int) {
        val radius = CARD_RADIUS.dp
        var bottom = height.toFloat()
        var index = 0
        while (bottom > 0f) {
            val top = bottom - CARD_HEIGHTS[index % CARD_HEIGHTS.size].dp
            placeholders.add(
                Placeholder(
                    RectF(
                        paddingLeft + CARD_INSET.dp,
                        top,
                        width - paddingRight - CARD_INSET.dp,
                        bottom
                    ),
                    false
                )
            )
            shapes.addRoundRect(
                paddingLeft + CARD_INSET.dp,
                top,
                width - paddingRight - CARD_INSET.dp,
                bottom,
                radius,
                radius,
                Path.Direction.CW
            )
            bottom = top - CARD_GAP.dp
            index++
        }
        invalidate()
    }

    private companion object {
        const val SUGGESTION_RADIUS = 18f
        const val CARD_RADIUS = 21f
        const val CARD_INSET = 16f
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

        val WIDTH_FRACTIONS = floatArrayOf(
            0.86f,
            0.70f,
            0.92f,
            0.64f,
            0.80f,
            0.72f,
            0.86f,
            0.64f
        )
        val HEIGHTS = intArrayOf(184, 120, 184, 120, 184, 120, 184, 120)
    }
}
