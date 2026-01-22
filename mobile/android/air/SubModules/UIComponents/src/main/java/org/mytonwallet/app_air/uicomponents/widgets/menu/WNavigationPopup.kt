package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.view.View.GONE
import android.view.View.VISIBLE
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
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
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

class WNavigationPopup(
    private val initialPopupView: WMenuPopupView,
    private val popupWidth: Int,
) : INavigationPopup {

    private val popupHost: WPopupHost? get() = PopupHelpers.popupHost

    private val roundRadius: Float = 20f.dp
    private val transitionXOffset: Float = 48f.dp

    private val isBlurSupported: Boolean
        get() = DevicePerformanceClassifier.isHighClass && WGlobalStorage.isBlurEnabled()

    private val contentContainerLayout = object : WFrameLayout(
        initialPopupView.context
    ), WThemedView {

        val blurryBackground: WBlurryBackgroundView by lazy {
            WBlurryBackgroundView(initialPopupView.context, null, 32f)
        }

        init {
            if (isBlurSupported) {
                addView(blurryBackground, LayoutParams(0, 0))
                popupHost?.windowView?.let { blurryBackground.setupWith(it) }
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
        }
    }.apply {
        elevation = 4f.dp
        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        addView(initialPopupView, FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT))
        if (isBlurSupported) {
            setRoundedOutline(roundRadius)
        }
        setOnClickListener {
            // do nothing, just to prevent click to parent
        }
    }

    private val rootContainerLayout: WFrameLayout = object : WFrameLayout(
        initialPopupView.context
    ), WThemedView {
        override fun updateTheme() {
            contentContainerLayout.updateTheme()
            popupViews.forEach { it.updateTheme() }
        }
    }.apply {
        val params = FrameLayout.LayoutParams(
            if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth,
            WRAP_CONTENT
        )
        addView(contentContainerLayout, params)
        setOnClickListener { dismiss() }
    }

    private val popupViews = mutableListOf(initialPopupView)
    private var onDismissListener: (() -> Unit)? = null
    private var isDismissed = false

    init {
        initialPopupView.popupWindow = this
    }

    fun setOnDismissListener(listener: (() -> Unit)?) {
        onDismissListener = listener
    }

    fun showAtLocation(x: Int, y: Int, initialHeight: Int = 0) {
        val popupHost = this.popupHost ?: return
        contentContainerLayout.apply {
            translationX = x.toFloat() - popupHost.paddingLeft
            translationY = y.toFloat() - popupHost.paddingTop
        }
        popupHost.addView(rootContainerLayout)
        initialPopupView.present(initialHeight)
        PopupHelpers.popupShown(this)
    }

    override fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean,
        onCompletion: (() -> Unit)?
    ) {
        val currentView = popupViews.last()
        currentView.lockView()

        nextPopupView.present(initialHeight = currentView.height)
        nextPopupView.alpha = 0f
        nextPopupView.translationX = transitionXOffset
        nextPopupView.lockView()

        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
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

    override fun dismiss() {
        if (isDismissed) {
            return
        }

        popupViews.last().apply {
            if (isDismissed) {
                removeFromParent()
                return
            }
            lockView()
            dismiss()
            PopupHelpers.popupDismissed(this@WNavigationPopup)
        }
    }

    private fun removeFromParent() {
        if (isDismissed) {
            return
        }
        isDismissed = true

        popupHost?.removeView(rootContainerLayout)
        onDismissListener?.invoke()
    }
}
