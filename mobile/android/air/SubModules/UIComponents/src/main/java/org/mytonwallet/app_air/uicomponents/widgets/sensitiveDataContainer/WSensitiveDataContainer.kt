package org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer

import android.animation.AnimatorSet
import android.annotation.SuppressLint
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.animation.doOnEnd
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeInObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.fadeOutObjectAnimator
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class WSensitiveDataContainer<V : View>(
    val contentView: V,
    private val maskConfig: MaskConfig
) : WFrameLayout(contentView.context), WProtectedView {

    var isSensitiveData = true
        set(value) {
            field = value
            updateProtectedView(false)
        }

    data class MaskConfig(
        val cols: Int,
        val rows: Int,
        val gravity: Int,
        val cornerRadius: Int = 8.dp,
        val cellSize: Int = 8.dp,
        val endMargin: Int = 0,
        val skin: SensitiveDataMaskView.Skin? = null,
        // `protectContentLayoutSize` is used to hide real content size, from the view hierarchy.
        //  may cause ui glitches if the content size is not correct in the first frame,
        //  so pass it false unless it's necessary; to prevent any issues or un-necessary processes.
        val protectContentLayoutSize: Boolean = true
    )

    val maskView = SensitiveDataMaskView(context).apply {
        cols = maskConfig.cols
        rows = maskConfig.rows
        cellSize = maskConfig.cellSize
        cornerRadius = maskConfig.cornerRadius.toFloat()
        skin = maskConfig.skin
        initMask()
        setOnClickListener {
            if (WGlobalStorage.getIsSensitiveDataProtectionOn())
                WGlobalStorage.toggleSensitiveDataHidden()
        }
    }

    private var isShowingMask: Boolean = false

    init {
        addView(contentView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = maskConfig.gravity
        })
        addView(maskView, LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
            gravity = maskConfig.gravity
            marginEnd = maskConfig.endMargin
        })

        maskView.visibility = GONE
        if (isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn()) {
            contentView.visibility = INVISIBLE
            // Awaits for view to be attached to the parent and then `updateProtectedView` will be called
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (maskConfig.protectContentLayoutSize && WGlobalStorage.getIsSensitiveDataProtectionOn()) {
            contentView.post {
                updateProtectedView(false)
            }
        } else {
            updateProtectedView(false)
        }
    }

    override fun updateProtectedView() {
        updateProtectedView(true)
    }

    fun updateProtectedView(animated: Boolean) {
        if (isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn()) {
            if (isShowingMask)
                return
            if (maskConfig.protectContentLayoutSize && (layoutParams == null || contentView.height == 0)) {
                // View is not attached to the window yet, wait...
                return
            }
            maskView.initMask()
            isShowingMask = true
            maskView.setIntersecting(true)
            maskView.visibility = VISIBLE
            if (_maskPivotYPercent > 0f)
                maskView.post {
                    setMaskPivotYPercent(_maskPivotYPercent)
                }
            if (animated) {
                val animations = listOf(
                    contentView.fadeOutObjectAnimator(),
                    maskView.fadeInObjectAnimator(),
                )
                AnimatorSet().apply {
                    duration = AnimationConstants.VERY_QUICK_ANIMATION
                    playTogether(animations)
                    doOnEnd {
                        if (isShowingMask) {
                            hideContent()
                        }
                    }
                    start()
                }
            } else {
                hideContent()
                maskView.alpha = 1f
            }
        } else {
            contentView.visibility = VISIBLE
            if (!isShowingMask)
                return
            isShowingMask = false
            if (maskConfig.protectContentLayoutSize)
                layoutParams = layoutParams.apply {
                    width = WRAP_CONTENT
                    height = WRAP_CONTENT
                }
            if (animated) {
                val animations = listOf(
                    contentView.fadeInObjectAnimator(),
                    maskView.fadeOutObjectAnimator()
                )
                AnimatorSet().apply {
                    duration = AnimationConstants.VERY_QUICK_ANIMATION
                    playTogether(animations)
                    doOnEnd {
                        if (!isShowingMask) {
                            maskView.setIntersecting(false)
                            maskView.visibility = GONE
                        }
                    }
                    start()
                }
            } else {
                contentView.alpha = 1f
                maskView.visibility = GONE
                maskView.setIntersecting(false)
            }
        }
    }

    fun setMaskCols(cols: Int) {
        maskView.cols = cols
        if (!isShowingMask)
            return
        val changed = maskView.initMask()
        if (!changed)
            return
        if (maskConfig.protectContentLayoutSize)
            setMaskedLayoutParams()
        requestLayout()
    }

    private var _maskPivotYPercent = 0f
    fun setMaskPivotYPercent(yPercent: Float) {
        _maskPivotYPercent = yPercent
        maskView.pivotX = maskView.width / 2f
        maskView.pivotY = maskView.height.toFloat()
    }

    fun setMaskScale(scale: Float) {
        maskView.scaleX = scale
        maskView.scaleY = scale
    }

    private fun hideContent() {
        if (maskConfig.protectContentLayoutSize) {
            setMaskedLayoutParams()
            contentView.visibility = GONE
        } else {
            contentView.visibility = INVISIBLE
        }
    }

    private fun setMaskedLayoutParams() {
        layoutParams = layoutParams.apply {
            width = maskView.calculatedWidth
            height = this@WSensitiveDataContainer.height
        }
    }
}
