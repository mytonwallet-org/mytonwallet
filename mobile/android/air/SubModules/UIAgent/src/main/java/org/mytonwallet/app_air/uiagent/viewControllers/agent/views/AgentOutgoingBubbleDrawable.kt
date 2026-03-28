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
import org.mytonwallet.app_air.uicomponents.extensions.getLocationOnScreen
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

class AgentOutgoingBubbleDrawable : Drawable() {

    private val paint = Paint().apply {
        color = WColor.Tint.color
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
        val r = 20f.dp

        tail.reset()
        tail.moveTo(w - 6f.dp, h - 10f.dp)
        tail.cubicTo(
            w - 6f.dp, h - 6.786f.dp,
            w - 4.235f.dp, h - 2.321f.dp,
            w - 0.706f.dp, h - 1.429f.dp
        )
        tail.lineTo(w, h - 1.429f.dp)
        tail.cubicTo(w, h - 0.714f.dp, w - 0.706f.dp, h, w - 0.706f.dp, h)
        tail.lineTo(w - 6f.dp, h)
        tail.lineTo(w - 6f.dp, h - 10f.dp)
        tail.close()

        body.reset()
        body.moveTo(w - 6f.dp, h)
        body.lineTo(r, h)
        body.cubicTo(8f.dp, h, 0f, h - 8f.dp, 0f, h - r)
        body.lineTo(0f, r)
        body.cubicTo(0f, 8f.dp, 8f.dp, 0f, r, 0f)
        body.lineTo(w - 6f.dp - r, 0f)
        body.cubicTo(w - 6f.dp - 8f.dp, 0f, w - 6f.dp, 8f.dp, w - 6f.dp, r)
        body.lineTo(w - 6f.dp, h)
        body.close()
    }

    override fun draw(canvas: Canvas) {
        canvas.save()
        if (LocaleController.isRTL) {
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
        val location = view.getLocationOnScreen()
        val w = view.width.toFloat()

        val combined = Path()
        combined.addPath(body)
        combined.addPath(tail)

        val matrix = Matrix()
        if (LocaleController.isRTL) {
            matrix.setScale(-1f, 1f, w / 2f, 0f)
        }
        matrix.postScale(0.995f, 0.995f, w / 2f, view.height / 2f)
        matrix.postTranslate(location.x.toFloat(), location.y.toFloat())
        combined.transform(matrix)
        return combined
    }
}
