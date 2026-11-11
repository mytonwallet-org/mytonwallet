package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.view.View
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

/** The width of a bubble's tail beside its body, as the design has it: 8 × 13.3 dp */
internal const val AGENT_BUBBLE_TAIL_WIDTH = 8

/** In dp */
internal const val AGENT_BUBBLE_RADIUS = 21f

/**
 * A message bubble with Telegram's tail at its bottom corner on the sender's side. A bubble that suggestions hang
 * from has no tail: it goes into the corner as they come and grows back out of it when they go ([tailProgress]).
 */
class AgentBubbleDrawable(
    private val isOutgoing: Boolean,
    private val hasActions: Boolean = false,
    isTailless: Boolean = false
) : Drawable() {

    private val paint = Paint().apply {
        color = if (isOutgoing) WColor.Tint.color else agentIncomingBubbleColor
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val tail = Path()
    private val body = Path()
    private val tailMatrix = Matrix()
    private val drawnTail = Path()

    /** How far the tail has grown out of the corner: 0 without a tail, 1 when it is whole */
    var tailProgress = if (isTailless) 0f else 1f
        set(value) {
            val clamped = value.coerceIn(0f, 1f)
            if (field == clamped) return
            field = clamped
            rebuildPaths(bounds.width().toFloat(), bounds.height().toFloat())
            invalidateSelf()
        }

    /**
     * Bounds the bubble keeps whatever its view sets, as while the skeleton's reveal draws it at a frame moving toward
     * its own; null lets the view set them again
     */
    var lockedBounds: Rect? = null
        set(value) {
            field = value?.let(::Rect)
            value?.let(::setBounds)
        }

    override fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        val locked = lockedBounds ?: return super.setBounds(left, top, right, bottom)
        super.setBounds(locked.left, locked.top, locked.right, locked.bottom)
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuildPaths(bounds.width().toFloat(), bounds.height().toFloat())
    }

    // Drawn with the tail on the right; [draw] mirrors it for the other side
    private fun rebuildPaths(width: Float, height: Float) {
        val radius = RADIUS.dp
        val bottomRadius = if (hasActions) ACTION_RADIUS.dp else radius
        val right = width - AGENT_BUBBLE_TAIL_WIDTH.dp
        // The tail's corner is square while the tail is out, and rounds as it withdraws
        val tailCornerRadius = bottomRadius * (1f - tailProgress)

        // Telegram's 6 × 10 tail, scaled to the design's size
        val tailUnit = TAIL_SCALE.dp
        tail.reset()
        tail.moveTo(right, height - 10f * tailUnit)
        tail.cubicTo(
            right,
            height - 6.786f * tailUnit,
            width - 4.235f * tailUnit,
            height - 2.321f * tailUnit,
            width - 0.706f * tailUnit,
            height - 1.429f * tailUnit
        )
        tail.lineTo(width, height - 1.429f * tailUnit)
        tail.cubicTo(
            width,
            height - 0.714f * tailUnit,
            width - 0.706f * tailUnit,
            height,
            width - 0.706f * tailUnit,
            height
        )
        tail.lineTo(right, height)
        tail.lineTo(right, height - 10f * tailUnit)
        tail.close()

        body.reset()
        body.moveTo(radius, 0f)
        body.lineTo(right - radius, 0f)
        body.cubicTo(
            right - radius + radius * CORNER_K,
            0f,
            right,
            radius - radius * CORNER_K,
            right,
            radius
        )
        body.lineTo(right, height - tailCornerRadius)
        if (tailCornerRadius > 0f) {
            body.cubicTo(
                right,
                height - tailCornerRadius + tailCornerRadius * CORNER_K,
                right - tailCornerRadius + tailCornerRadius * CORNER_K,
                height,
                right - tailCornerRadius,
                height
            )
        }
        body.lineTo(bottomRadius, height)
        body.cubicTo(
            bottomRadius - bottomRadius * CORNER_K,
            height,
            0f,
            height - bottomRadius + bottomRadius * CORNER_K,
            0f,
            height - bottomRadius
        )
        body.lineTo(0f, radius)
        body.cubicTo(0f, radius - radius * CORNER_K, radius - radius * CORNER_K, 0f, radius, 0f)
        body.close()

        // The growing tail starts at 40% of its size, raised into the corner, and fades in
        val scale = TAIL_START_SCALE + (1f - TAIL_START_SCALE) * tailProgress
        val rise = 10f * tailUnit * (1f - TAIL_START_SCALE) / 2f * (1f - tailProgress)
        tailMatrix.setScale(scale, scale, right, height)
        tailMatrix.postTranslate(0f, -rise)
        tail.transform(tailMatrix, drawnTail)
    }

    private val isMirrored: Boolean
        get() = isOutgoing == LocaleController.isRTL

    override fun draw(canvas: Canvas) {
        canvas.save()
        // The paths are built from the corner of the bounds, which needn't be the canvas's
        canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
        if (isMirrored) {
            canvas.translate(bounds.width().toFloat(), 0f)
            canvas.scale(-1f, 1f)
        }
        canvas.drawPath(body, paint)
        if (tailProgress > 0f) {
            val alpha = paint.alpha
            paint.alpha = (alpha * tailProgress).toInt()
            canvas.drawPath(drawnTail, paint)
            paint.alpha = alpha
        }
        canvas.restore()
    }

    val bubbleColor: Int
        get() = paint.color

    fun setBubbleColor(color: Int) {
        paint.color = color
        invalidateSelf()
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    /** The bubble's outline within its bounds, mirrored as it draws */
    fun buildOutlinePath(): Path {
        val path = Path(body)
        if (tailProgress > 0f) path.addPath(drawnTail)
        if (isMirrored) {
            path.transform(Matrix().apply { setScale(-1f, 1f, bounds.width() / 2f, 0f) })
        }
        return path
    }

    fun buildCutoutPath(view: View): Path {
        val location = view.getLocationInWindow()
        val w = view.width.toFloat()

        val combined = Path()
        combined.addPath(body)
        if (tailProgress > 0f) combined.addPath(drawnTail)

        val matrix = Matrix()
        if (isMirrored) {
            matrix.setScale(-1f, 1f, w / 2f, 0f)
        }
        matrix.postScale(0.995f, 0.995f, w / 2f, view.height / 2f)
        matrix.postTranslate(location.x.toFloat(), location.y.toFloat())
        combined.transform(matrix)
        return combined
    }

    private companion object {
        const val RADIUS = AGENT_BUBBLE_RADIUS
        const val ACTION_RADIUS = 8f
        const val TAIL_SCALE = AGENT_BUBBLE_TAIL_WIDTH / 6f
        const val TAIL_START_SCALE = 0.4f

        // Where the corner curves' control points sit along their tangents, as the design's corners have them
        const val CORNER_K = 0.62f
    }
}
