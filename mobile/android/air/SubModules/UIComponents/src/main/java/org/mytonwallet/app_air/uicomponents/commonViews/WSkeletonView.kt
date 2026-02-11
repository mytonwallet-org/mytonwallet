package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

@SuppressLint("ViewConstructor")
class SkeletonView(
    context: Context,
    val isVertical: Boolean = true,
    val forcedLight: Boolean = false,
) : View(context), WThemedView {

    private var gradientPaint: Paint = Paint()
    private var gradientColors: IntArray = intArrayOf()
    private var animator: ValueAnimator? = null

    var isAnimating: Boolean = false

    private val myLocation: Vec2i = vec2i()
    private val location: Vec2i = vec2i()

    init {
        id = generateViewId()
        isFocusable = false
        visibility = INVISIBLE
        updateTheme()
    }

    private val topCornerRadius = ViewConstants.BLOCK_RADIUS.dp
    private var maskViews = emptyList<View>()
    private var maskCornerRadius: HashMap<Int, Float>? = null
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        // To properly calculate coordinates when SkeletonView is not rooted to 0,0 of the screen
        getLocationOnScreen(myLocation)

        canvas.save()
        for ((index, view) in maskViews.withIndex()) {
            view.getLocationOnScreen(location)

            if (location.x == 0 && location.y == 0)
                continue

            val left = location.x.toFloat() - myLocation.x
            val top = location.y.toFloat() - myLocation.y

            val right = left + view.width
            val bottom = top + view.height

            val itemRadius = maskCornerRadius?.get(index)
            if (index == 0 || itemRadius != null) {
                val path = Path().apply {
                    addRoundRect(
                        left,
                        top,
                        right,
                        bottom,
                        floatArrayOf(
                            itemRadius ?: topCornerRadius,
                            itemRadius ?: topCornerRadius,
                            itemRadius ?: topCornerRadius,
                            itemRadius ?: topCornerRadius,
                            itemRadius ?: 0f,
                            itemRadius ?: 0f,
                            itemRadius ?: 0f,
                            itemRadius ?: 0f
                        ),
                        Path.Direction.CW
                    )
                }
                canvas.drawPath(path, gradientPaint)
            } else {
                canvas.drawRect(left, top, right, bottom, gradientPaint)
            }
        }
        canvas.restore()
    }

    fun startAnimating() {
        if (isAnimating) return

        visibility = VISIBLE
        isAnimating = true

        val animValue = if (isVertical) height else width.coerceAtLeast(height)
        animator =
            ValueAnimator.ofFloat(0.2f * -animValue, 1.2f * animValue).apply {
                duration = 2000L
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener { animation ->
                    val animatedValue = animation.animatedValue as Float
                    if (isVertical)
                        gradientPaint.shader = LinearGradient(
                            0f, animatedValue, 0f, animatedValue + height.toFloat(),
                            gradientColors, floatArrayOf(0.0f, 0.1f, 0.2f),
                            Shader.TileMode.CLAMP
                        )
                    else
                        gradientPaint.shader = LinearGradient(
                            animatedValue,
                            animatedValue,
                            animatedValue + width.toFloat(),
                            animatedValue + height.toFloat(),
                            gradientColors,
                            floatArrayOf(0.0f, 0.1f, 0.2f),
                            Shader.TileMode.CLAMP
                        )
                    invalidate()
                }
                start()
            }
    }

    fun stopAnimating() {
        if (!isAnimating) return

        isAnimating = false
        visibility = GONE
        animator?.cancel()
        animator = null
    }

    fun applyMask(views: List<View>, radius: HashMap<Int, Float>? = null) {
        maskViews = views
        maskCornerRadius = radius
    }

    override fun updateTheme() {
        gradientColors = if (!forcedLight && ThemeManager.isDark)
            intArrayOf(0x00000000, WColor.Background.color, 0x00000000)
        else
            intArrayOf(0x00FFFFFF, 0x44FFFFFF, 0x00FFFFFF)
    }

    fun onDestroy() {
        stopAnimating()
        maskViews = emptyList()
        maskCornerRadius = HashMap()
    }
}
