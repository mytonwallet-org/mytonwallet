package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.ValueAnimator
import android.view.View.GONE
import android.view.View.VISIBLE
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AccelerateInterpolator
import android.widget.FrameLayout
import android.widget.PopupWindow
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WPopupWindow(
    initialPopupView: WMenuPopupView,
    private val popupWidth: Int,
) : PopupWindow(
    FrameLayout(initialPopupView.context),
    if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth + 8.dp,
    WRAP_CONTENT,
    true
) {

    private val containerLayout = object : FrameLayout(initialPopupView.context), WThemedView {
        init {
            updateTheme()
        }

        override fun updateTheme() {
            setBackgroundColor(WColor.Background.color, 8f.dp, true)
        }
    }.apply {
        elevation = 2f.dp
        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        addView(initialPopupView, FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT))
    }

    private val popupViews = mutableListOf(initialPopupView)

    init {
        (contentView as FrameLayout).apply {
            val containerWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else MATCH_PARENT
            addView(
                containerLayout,
                FrameLayout.LayoutParams(containerWidth, MATCH_PARENT).apply {
                    topMargin = 12.dp
                    leftMargin = 4.dp
                    rightMargin = 4.dp
                    bottomMargin = 4.dp
                })
            setOnClickListener {
                dismiss()
            }
        }
    }

    fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        val currentView = popupViews.last()
        currentView.lockView()

        nextPopupView.present(initialHeight = currentView.height)
        nextPopupView.alpha = 0f
        nextPopupView.lockView()

        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        containerLayout.addView(
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
            nextPopupView.setBackgroundColor(WColor.Background.color)
            nextPopupView.alpha = 0f
            nextPopupView.translationX = 48f
            nextPopupView.animate()
                .alpha(1f)
                .translationX(0f)
                .setDuration(500)
                .setInterpolator(WInterpolator.emphasized)
                .withEndAction {
                    nextPopupView.background = null
                    onEnd()
                }.start()
        } else {
            onEnd()
        }
    }

    fun pop(
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        if (popupViews.size <= 1) {
            dismiss()
            return
        }

        val currentView = popupViews.last()
        val previousView = popupViews[popupViews.size - 2]

        previousView.unlockView()
        previousView.visibility = VISIBLE
        previousView.alpha = 1f
        previousView.translationX = 0f

        fun onEnd() {
            containerLayout.removeView(currentView)
            popupViews.removeAt(popupViews.size - 1)
            if (popupWidth != WRAP_CONTENT) {
                width = popupWidth + 8.dp
                update()
            }
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            currentView.setBackgroundColor(WColor.Background.color)
            currentView.post {
                currentView.animate()?.setDuration(AnimationConstants.NAV_POP)
                    ?.setInterpolator(AccelerateInterpolator())?.translationX(48f.dp)
                    ?.alpha(0f)?.withEndAction {
                        onEnd()
                    }
                ValueAnimator.ofInt(containerLayout.height, previousView.height).apply {
                    duration = AnimationConstants.NAV_POP
                    interpolator = AccelerateDecelerateInterpolator()

                    addUpdateListener { animator ->
                        val animatedValue = animator.animatedValue as Int
                        val params = containerLayout.layoutParams
                        params.height = animatedValue
                        containerLayout.layoutParams = params
                    }

                    start()
                }
            }
        } else {
            onEnd()
        }
    }

    override fun dismiss() {
        popupViews.last().apply {
            if (isDismissed) {
                super.dismiss()
                return
            }
            lockView()
            dismiss()
            PopupHelpers.popupDismissed(this@WPopupWindow)
        }
    }

}
