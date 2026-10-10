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
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

class AgentBubbleDrawable(
    private val isOutgoing: Boolean,
    private val hasActions: Boolean = false
) : Drawable() {

    private val paint = Paint().apply {
        color = if (isOutgoing) WColor.Tint.color else WColor.SecondaryBackground.color
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val tail = Path()
    private val body = Path()

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuildPaths(bounds.width().toFloat(), bounds.height().toFloat())
    }

    private fun rebuildPaths(w: Float, h: Float) {
        val r = if (isOutgoing) 20f.dp else 21f.dp
        val bottomRadius = if (hasActions) 8f.dp else r
        val bottomControl = if (hasActions) 3.2f.dp else 8f.dp

        tail.reset()
        tail.moveTo(w - 6f.dp, h - 10f.dp)
        tail.cubicTo(
            w - 6f.dp,
            h - 6.786f.dp,
            w - 4.235f.dp,
            h - 2.321f.dp,
            w - 0.706f.dp,
            h - 1.429f.dp
        )
        tail.lineTo(w, h - 1.429f.dp)
        tail.cubicTo(w, h - 0.714f.dp, w - 0.706f.dp, h, w - 0.706f.dp, h)
        tail.lineTo(w - 6f.dp, h)
        tail.lineTo(w - 6f.dp, h - 10f.dp)
        tail.close()

        body.reset()
        body.moveTo(w - 6f.dp, h)
        body.lineTo(bottomRadius, h)
        body.cubicTo(bottomControl, h, 0f, h - bottomControl, 0f, h - bottomRadius)
        body.lineTo(0f, r)
        body.cubicTo(0f, 8f.dp, 8f.dp, 0f, r, 0f)
        body.lineTo(w - 6f.dp - r, 0f)
        body.cubicTo(w - 6f.dp - 8f.dp, 0f, w - 6f.dp, 8f.dp, w - 6f.dp, r)
        body.lineTo(w - 6f.dp, h)
        body.close()
    }

    private val isMirrored: Boolean
        get() = isOutgoing == LocaleController.isRTL

    override fun draw(canvas: Canvas) {
        canvas.save()
        if (isMirrored) {
            canvas.translate(bounds.width().toFloat(), 0f)
            canvas.scale(-1f, 1f)
        }

        canvas.drawPath(body, paint)
        canvas.drawPath(tail, paint)
        canvas.restore()
    }

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

    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    fun buildCutoutPath(view: View): Path {
        val location = view.getLocationInWindow()
        val w = view.width.toFloat()

        val combined = Path()
        combined.addPath(body)
        combined.addPath(tail)

        val matrix = Matrix()
        if (isMirrored) {
            matrix.setScale(-1f, 1f, w / 2f, 0f)
        }
        matrix.postScale(0.995f, 0.995f, w / 2f, view.height / 2f)
        matrix.postTranslate(location.x.toFloat(), location.y.toFloat())
        combined.transform(matrix)
        return combined
    }
}
