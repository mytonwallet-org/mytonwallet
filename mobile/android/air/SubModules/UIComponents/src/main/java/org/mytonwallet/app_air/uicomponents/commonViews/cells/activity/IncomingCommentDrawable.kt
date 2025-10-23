package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class IncomingCommentDrawable : Drawable(), ICommentDrawable {

    private val paint = Paint().apply {
        color = WColor.IncomingComment.color
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds

        canvas.save()

        if (LocaleController.isRTL) {
            canvas.translate(bounds.width().toFloat(), 0f)
            canvas.scale(-1f, 1f)
        }

        val path1 = Path().apply {
            moveTo(6f.dp, 10f.dp)
            cubicTo(
                6f.dp, 6.78571f.dp,
                4.23529f.dp, 2.32143f.dp,
                0.705882f.dp, 1.42857f.dp
            )
            lineTo(0f, 1.42857f.dp)
            cubicTo(
                0f, 0.714284f.dp,
                0.705882f.dp, 0f,
                0.705882f.dp, 0f
            )
            lineTo(6f.dp, 0f)
            lineTo(6f.dp, 10f.dp)
            close()
        }

        val path2 = Path().apply {
            moveTo(6f.dp, 0f)
            lineTo(bounds.width() - 18f.dp, 0f)
            cubicTo(
                bounds.width() - 8f.dp, 0f,
                bounds.width().toFloat(), 8f.dp,
                bounds.width().toFloat(), 18f.dp
            )
            lineTo(bounds.width().toFloat(), bounds.height().toFloat() - 18f.dp)
            cubicTo(
                bounds.width().toFloat(), bounds.height().toFloat() - 8.dp,
                bounds.width() - 8f.dp, bounds.height().toFloat(),
                bounds.width() - 18f.dp, bounds.height().toFloat()
            )
            lineTo(24f.dp, bounds.height().toFloat())
            cubicTo(
                14f.dp, bounds.height().toFloat(),
                6f.dp, bounds.height().toFloat() - 8.dp,
                6f.dp, bounds.height().toFloat() - 18f.dp
            )
            lineTo(6f.dp, 0f)
            close()
        }

        canvas.drawPath(path2, paint)
        canvas.drawPath(path1, paint)

        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    override fun setBubbleColor(bubbleColor: Int) {
        paint.color = bubbleColor
        invalidateSelf()
    }
}
