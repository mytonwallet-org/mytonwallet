package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import androidx.core.graphics.PathParser
import kotlin.math.min

/** The Agent mark, a spinning top's silhouette, as the design draws it in a 48 × 48 box */
internal object AgentMark {
    val path: Path by lazy { PathParser.createPathFromPathData(PATH_DATA) }

    /** The silhouette's bounds in the design box */
    val bounds: RectF by lazy { RectF().also { path.computeBounds(it, true) } }

    /** The tip the top spins on, as fractions of the silhouette's bounds */
    const val TIP_X = 0.429f
    const val TIP_Y = 1f

    /**
     * Fits the silhouette, rather than its design box, centered in a [width] × [height] area at [fraction] of it.
     * Returns the silhouette's frame in that area.
     */
    fun fit(matrix: Matrix, width: Float, height: Float, fraction: Float = 1f): RectF {
        val bounds = bounds
        val scale = min(width / bounds.width(), height / bounds.height()) * fraction
        val frameWidth = bounds.width() * scale
        val frameHeight = bounds.height() * scale
        val left = (width - frameWidth) / 2
        val top = (height - frameHeight) / 2
        matrix.setTranslate(-bounds.left, -bounds.top)
        matrix.postScale(scale, scale)
        matrix.postTranslate(left, top)
        return RectF(left, top, left + frameWidth, top + frameHeight)
    }

    private const val PATH_DATA =
        "M27.9273,5.8302 C28.4264,5.9363 28.8487,6.1382 29.1794,6.4497 C29.5101,6.7615 " +
            "29.7215,7.1559 29.8436,7.5993 C30.0812,8.4625 29.9938,9.5676 29.7647,10.8073 " +
            "C29.0665,14.5722 28.6137,17.8016 28.6385,20.5677 C28.6634,23.3287 29.1653,25.5925 " +
            "30.3414,27.455 L30.6961,27.9657 C32.5716,30.4252 35.8393,31.4942 39.099,32.3316 " +
            "L39.542,32.4737 C39.9628,32.6341 40.3147,32.8538 40.57,33.1235 C40.9164,33.4895 " +
            "41.1033,33.9781 40.9508,34.4884 C40.8024,34.9991 40.4395,35.3491 39.963,35.5284 " +
            "C39.5048,35.7005 38.9523,35.7149 38.3683,35.6187 L38.3645,35.6179 C33.1702,34.7339 " +
            "29.8284,35.0041 27.4432,36.2617 L27.4409,36.2632 C26.3923,36.8121 25.4761,37.9784 " +
            "24.5352,39.2617 C24.0783,39.8849 23.6164,40.533 23.1513,41.0941 C22.6875,41.6537 " +
            "22.1891,42.1649 21.6438,42.5029 L21.6415,42.5044 C21.1682,42.7939 20.6129,42.9026 " +
            "20.0717,42.7877 C19.5304,42.6727 19.0658,42.3471 18.751,41.89 L18.7495,41.8877 " +
            "C18.3891,41.3573 18.1434,40.6875 17.9473,39.988 C17.7506,39.2864 17.5922,38.5061 " +
            "17.4283,37.7511 C17.0907,36.1958 16.7265,34.7575 15.9916,33.8296 C14.3241,31.7102 " +
            "11.3805,30.1024 6.2748,28.797 C5.7018,28.6473 5.1996,28.409 4.8509,28.0651 " +
            "C4.4885,27.7074 4.2993,27.2402 4.3715,26.7132 L4.4121,26.5222 C4.5349,26.0951 " +
            "4.8678,25.7905 5.2745,25.6212 C5.7318,25.4312 6.311,25.3907 6.9405,25.4961 " +
            "C10.4794,26.0941 14.1343,26.4538 16.9244,24.6032 C18.7566,23.3801 20.1356,21.5161 " +
            "21.2814,19.0039 C22.4292,16.487 23.329,13.3526 24.2225,9.6292 C24.5174,8.4035 " +
            "24.8889,7.3589 25.4572,6.6669 C25.7491,6.3116 26.1025,6.0371 26.5315,5.8869 " +
            "C26.9604,5.7369 27.4282,5.7241 27.9273,5.8302 Z"
}

/** The Agent mark filled with a color, its silhouette centered in the drawable's bounds */
internal class AgentMarkDrawable(color: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
    private val matrix = Matrix()
    private val fitted = Path()

    var shader: Shader?
        get() = paint.shader
        set(value) {
            paint.shader = value
            invalidateSelf()
        }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        AgentMark.fit(matrix, bounds.width().toFloat(), bounds.height().toFloat())
        matrix.postTranslate(bounds.left.toFloat(), bounds.top.toFloat())
        AgentMark.path.transform(matrix, fitted)
    }

    override fun draw(canvas: Canvas) {
        canvas.drawPath(fitted, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
