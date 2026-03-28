package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.graphics.Canvas
import android.graphics.Path
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.View.GONE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.core.graphics.withSave
import androidx.core.view.children
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WCutoutDrawable
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import kotlin.math.roundToInt

class WNavigationPopup(
    private val initialPopupView: WMenuPopupView,
    private val popupWidth: Int,
    private val windowBackgroundStyle: WMenuPopup.BackgroundStyle,
    private val backdropStyle: WMenuPopup.BackdropStyle
) : INavigationPopup {
    companion object {
        private const val BACKDROP_BLUR_RADIUS = 14f
    }

    private val popupHost: WPopupHost? get() = PopupHelpers.popupHost

    private val roundRadius: Float = 20f.dp
    private val transitionXOffset: Float = 48f.dp

    private val isBlurSupported: Boolean
        get() = WGlobalStorage.isBlurEnabled()
    private val shouldUseTransparentBackdrop: Boolean
        get() = backdropStyle is WMenuPopup.BackdropStyle.Transparent
    private val shouldUseDimBackdrop: Boolean
        get() = !shouldUseTransparentBackdrop
    private val shouldUseBlurBackdrop: Boolean
        get() = isBlurSupported && backdropStyle is WMenuPopup.BackdropStyle.BlurDimmed

    private val contentContainerLayout = object : WFrameLayout(
        initialPopupView.context
    ), WThemedView {

        val blurryBackground: WBlurryBackgroundView by lazy {
            WBlurryBackgroundView(initialPopupView.context, null, 25f)
        }

        init {
            if (isBlurSupported) {
                addView(blurryBackground, LayoutParams(0, 0))
                val blurRootView = popupHost?.windowView?.children
                    ?.lastOrNull { child ->
                        child is ViewGroup &&
                            child !is JSWebViewBridge &&
                            child !is WPopupHost
                    } as? ViewGroup

                blurRootView?.let { viewGroup ->
                    blurryBackground.setupWith(viewGroup)
                }
            }
            updateTheme()
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            if (isBlurSupported) {
                // with stable size blur works better while animation
                val height = popupViews.maxOfOrNull { it.finalHeight } ?: measuredHeight
                blurryBackground.measure(measuredWidth.exactly, height.exactly)
            }
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            super.onLayout(changed, left, top, right, bottom)
            val contentAreaBounds = popupHost?.getContentAreaBounds() ?: return
            if (!changed) {
                return
            }
            // Fit popup to safe bounds
            val displayLeft = left + translationX
            val displayTop = top + translationY
            val displayRight = right + translationX
            val displayBottom = bottom + translationY

            var dx = 0f
            var dy = 0f

            if (displayTop < contentAreaBounds.top) {
                dy += (contentAreaBounds.top - displayTop)
            }
            if (displayLeft < contentAreaBounds.left) {
                dx += (contentAreaBounds.left - displayLeft)
            }

            if (displayBottom + dy > contentAreaBounds.bottom) {
                dy -= (displayBottom + dy - contentAreaBounds.bottom)
            }
            if (displayRight + dx > contentAreaBounds.right) {
                dx -= (displayRight + dx - contentAreaBounds.right)
            }

            translationX += dx
            translationY += dy
        }

        override fun updateTheme() {
            if (isBlurSupported) {
                blurryBackground.setOverlayColor(WColor.Background, 204)
            } else {
                setBackgroundColor(WColor.Background.color, roundRadius, true)
            }
            updateShadows()
        }

        fun updateShadows() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                outlineAmbientShadowColor = WColor.PopupAmbientShadow.color
                outlineSpotShadowColor = WColor.PopupSpotShadow.color
            }
        }
    }.apply {
        updateShadows()
        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        addView(initialPopupView, FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT))
        if (isBlurSupported) {
            setRoundedOutline(roundRadius)
        }
        setOnClickListener {
            // do nothing, just to prevent click to parent
        }
    }

    private var windowBackgroundDrawable: Drawable? = null
    private var blurCutoutPath: Path? = null
    private val blurVisiblePath = Path()
    private val windowBlurBackground: WBlurryBackgroundView by lazy {
        WBlurryBackgroundView(initialPopupView.context, null, BACKDROP_BLUR_RADIUS)
    }
    private val blurBackdropContainer = object : WFrameLayout(initialPopupView.context) {
        override fun dispatchDraw(canvas: Canvas) {
            val cutoutPath = blurCutoutPath
            if (cutoutPath == null) {
                super.dispatchDraw(canvas)
                return
            }

            blurVisiblePath.reset()
            blurVisiblePath.addRect(
                0f,
                0f,
                width.toFloat(),
                height.toFloat(),
                Path.Direction.CW
            )
            if (!blurVisiblePath.op(cutoutPath, Path.Op.DIFFERENCE)) {
                super.dispatchDraw(canvas)
                return
            }

            canvas.withSave {
                clipPath(blurVisiblePath)
                super.dispatchDraw(this)
            }
        }
    }.apply {
        addView(windowBlurBackground, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private var isBlurBackdropAttached = false

    private fun getBlurRootView(host: WPopupHost): ViewGroup? {
        return host.windowView?.children
            ?.lastOrNull { child ->
                child is ViewGroup &&
                    child !is JSWebViewBridge &&
                    child !is WPopupHost
            } as? ViewGroup ?: (host.windowView as? ViewGroup)
    }

    private fun configureBlurBackdrop() {
        windowBlurBackground.post {
            windowBlurBackground.setBlurEnabled(isBlurSupported)
            windowBlurBackground.setBlurRadius(BACKDROP_BLUR_RADIUS)
            windowBlurBackground.setOverlayColor(WColor.Background, 0)
            windowBlurBackground.resumeBlurring()
            windowBlurBackground.invalidate()
        }
    }

    private fun ensureBlurBackdropAttached(host: WPopupHost) {
        if (!shouldUseBlurBackdrop || isBlurBackdropAttached) {
            return
        }

        getBlurRootView(host)?.let { viewGroup ->
            windowBlurBackground.setupWith(viewGroup)
        }

        if (windowBlurBackground.parent is ViewGroup) {
            (windowBlurBackground.parent as ViewGroup).removeView(windowBlurBackground)
        }
        if (blurBackdropContainer.parent is ViewGroup) {
            (blurBackdropContainer.parent as ViewGroup).removeView(blurBackdropContainer)
        }
        if (windowBlurBackground.parent !== blurBackdropContainer) {
            blurBackdropContainer.addView(
                windowBlurBackground,
                FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
        }

        host.addView(blurBackdropContainer, 0, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        isBlurBackdropAttached = true
    }

    private fun updateBackdropProgress(progress: Float) {
        if (shouldUseDimBackdrop) {
            windowBackgroundDrawable?.alpha = (255 * progress).roundToInt()
        } else {
            windowBackgroundDrawable?.alpha = 0
        }
        if (shouldUseBlurBackdrop && isBlurBackdropAttached) {
            blurBackdropContainer.alpha = progress
        }
    }

    private val rootContainerLayout: WFrameLayout = object : WFrameLayout(
        initialPopupView.context
    ), WThemedView {
        override fun updateTheme() {
            contentContainerLayout.updateTheme()
            popupViews.forEach { it.updateTheme() }
            if (shouldUseDimBackdrop) {
                (windowBackgroundDrawable as? WCutoutDrawable)?.color = WColor.PopupWindow.color
            }
            if (shouldUseBlurBackdrop) {
                configureBlurBackdrop()
            }
        }
    }.apply {
        val params = FrameLayout.LayoutParams(
            if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth,
            WRAP_CONTENT
        )
        if (windowBackgroundStyle is WMenuPopup.BackgroundStyle.Cutout) {
            blurCutoutPath = if (shouldUseBlurBackdrop) windowBackgroundStyle.cutoutPath else null
            if (shouldUseDimBackdrop) {
                background = WCutoutDrawable().apply {
                    color = WColor.PopupWindow.color
                    cutoutPath = windowBackgroundStyle.cutoutPath
                    windowBackgroundDrawable = this
                }
            } else {
                background = null
                windowBackgroundDrawable = null
            }
        } else {
            blurCutoutPath = null
            windowBackgroundDrawable = null
        }
        addView(contentContainerLayout, params)
        setOnClickListener { dismiss() }
    }

    private val popupViews = mutableListOf(initialPopupView)
    private var onDismissListener: (() -> Unit)? = null
    private var displayProgressListener: ((progress: Float) -> Unit)? = null
    private var isDismissed = false

    init {
        initialPopupView.popupWindow = this
    }

    fun setOnDismissListener(listener: (() -> Unit)?) {
        onDismissListener = listener
    }

    fun setDisplayProgressListener(listener: ((progress: Float) -> Unit)?) {
        displayProgressListener = listener
    }

    fun showAtLocation(
        x: Int, y: Int, initialHeight: Int = 0, fromTop: Boolean = true
    ) {
        val popupHost = this.popupHost ?: return
        ensureBlurBackdropAttached(popupHost)
        contentContainerLayout.apply {
            translationX = x.toFloat() - popupHost.paddingLeft
            translationY = y.toFloat() - popupHost.paddingTop
            val elevationValue = if (!shouldUseDimBackdrop ||
                windowBackgroundStyle is WMenuPopup.BackgroundStyle.Transparent
            ) {
                4f
            } else {
                2f
            }
            elevation = elevationValue.dp
        }
        popupHost.addView(rootContainerLayout)
        if (shouldUseBlurBackdrop) {
            configureBlurBackdrop()
            blurBackdropContainer.alpha = 0f
        }
        updateBackdropProgress(0f)
        val interpolator = LinearInterpolator()
        initialPopupView.present(initialHeight, fromTop) { animationFraction ->
            val interpolated = interpolator.getInterpolation(animationFraction)
            updateBackdropProgress(interpolated)
            displayProgressListener?.invoke(animationFraction)
        }
        PopupHelpers.popupShown(this)
    }

    override fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean,
        onCompletion: (() -> Unit)?
    ) {
        val currentView = popupViews.last()
        currentView.lockView()

        nextPopupView.present(initialHeight = currentView.height, fromTop = true)
        nextPopupView.alpha = 0f
        nextPopupView.translationX = transitionXOffset
        nextPopupView.lockView()

        val layoutWidth = if (popupWidth == WRAP_CONTENT) contentContainerLayout.width else popupWidth
        contentContainerLayout.addView(
            nextPopupView,
            FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT)
        )
        popupViews.add(nextPopupView)

        fun onEnd() {
            currentView.visibility = GONE
            nextPopupView.alpha = 1f
            nextPopupView.translationX = 0f
            nextPopupView.unlockView()
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            animatorSet {
                together {
                    viewProperty(nextPopupView) {
                        alpha(1f)
                        translationX(0f)
                        duration(AnimationConstants.NAV_PUSH)
                        interpolator(WInterpolator.emphasized)
                    }
                    viewProperty(currentView) {
                        alpha(0f)
                        translationX(-transitionXOffset)
                        duration(AnimationConstants.NAV_PUSH / 2)
                        interpolator(WInterpolator.emphasized)
                    }
                }
                onEnd { onEnd() }
            }.start()
        } else {
            onEnd()
        }
    }

    override fun pop(
        animated: Boolean,
        onCompletion: (() -> Unit)?
    ) {
        if (popupViews.size <= 1) {
            dismiss()
            return
        }

        val currentView = popupViews.last()
        val previousView = popupViews[popupViews.size - 2]

        with(previousView) {
            unlockView()
            visibility = VISIBLE
            alpha = 0f
            translationX = -transitionXOffset
        }

        fun onEnd() {
            with(previousView) {
                alpha = 1f
                translationX = 0f
            }
            contentContainerLayout.removeView(currentView)
            popupViews.removeAt(popupViews.size - 1)
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            currentView.post {
                animatorSet {
                    together {
                        viewProperty(currentView) {
                            alpha(0f)
                            translationX(transitionXOffset)
                            duration(AnimationConstants.NAV_POP / 2)
                            interpolator(WInterpolator.emphasized)
                        }
                        viewProperty(previousView) {
                            alpha(1f)
                            translationX(0f)
                            duration(AnimationConstants.NAV_POP)
                            interpolator(WInterpolator.emphasized)
                        }
                        intValues(contentContainerLayout.height, previousView.height) {
                            interpolator(AccelerateDecelerateInterpolator())
                            duration(AnimationConstants.NAV_POP)
                            onUpdate { animatedValue ->
                                contentContainerLayout.updateLayoutParams {
                                    height = animatedValue
                                }
                            }
                        }
                    }
                    onEnd { onEnd() }
                }.start()
            }
        } else {
            onEnd()
        }
    }

    override fun onBackPressed() {
        pop(animated = true)
    }

    override fun dismiss() {
        if (isDismissed) {
            return
        }
        popupViews.last().apply {
            PopupHelpers.popupDismissed(this@WNavigationPopup)
            if (isDismissed) {
                removeFromParent()
                return
            }
            lockView()
            val interpolator = LinearInterpolator()
            dismiss { animationFraction ->
                val reversed = 1 - animationFraction
                val reversedInterpolated = interpolator.getInterpolation(reversed)
                updateBackdropProgress(reversedInterpolated)
                displayProgressListener?.invoke(reversedInterpolated)
            }
            PopupHelpers.popupDismissed(this@WNavigationPopup)
        }
    }

    private fun removeFromParent() {
        if (isDismissed) {
            return
        }
        isDismissed = true
        PopupHelpers.popupDismissed(this@WNavigationPopup)

        (rootContainerLayout.parent as? ViewGroup)?.removeView(rootContainerLayout)
        if (isBlurBackdropAttached) {
            windowBlurBackground.pauseBlurring()
            (blurBackdropContainer.parent as? ViewGroup)?.removeView(blurBackdropContainer)
            isBlurBackdropAttached = false
        }
        onDismissListener?.invoke()
    }
}
