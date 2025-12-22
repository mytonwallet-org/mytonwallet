package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RoundRectShape
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewOutlineProvider
import android.view.animation.TranslateAnimation
import android.view.inputmethod.InputMethodManager
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.children
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
open class WView(
    context: Context,
    layoutParams: ViewGroup.LayoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
) :
    ConstraintLayout(context) {
    init {
        id = generateViewId()
        this.layoutParams = layoutParams
    }

    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (configured)
            return
        configured = true
        setupViews()
        didSetupViews()
    }

    open fun setupViews() {}

    open fun didSetupViews() {}

    fun constraintSet(): WConstraintSet {
        return WConstraintSet(this)
    }

    fun setConstraints(block: WConstraintSet.() -> Unit) {
        constraintSet().apply(block).layout()
    }

    var currentBackgroundColor: Int? = null
        private set
    private var borderColor: Int? = null
    fun animateBackgroundColor(
        newBackgroundColor: Int,
        radius: Float = 0f,
        newBorderColor: Int = Color.TRANSPARENT,
        borderWidth: Int = 0,
        duration: Long = AnimationConstants.QUICK_ANIMATION,
        onCompletion: (() -> Unit)? = null
    ) {
        val currentDrawable = this.background as? GradientDrawable

        if (!WGlobalStorage.getAreAnimationsActive() || duration == 0L) {
            val gradientDrawable = (currentDrawable ?: GradientDrawable()).apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = radius
                setColor(newBackgroundColor)
                setStroke(borderWidth, newBorderColor)
            }
            this.background = gradientDrawable
            currentBackgroundColor = newBackgroundColor
            onCompletion?.invoke()
            return
        }

        val prevBackgroundColor = currentBackgroundColor ?: Color.TRANSPARENT
        currentBackgroundColor = newBackgroundColor
        val currentStrokeColor = borderColor ?: Color.TRANSPARENT
        borderColor = newBorderColor

        val gradientDrawable = currentDrawable ?: GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(prevBackgroundColor)
            setStroke(borderWidth, currentStrokeColor)
        }
        this.background = gradientDrawable

        // Create ValueAnimators to animate the color change
        val backgroundColorAnimator =
            ValueAnimator.ofArgb(prevBackgroundColor, newBackgroundColor)
        val borderColorAnimator = ValueAnimator.ofArgb(currentStrokeColor, newBorderColor)

        backgroundColorAnimator.addUpdateListener { animator ->
            val animatedBackgroundColor = animator.animatedValue as Int
            gradientDrawable.setColor(animatedBackgroundColor)
        }

        borderColorAnimator.addUpdateListener { animator ->
            val animatedBorderColor = animator.animatedValue as Int
            gradientDrawable.setStroke(borderWidth, animatedBorderColor)
        }

        // On completion
        if (onCompletion != null) {
            backgroundColorAnimator.addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    onCompletion()
                }
            })
        }

        // Start the animations
        backgroundColorAnimator.duration = duration
        borderColorAnimator.duration = duration
        backgroundColorAnimator.start()
        borderColorAnimator.start()
    }

    @Deprecated("Use WRippleDrawable")
    fun addRippleEffect(rippleColor: Int, topRadius: Float = 0f, bottomRadius: Float? = null) {
        val mask = if (topRadius == 0f && bottomRadius == 0f)
            ShapeDrawable()
        else
            ViewHelpers.roundedShapeDrawable(topRadius, bottomRadius ?: topRadius)
        mask.paint.color = Color.WHITE

        val rippleDrawable = RippleDrawable(
            ColorStateList.valueOf(rippleColor),
            background,
            mask
        )

        background = rippleDrawable
    }

    open fun lockView() {
        isEnabled = false
        children.forEach {
            if (it is WView)
                it.lockView()
            else
                it.isEnabled = false
        }
    }

    open fun unlockView() {
        isEnabled = true
        children.forEach {
            if (it is WView)
                it.unlockView()
            else
                it.isEnabled = true
        }
    }

}

fun View.fadeOut(
    duration: Long = AnimationConstants.QUICK_ANIMATION,
    targetAlpha: Float = 0f,
    onCompletion: (() -> Unit)? = null
) {
    visibility = View.VISIBLE
    if (!WGlobalStorage.getAreAnimationsActive()) {
        alpha = targetAlpha
        onCompletion?.invoke()
        return
    }
    animate()
        .alpha(targetAlpha)
        .setDuration(duration)
        .withEndAction {
            onCompletion?.invoke()
        }
}

fun View.fadeIn(
    duration: Long = AnimationConstants.QUICK_ANIMATION,
    targetAlpha: Float = 1f,
    onCompletion: (() -> Unit)? = null
) {
    if (!WGlobalStorage.getAreAnimationsActive()) {
        alpha = targetAlpha
        onCompletion?.invoke()
        return
    }
    animate()
        .alpha(targetAlpha)
        .setDuration(duration)
        .withEndAction {
            onCompletion?.invoke()
        }
}

fun View.fadeOutObjectAnimator(): ObjectAnimator? {
    visibility = View.VISIBLE
    if (!WGlobalStorage.getAreAnimationsActive()) {
        alpha = 0f
        return null
    }
    return ObjectAnimator.ofFloat(this, "alpha", 1f, 0f);
}

fun View.fadeInObjectAnimator(): ObjectAnimator? {
    visibility = View.VISIBLE
    if (!WGlobalStorage.getAreAnimationsActive()) {
        alpha = 1f
        return null
    }
    return ObjectAnimator.ofFloat(this, "alpha", 0f, 1f);
}

fun View.setAlpha(
    targetAlpha: Float,
    animated: Boolean,
    duration: Long = AnimationConstants.VERY_QUICK_ANIMATION
) {
    if (!animated || !WGlobalStorage.getAreAnimationsActive()) {
        alpha = targetAlpha
        return
    }
    animate()
        .alpha(targetAlpha)
        .setDuration(duration)
        .start()
}

fun View.setBackgroundColor(color: Int, radius: Float, clipToBounds: Boolean = false) {
    background = ViewHelpers.roundedShapeDrawable(color, radius)

    if (clipToBounds) {
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                val left = 0
                val top = 0
                val right = view.width
                val bottom = view.height
                outline.setRoundRect(left, top, right, bottom, radius)
            }
        }
        clipToOutline = true
    }
}

fun View.setBackgroundColor(
    color: Int,
    topRadius: Float,
    bottomRadius: Float,
    clipToBounds: Boolean = false,
    strokeColor: Int? = null,
    strokeWidth: Int = 0
) {
    setBackgroundColor(
        color,
        topRadius,
        topRadius,
        bottomRadius,
        bottomRadius,
        clipToBounds,
        strokeColor,
        strokeWidth
    )
}

fun View.setBackgroundColor(
    color: Int,
    topLeftRadius: Float,
    topRightRadius: Float,
    bottomRightRadius: Float,
    bottomLeftRadius: Float,
    clipToBounds: Boolean = false,
    strokeColor: Int? = null,
    strokeWidth: Int = 0
) {
    val gradientDrawable = GradientDrawable()

    gradientDrawable.setColor(color)

    gradientDrawable.cornerRadii = floatArrayOf(
        topLeftRadius, topLeftRadius,
        topRightRadius, topRightRadius,
        bottomRightRadius, bottomRightRadius,
        bottomLeftRadius, bottomLeftRadius,
    )

    if (strokeColor != null && strokeWidth > 0) {
        gradientDrawable.setStroke(strokeWidth, strokeColor)
    }

    background = gradientDrawable

    if (clipToBounds) {
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val path = Path().apply {
                        addRoundRect(
                            0f, 0f, view.width.toFloat(), view.height.toFloat(),
                            floatArrayOf(
                                topLeftRadius, topLeftRadius,
                                topRightRadius, topRightRadius,
                                bottomRightRadius, bottomRightRadius,
                                bottomLeftRadius, bottomLeftRadius,
                            ),
                            Path.Direction.CW
                        )
                    }
                    outline.setPath(path)
                } else {
                    outline.setRoundRect(
                        0,
                        0,
                        view.width,
                        view.height,
                        maxOf(topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius)
                    )
                }
            }
        }
        clipToOutline = true
    }
}

fun View.setBackgroundColor(
    color: Int,
    topLeft: Float,
    topRight: Float,
    bottomRight: Float,
    bottomLeft: Float,
) {
    background =
        ViewHelpers.roundedShapeDrawable(color, topLeft, topRight, bottomRight, bottomLeft)
}

fun View.setBackgroundColor(color: Int, radius: Float, borderColor: Int, borderWidth: Float) {
    background =
        ViewHelpers.roundedBorderedShareDrawable(color, radius, borderColor, borderWidth)
}

fun View.setBackgroundColor(color: Int, topRadius: Float, bottomRadius: Float) {
    val shapeDrawable = ShapeDrawable()
    shapeDrawable.shape = RoundRectShape(
        floatArrayOf(
            topRadius,
            topRadius,
            topRadius,
            topRadius,
            bottomRadius,
            bottomRadius,
            bottomRadius,
            bottomRadius
        ),
        null,
        null
    )
    shapeDrawable.paint.color = color
    background = shapeDrawable
}

fun View.showKeyboard() {
    val imm = context.getSystemService(Activity.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT)
}

fun View.hideKeyboard() {
    val imm = context.getSystemService(Activity.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.hideSoftInputFromWindow(windowToken, 0)
    clearFocus()
}

fun View.shakeView(duration: Long = AnimationConstants.SUPER_QUICK_ANIMATION) {
    val shake = TranslateAnimation(
        0f, 10f,
        0f, 0f
    )
    shake.duration = duration
    shake.repeatCount = 5
    shake.repeatMode = TranslateAnimation.REVERSE
    startAnimation(shake)
}

fun View.pulseView(scale: Float = 1.2f, duration: Long = AnimationConstants.VERY_QUICK_ANIMATION) {
    val scaleUpX = ObjectAnimator.ofFloat(this, "scaleX", scaleX, scale)
    val scaleUpY = ObjectAnimator.ofFloat(this, "scaleY", scaleY, scale)
    val scaleDownX = ObjectAnimator.ofFloat(this, "scaleX", scale, 1f)
    val scaleDownY = ObjectAnimator.ofFloat(this, "scaleY", scale, 1f)

    scaleUpX.duration = duration / 2
    scaleUpY.duration = duration / 2
    scaleDownX.duration = duration / 2
    scaleDownY.duration = duration / 2

    val scaleUp = AnimatorSet().apply {
        playTogether(scaleUpX, scaleUpY)
    }

    val scaleDown = AnimatorSet().apply {
        playTogether(scaleDownX, scaleDownY)
    }

    AnimatorSet().apply {
        playSequentially(scaleUp, scaleDown)
        start()
    }
}

@Deprecated("Problem re-call inside updateTheme. Use WRippleDrawable")
fun View.addRippleEffect(rippleColor: Int, cornerRadius: Float) {
    background = ViewHelpers.roundedRippleDrawable(background, rippleColor, cornerRadius)
}

fun View.lockView() {
    isEnabled = false
    ((this as? ViewGroup)?.children)?.forEach {
        if (it is WView)
            it.lockView()
        else
            it.isEnabled = false
    }
}

fun View.unlockView() {
    isEnabled = true
    ((this as? ViewGroup)?.children)?.forEach {
        it.unlockView()
    }
}

fun View.animateHeight(newValue: Int) {
    if (measuredHeight == newValue)
        return
    ValueAnimator.ofInt(measuredHeight, newValue).apply {
        addUpdateListener { valueAnimator ->
            layoutParams = layoutParams.apply {
                height = valueAnimator.animatedValue as Int
            }
        }
        setDuration(AnimationConstants.QUICK_ANIMATION)
        start()
    }
}

fun View.frameAsRectF(padding: Float): RectF {
    val location = IntArray(2)
    getLocationOnScreen(location)
    return RectF(
        location[0].toFloat() - padding,
        location[1].toFloat() - padding,
        (location[0] + width).toFloat() + padding,
        (location[1] + height).toFloat() + padding
    )
}

@SuppressLint("NotifyDataSetChanged")
fun updateThemeForChildren(parentView: ViewGroup, onlyTintedViews: Boolean) {
    for (child in parentView.children) {
        if (child is WThemedView && (!onlyTintedViews || child.isTinted))
            child.updateTheme()
        if (child is ViewGroup && child !is WRecyclerView)
            updateThemeForChildren(child, onlyTintedViews)
        else if (child is WRecyclerView && !onlyTintedViews) {
            (child.adapter as? WRecyclerViewAdapter)?.updateTheme() ?: run {
                child.adapter?.notifyDataSetChanged()
            }
            // Note: Updating tinted RecyclerViews is handled per-case in view-controllers
        }
        if (child is WSegmentedController) {
            child.items.forEach {
                updateThemeForChildren(it.viewController.view, onlyTintedViews)
            }
        }
    }
}
