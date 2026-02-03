package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.animation.Animator
import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell.TopRounding
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

@SuppressLint("ViewConstructor")
class WAutoCompleteAddressHeaderCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, 40.dp)),
    IAutoCompleteAddressItemCell, WThemedView {

    private val animationDuration = AnimationConstants.QUICK_ANIMATION
    private var animator: Animator? = null

    private var animationState: AutoCompleteAddressItem.AnimationState =
        AutoCompleteAddressItem.AnimationState.IDLE


    private val label: HeaderCell by lazy {
        HeaderCell(context, 20f).apply {
            titleLabel.setStyle(14f, WFont.DemiBold)
        }
    }

    init {
        super.setupViews()

        addView(label, LayoutParams(MATCH_PARENT, 40.dp))
        setConstraints {
            toStart(label)
            toEnd(label)
            toTop(label)
        }

        updateTheme()
    }

    override fun configure(
        item: AutoCompleteAddressItem,
        onTap: () -> Unit,
        changeAnimationFinishListener: (() -> Unit),
        onLongClick: (() -> Unit)?
    ) {
        label.configure(
            title = item.title,
            titleColor = WColor.Tint,
            topRounding = TopRounding.FIRST_ITEM
        )
        if (layoutParams.height != 40.dp) {
            updateLayoutParams { height = 40.dp }
        }

        updateTheme()

        val stateChanged = this.animationState != item.animationState
        this.animationState = item.animationState

        if (!stateChanged) {
            return
        }
        when (animationState) {
            AutoCompleteAddressItem.AnimationState.IDLE -> {
                animator?.cancel()
                animator = null
                resetCollapseProgress()
            }

            AutoCompleteAddressItem.AnimationState.DISAPPEARING -> animateCollapse(
                changeAnimationFinishListener
            )

            AutoCompleteAddressItem.AnimationState.CORNER_ROUNDING -> {}
        }
    }

    private fun animateCollapse(finishListener: () -> Unit) {
        animator = animatorSet {
            duration(animationDuration)
            interpolator(CubicBezierInterpolator.EASE_OUT)
            together {
                intValues(height, 0) {
                    onUpdate { h -> updateLayoutParams { height = h } }
                }
                viewProperty(label.titleLabel) {
                    duration(animationDuration / 4)
                    translationY(-(10f).dp)
                    alpha(0f)
                    scaleX(0.95f)
                    scaleY(0.95f)
                }
            }
            onEnd { finishListener() }
        }.also { it.start() }
    }

    private fun resetCollapseProgress() {
        label.titleLabel.alpha = 1f
        label.titleLabel.scaleX = 1f
        label.titleLabel.scaleY = 1f
        label.titleLabel.translationY = 0f
    }

    override fun hasActiveAnimation(): Boolean {
        return false
    }

    override fun updateTheme() {
        label.updateTheme()
    }
}
