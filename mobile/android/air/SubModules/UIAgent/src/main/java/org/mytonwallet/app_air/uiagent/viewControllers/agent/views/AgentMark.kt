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
    const val TIP_X = 0.427f
    const val TIP_Y = 0.998f

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
        "M20.9714,42.9249 C20.3761,42.9056 19.7459,42.7284 19.3497,42.2609 C17.779,40.4078 " +
            "18.135,35.8634 15.4832,33.1684 C14.8554,32.5304 13.7768,31.5764 12.981,31.1843 " +
            "C11.3855,30.3981 5.6069,29.1549 5.625,26.7701 C5.6443,24.2355 11.6534,25.0133 " +
            "13.1737,24.9361 C13.7302,24.9079 14.6948,24.7162 15.2338,24.5567 C16.6433,24.1396 " +
            "18.6172,22.6204 19.5599,21.4935 C21.5859,19.0714 23.1407,14.4387 23.9803,11.3876 " +
            "C24.3835,9.9224 24.7871,7.8424 25.5745,6.5622 C25.9811,5.9011 26.5548,5.3977 " +
            "27.3669,5.3965 C28.4389,5.3949 29.1754,5.923 29.4812,6.9585 C29.9389,8.5082 " +
            "29.2416,11.8675 29.0774,13.5837 C28.7979,16.5054 28.6599,19.7795 29.2704,22.6638 " +
            "C30.9983,30.8265 40.4442,29.5855 40.455,33.1387 C40.4633,35.8721 33.5044,34.8566 " +
            "31.9053,34.9061 C31.4909,34.9189 30.4215,35.2021 30.0053,35.3412 C28.5212,35.8372 " +
            "27.2322,36.554 26.1497,37.7069 C24.9957,38.9359 22.5676,42.9767 20.9714,42.9249 Z"
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
