package org.mytonwallet.app_air.uicomponents.extensions

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.createBitmap
import androidx.core.graphics.drawable.toDrawable
import org.mytonwallet.app_air.uicomponents.AnimationConstants

fun Drawable.animateTintColor(
    fromColor: Int,
    toColor: Int,
    duration: Long = AnimationConstants.QUICK_ANIMATION
) {
    ValueAnimator.ofFloat(0f, 1f).apply {
        this.duration = duration
        this.interpolator = AccelerateDecelerateInterpolator()
        addUpdateListener { animator ->
            val fraction = animator.animatedValue as Float
            val color = ColorUtils.blendARGB(fromColor, toColor, fraction)
            setTint(color)
        }
        start()
    }
}

fun Drawable.resize(
    context: Context,
    widthPx: Int,
    heightPx: Int,
    tintColor: Int? = null
): BitmapDrawable {
    val bitmap = createBitmap(widthPx, heightPx)
    val canvas = Canvas(bitmap)

    setBounds(0, 0, widthPx, heightPx)
    tintColor?.let { setTint(it) }
    draw(canvas)

    return bitmap.toDrawable(context.resources)
}

fun Drawable.withGradient(colors: IntArray): Drawable {
    val bitmap = createBitmap(intrinsicWidth, intrinsicHeight)

    val canvas = Canvas(bitmap)

    setBounds(0, 0, canvas.width, canvas.height)
    draw(canvas)

    val paint = Paint()
    paint.shader = LinearGradient(
        0f, 0f, canvas.width.toFloat(), 0f,
        colors,
        null,
        Shader.TileMode.CLAMP
    )
    paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
    canvas.drawRect(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat(), paint)

    return bitmap.toDrawable(Resources.getSystem())
}

fun Drawable.setSizeBounds(widthPx: Int, heightPx: Int) {
    setBounds(0, 0, widthPx, heightPx)
}
