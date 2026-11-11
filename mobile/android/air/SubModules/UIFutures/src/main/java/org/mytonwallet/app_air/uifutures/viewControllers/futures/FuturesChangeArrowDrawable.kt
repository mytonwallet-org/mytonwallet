package org.mytonwallet.app_air.uifutures.viewControllers.futures

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.drawable.Drawable
import androidx.core.graphics.PathParser
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/** The arrow between a previous and a new amount, fading from secondary to primary text. */
internal class FuturesChangeArrowDrawable : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()

    override fun getIntrinsicWidth() = WIDTH.dp

    override fun getIntrinsicHeight() = HEIGHT.dp

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return
        path.set(SOURCE_PATH)
        path.transform(
            Matrix().apply {
                setScale(bounds.width() / VIEWPORT_WIDTH, bounds.height() / VIEWPORT_HEIGHT)
                // The arrow points toward the reading direction's end
                if (LocaleController.isRTL) postScale(-1f, 1f, bounds.width() / 2f, 0f)
                postTranslate(bounds.left.toFloat(), bounds.top.toFloat())
            }
        )
        val start = WColor.SecondaryText.color
        val end = WColor.PrimaryText.color
        paint.shader = LinearGradient(
            bounds.left.toFloat(),
            0f,
            bounds.right.toFloat(),
            0f,
            if (LocaleController.isRTL) end else start,
            if (LocaleController.isRTL) start else end,
            Shader.TileMode.CLAMP
        )
        canvas.drawPath(path, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.TRANSLUCENT

    private companion object {
        const val WIDTH = 15
        const val HEIGHT = 8
        const val VIEWPORT_WIDTH = 15f
        const val VIEWPORT_HEIGHT = 8f

        // Change.svg
        val SOURCE_PATH: Path = PathParser.createPathFromPathData(
            "M12.176 3.00814V2.97614L9.21605 0.00014019H10.832L14.496 3.68014L10.832 " +
                "7.32814H9.21605L12.176 4.36814V4.33614H4.69089e-05V3.00814H12.176Z"
        )
    }
}
