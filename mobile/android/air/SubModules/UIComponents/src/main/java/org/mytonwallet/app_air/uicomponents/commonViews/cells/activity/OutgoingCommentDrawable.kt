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

class OutgoingCommentDrawable : Drawable(), ICommentDrawable {

    private val paint = Paint().apply {
        color = WColor.OutgoingComment.color
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
            moveTo(bounds.width() - 6f.dp, bounds.height() - 10f.dp)
            cubicTo(
                bounds.width() - 6f.dp, bounds.height() - 6.78571f.dp,
                bounds.width() - 4.23529f.dp, bounds.height() - 2.32143f.dp,
                bounds.width() - 0.705882f.dp, bounds.height() - 1.42857f.dp
            )
            lineTo(bounds.width().toFloat(), bounds.height() - 1.42857f.dp)
            cubicTo(
                bounds.width().toFloat(), bounds.height() - 0.714284f.dp,
                bounds.width() - 0.705882f.dp, bounds.height().toFloat(),
                bounds.width() - 0.705882f.dp, bounds.height().toFloat()
            )
            lineTo(bounds.width() - 6f.dp, bounds.height().toFloat())
            lineTo(bounds.width() - 6f.dp, bounds.height() - 10f.dp)
            close()
        }

        val path2 = Path().apply {
            moveTo(bounds.width() - 6f.dp, bounds.height().toFloat())
            lineTo(18f.dp, bounds.height().toFloat())
            cubicTo(
                8f.dp, bounds.height().toFloat(),
                0f, bounds.height() - 8f.dp,
                0f, bounds.height() - 18f.dp
            )
            lineTo(0f, 18f.dp)
            cubicTo(
                0f, 8f.dp,
                8f.dp, 0f,
                18f.dp, 0f
            )
            lineTo(bounds.width() - 24f.dp, 0f)
            cubicTo(
                bounds.width() - 14f.dp, 0f,
                bounds.width() - 6f.dp, 8f.dp,
                bounds.width() - 6f.dp, 18f.dp
            )
            lineTo(bounds.width() - 6f.dp, bounds.height().toFloat())
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
