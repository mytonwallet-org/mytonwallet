package org.mytonwallet.uihome.tabs

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.graphics.Color
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor

internal class MinimizedBrowserPresenter(private val host: Host) {
    interface Host {
        val container: ViewGroup
        val availableHeight: Int
        val bottomInset: Int
        val animationsEnabled: Boolean
        fun canMinimize(nav: WNavigationController): Boolean
        fun detach(nav: WNavigationController)
        fun attach(nav: WNavigationController)
        fun destroy(nav: WNavigationController)
        fun render()
        fun restack()
    }
    private var isDisposed = false
    private var animator: ValueAnimator? = null
    private var transition: Any? = null
    private val context get() = host.container.context
    val hasNavigation get() = minimizedNav != null

    fun bringToFront() {
        minimizedNavGlass?.bringToFront()
        minimizedNav?.bringToFront()
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        cancelTransition()
        minimizedNav?.let { release(it, restore = false) }
    }

    private fun release(nav: WNavigationController, restore: Boolean) {
        if (minimizedNav !== nav) return
        minimizedNav = null
        onMaximizeProgress = null
        height = 0f
        detachMinimizedShadow(nav)
        host.render()
        if (restore) {
            host.container.removeView(nav)
            host.attach(nav)
        } else {
            host.destroy(nav)
        }
    }

    private fun cancelTransition() {
        transition = null
        val previous = animator
        animator = null
        previous?.removeAllListeners()
        previous?.removeAllUpdateListeners()
        previous?.cancel()
    }

    private fun animate(
        animated: Boolean,
        duration: Long,
        interpolator: TimeInterpolator,
        update: (Float) -> Unit,
        onStart: () -> Unit = {},
        complete: () -> Unit = {}
    ) {
        cancelTransition()
        val next = Any()
        transition = next
        onStart()
        if (transition !== next) return
        if (!animated) {
            update(1f)
            if (transition === next) {
                transition = null
                complete()
            }
            return
        }
        val nextAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            this.interpolator = interpolator
            addUpdateListener {
                if (transition === next) update(it.animatedFraction)
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (transition !== next) return
                    transition = null
                    animator = null
                    complete()
                }
            })
        }
        animator = nextAnimator
        nextAnimator.start()
    }

    private var minimizedNav: WNavigationController? = null
    var height = 0f
        private set
    private var cornerRadius = 0f
    private var minimizedNavGlass: WGlassView? = null

    private fun attachMinimizedShadow(nav: WNavigationController) {
        nav.elevation = 0f
        if (minimizedNavGlass == null) {
            minimizedNavGlass = WGlassView(context).also {
                it.alpha = 0f
                it.glassPadding = WGlassView.GLASS_PADDING_DP.dp
                it.setProvider(GlassProviders.shadowOnly())
                host.container.addView(
                    it,
                    ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
                minimizedNav?.bringToFront()
            }
        }
    }

    private fun detachMinimizedShadow(nav: WNavigationController?) {
        minimizedNavGlass?.let { host.container.removeView(it) }
        minimizedNavGlass = null
        nav?.elevation = 0f
    }

    private fun applyMinimizedShadowProgress(
        nav: WNavigationController,
        fraction: Float,
        width: Int,
        height: Int,
        radius: Float
    ) {
        val shadow = minimizedNavGlass
        if (shadow != null) {
            shadow.alpha = fraction
            val l = nav.left + nav.translationX
            val t = nav.top + nav.translationY
            shadow.setTargetRect(l, t, l + width, t + height, radius)
        } else {
            nav.elevation = fraction * 1.5f.dp
        }
    }

    private var onMaximizeProgress: ((progress: Float) -> Unit)? = null
    fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit
    ) {
        if (isDisposed || !host.canMinimize(nav)) {
            onMaximizeProgress(1f)
            return
        }
        cancelTransition()
        minimizedNav?.let { release(it, restore = false) }
        this.onMaximizeProgress = onMaximizeProgress
        minimizedNav = nav
        host.detach(nav)
        attachMinimizedShadow(nav)
        host.container.addView(nav)
        host.restack()
        val initialHeight = nav.height
        val finalHeight = 48.dp
        val initialWidth = nav.width
        val finalWidth = initialWidth - 20.dp
        val finalTranslationX = 10.dp.toFloat()
        val containerHeight = host.availableHeight
        val finalY = containerHeight -
            host.bottomInset -
            finalHeight - 4.dp
        val finalMinimizedNavHeight = finalHeight + 8f.dp
        height = 0f
        host.render()

        fun onUpdate(animatedFraction: Float) {
            height = animatedFraction * finalMinimizedNavHeight
            host.render()
            val navY = animatedFraction * finalY

            nav.translationY = navY
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            nav.layoutParams = nav.layoutParams.apply {
                height = animatedHeight
                width = animatedWidth
            }
            nav.translationX = animatedFraction * finalTranslationX
            val radius = 24.dp * animatedFraction
            cornerRadius = radius
            nav.setBackgroundColor(Color.TRANSPARENT, radius, true)
            applyMinimizedShadowProgress(
                nav,
                animatedFraction,
                animatedWidth,
                animatedHeight,
                radius
            )
        }

        animate(
            host.animationsEnabled,
            AnimationConstants.VERY_VERY_QUICK_ANIMATION,
            AccelerateDecelerateInterpolator(),
            update = { fraction ->
                onUpdate(fraction)
                onProgress(fraction)
            }
        )
    }

    fun maximize(animated: Boolean) {
        if (isDisposed) return
        val nav = minimizedNav ?: return
        cancelTransition()
        val initialHeight = nav.height
        val finalHeight = host.container.height
        val initialWidth = nav.width
        val finalWidth = host.container.width
        val initialY = nav.y
        val initialAlpha = nav.alpha
        val initialRadius = cornerRadius
        val initialMinimizedNavHeight = height
        val minimizedNavTranslationX = nav.translationX

        fun onUpdate(animatedFraction: Float) {
            height = (1 - animatedFraction) * initialMinimizedNavHeight
            host.render()
            val topY = (1 - animatedFraction) * initialY
            nav.translationY = topY
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            nav.layoutParams = nav.layoutParams.apply {
                height = animatedHeight
                width = animatedWidth
            }
            nav.translationX = (1 - animatedFraction) * minimizedNavTranslationX
            nav.alpha = initialAlpha + (1 - initialAlpha) * animatedFraction
            val radius = initialRadius * (1 - animatedFraction)
            cornerRadius = radius
            nav.setBackgroundColor(Color.TRANSPARENT, radius, radius > 0f)
            applyMinimizedShadowProgress(
                nav,
                1f - animatedFraction,
                animatedWidth,
                animatedHeight,
                radius
            )
        }

        animate(
            animated,
            AnimationConstants.VERY_VERY_QUICK_ANIMATION,
            AccelerateDecelerateInterpolator(),
            update = { fraction ->
                onUpdate(fraction)
                onMaximizeProgress?.invoke(fraction)
            },
            onStart = { onMaximizeProgress?.invoke(0f) },
            complete = { release(nav, restore = true) }
        )
    }

    fun dismissMinimized(animated: Boolean) {
        if (isDisposed) return
        val nav = minimizedNav ?: return
        cancelTransition()
        val initialMinimizedNavHeight = height
        val initialAlpha = nav.alpha

        fun onUpdate(animatedFraction: Float) {
            height = (1 - animatedFraction) * initialMinimizedNavHeight
            host.render()
            val fadedAlpha = initialAlpha * (1 - animatedFraction)
            nav.alpha = fadedAlpha
            minimizedNavGlass?.alpha = fadedAlpha
        }

        animate(
            animated,
            AnimationConstants.VERY_QUICK_ANIMATION,
            DecelerateInterpolator(),
            update = ::onUpdate,
            complete = { release(nav, restore = false) }
        )
    }
}
