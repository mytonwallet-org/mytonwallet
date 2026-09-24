package org.mytonwallet.app_air.uicomponents.helpers

import android.animation.ValueAnimator
import android.view.View
import android.view.animation.DecelerateInterpolator
import androidx.constraintlayout.widget.Guideline
import androidx.core.view.updatePadding
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.updateLayoutParamsIfExists
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

// Keeps a bottom action area above the system bars / keyboard: guideline, corner view, scroll padding.
class BottomActionAreaController(
    private val viewController: WViewController,
    private val scrollView: WScrollView,
    private val contentView: View,
    private val cornerView: ReversedCornerViewUpsideDown,
    private val gradientSolidHeight: Int? = null,
    private val actionAreaHeight: () -> Int
) {
    val guideline = Guideline(viewController.context).apply {
        id = View.generateViewId()
    }

    private var systemOffset: Int? = null
    private var systemOffsetAnimator: ValueAnimator? = null
    private var isAreaVisible = true
    private var extraSize = 0

    private val systemBarsBottom: Int
        get() = viewController.navigationController?.getSystemBars()?.bottom ?: 0

    private val targetSystemOffset: Int
        get() = max(systemBarsBottom, viewController.navigationController?.imeInsetBottom ?: 0)

    private val currentSystemOffset: Int
        get() = systemOffset ?: targetSystemOffset

    val cornerViewDiff: Int
        get() = getCornerViewHeight(true) - getCornerViewHeight(false)

    fun getCornerViewHeight(areaVisible: Boolean = true): Int {
        if (areaVisible && gradientSolidHeight != null && cornerView.isGradientMode) {
            return currentSystemOffset + actionAreaHeight() - ViewConstants.GAP.dp +
                cornerView.extraTopHeight
        }
        val area = if (areaVisible) actionAreaHeight() else ViewConstants.GAP.dp
        return currentSystemOffset + area + ViewConstants.BLOCK_RADIUS.dp.roundToInt()
    }

    fun update(areaVisible: Boolean, extraSize: Int = 0) {
        isAreaVisible = areaVisible
        this.extraSize = extraSize
        if (gradientSolidHeight != null) {
            cornerView.gradientFadeEndY = if (areaVisible) {
                (currentSystemOffset + gradientSolidHeight).toFloat()
            } else {
                currentSystemOffset - systemBarsBottom / 2f
            }
        }
        cornerView.updateLayoutParamsIfExists {
            height = getCornerViewHeight(areaVisible) + extraSize
        }
        val bottomMargin =
            currentSystemOffset + (if (areaVisible) actionAreaHeight() else 0) + extraSize
        contentView.updatePadding(bottom = bottomMargin)
        scrollView.bottomObscuredInset = bottomMargin
    }

    fun insetsUpdated() {
        val from = systemOffset
        val target = targetSystemOffset
        systemOffsetAnimator?.cancel()
        if (from == null || from == target || !WGlobalStorage.getAreAnimationsActive()) {
            applySystemOffset(target)
            return
        }
        systemOffsetAnimator = ValueAnimator.ofInt(from, target).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { applySystemOffset(it.animatedValue as Int) }
            start()
        }
    }

    fun onDestroy() {
        systemOffsetAnimator?.cancel()
    }

    private fun applySystemOffset(offset: Int) {
        systemOffset = offset
        update(isAreaVisible, extraSize)
        guideline.setGuidelineEnd(offset)
    }
}
