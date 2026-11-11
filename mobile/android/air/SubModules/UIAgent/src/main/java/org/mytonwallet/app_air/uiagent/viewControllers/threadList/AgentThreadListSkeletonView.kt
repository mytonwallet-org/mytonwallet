package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.view.Choreographer
import android.view.View
import android.view.animation.DecelerateInterpolator
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentDebugAnimations
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentOnScreenTracker
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Placeholder rows shown until the first page of chats has loaded, after Telegram's chat list shimmer: an avatar and
 * the bars of a title, a time and two preview lines per row, with a light band crossing them from top to bottom
 */
internal class AgentThreadListSkeletonView(context: Context) :
    View(context),
    WThemedView {
    private val shapes = Path()
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shimmerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shimmerMatrix = Matrix()
    private val rect = RectF()
    private val interpolator = DecelerateInterpolator()
    private var shimmer: LinearGradient? = null
    private var startTimeNanos = 0L
    private var isFrameScheduled = false

    // A page of the tabs laid out beside the selected one still counts as visible
    private val onScreenTracker = AgentOnScreenTracker(this) { scheduleFrameIfNeeded() }
    private val isShownOnScreen: Boolean
        get() = onScreenTracker.isOnScreen

    private val onSystemAnimationsChanged: () -> Unit = {
        invalidate()
        scheduleFrameIfNeeded()
    }

    private val frameCallback = Choreographer.FrameCallback {
        isFrameScheduled = false
        invalidate()
        scheduleFrameIfNeeded()
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = LocaleController.getString("Loading...")
        accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
        updateTheme()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        buildShapes(w, h)
        updateShimmer()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        onScreenTracker.setVisibilityAggregated(isVisible)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        onScreenTracker.attach()
        AgentDebugAnimations.addListener(context, onSystemAnimationsChanged)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        onScreenTracker.detach()
        AgentDebugAnimations.removeListener(context, onSystemAnimationsChanged)
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
        shimmerMatrix.setTranslate(0f, -band + (height + band) * progress)
        shimmer.setLocalMatrix(shimmerMatrix)
        canvas.save()
        canvas.clipPath(shapes)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), shimmerPaint)
        canvas.restore()
    }

    override fun updateTheme() {
        fillPaint.color = if (ThemeManager.isDark) {
            WColor.TrinaryBackground.color
        } else {
            WColor.ThumbBackground.color
        }
        updateShimmer()
        invalidate()
    }

    private val isMoving: Boolean
        get() = isShownOnScreen && isAttachedToWindow && WGlobalStorage.getAreAnimationsActive() &&
            AgentDebugAnimations.areSystemAnimationsOn(context)

    private fun scheduleFrameIfNeeded() {
        if (!isMoving || isFrameScheduled) return
        if (startTimeNanos == 0L) startTimeNanos = System.nanoTime()
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun updateShimmer() {
        val peak = ColorUtils.setAlphaComponent(
            Color.WHITE,
            ((if (ThemeManager.isDark) DARK_PEAK else LIGHT_PEAK) * 255).toInt()
        )
        shimmer = LinearGradient(
            0f,
            0f,
            0f,
            SHIMMER_BAND.dp.toFloat(),
            intArrayOf(Color.TRANSPARENT, peak, Color.TRANSPARENT),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        shimmerPaint.shader = shimmer
    }

    // Rows every row height, mirrored in RTL
    private fun buildShapes(width: Int, height: Int) {
        shapes.rewind()
        val metrics = AgentThreadRowMetrics
        val rowHeight = metrics.MIN_HEIGHT.dp
        val barHeight = BAR_HEIGHT.dp.toFloat()
        val radius = barHeight / 2
        val isRtl = LocaleController.isRTL
        fun addBar(x: Float, centerY: Float, barWidth: Float) {
            val left = if (isRtl) width - x - barWidth else x
            rect.set(left, centerY - barHeight / 2, left + barWidth, centerY + barHeight / 2)
            shapes.addRoundRect(rect, radius, radius, Path.Direction.CW)
        }
        val avatar = metrics.AVATAR.dp.toFloat()
        val contentStart = metrics.contentStart.toFloat()
        val trailing = (width - metrics.HORIZONTAL_PADDING.dp).toFloat()
        var top = 0
        while (top < height) {
            val avatarX = metrics.HORIZONTAL_PADDING.dp + avatar / 2
            val centerX = if (isRtl) width - avatarX else avatarX
            shapes.addCircle(centerX, top + rowHeight / 2f, avatar / 2, Path.Direction.CW)
            val titleCenter = top + (metrics.VERTICAL_PADDING + metrics.TITLE_LINE / 2).dp.toFloat()
            val previewTop = top + (metrics.VERTICAL_PADDING + metrics.TITLE_LINE).dp
            val firstLine = previewTop + PREVIEW_LINE.dp / 2f
            val secondLine = firstLine + PREVIEW_LINE.dp
            addBar(contentStart, titleCenter, TITLE_BAR.dp.toFloat())
            addBar(trailing - TIME_BAR.dp, titleCenter, TIME_BAR.dp.toFloat())
            addBar(contentStart, firstLine, PREVIEW_LONG_BAR.dp.toFloat())
            addBar(
                contentStart + (PREVIEW_LONG_BAR + PREVIEW_GAP).dp,
                firstLine,
                PREVIEW_SHORT_BAR.dp.toFloat()
            )
            addBar(contentStart, secondLine, PREVIEW_SHORT_BAR.dp.toFloat())
            top += rowHeight
        }
        invalidate()
    }

    private companion object {
        const val NANOS_PER_MS = 1_000_000f
        const val SHIMMER_PERIOD_MS = 1300f
        const val SHIMMER_BAND = 250
        const val LIGHT_PEAK = 0.7f
        const val DARK_PEAK = 0.14f
        const val BAR_HEIGHT = 8
        const val PREVIEW_LINE = 20
        const val TITLE_BAR = 60
        const val TIME_BAR = 30
        const val PREVIEW_LONG_BAR = 120
        const val PREVIEW_SHORT_BAR = 60
        const val PREVIEW_GAP = 10
    }
}
