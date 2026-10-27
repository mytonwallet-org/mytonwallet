@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer

import android.animation.AnimatorSet
import android.annotation.SuppressLint
import android.graphics.Canvas
import android.os.Build
import android.view.MotionEvent
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
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

@SuppressLint("ViewConstructor")
class WSensitiveDataContainer<V : View>(val contentView: V, private val maskConfig: MaskConfig) :
    WFrameLayout(contentView.context),
    WProtectedView,
    WalletCore.EventObserver {

    var onProtectionChanged: ((Boolean) -> Unit)? = null

    var isSensitiveData = true
        set(value) {
            if (field == value) return
            field = value
            updateProtectedView(false)
        }

    data class HeroConfig(
        val widthDp: Float,
        val heightDp: Float,
        val globalReveal: Boolean = false,
        val softwareSnapshot: Boolean = false
    )

    private var heroLayer: HeroSensitiveLayer? = null
    private var heroObserving = false
    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent == WalletEvent.CardEffectsChanged &&
            Build.VERSION.SDK_INT >= 34
        ) {
            heroLayer?.policyChanged()
        }
    }
    fun settleHero() {
        removeCallbacks(clearHeroOrigin)
        clearHeroOrigin.run()
        if (Build.VERSION.SDK_INT >= 34) {
            heroLayer?.setHidden(
                isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn(),
                false
            )
            heroLayer?.stop()
        }
    }
    private var heroOriginX = 0f
    private var heroOriginY = 0f
    private val clearHeroOrigin = Runnable {
        heroOriginX = 0f
        heroOriginY = 0f
    }

    fun setHeroActive(active: Boolean) {
        if (Build.VERSION.SDK_INT >= 34) heroLayer?.active = active
    }

    fun setHeroTouch(x: Float?, y: Float?) {
        if (Build.VERSION.SDK_INT < 34) return
        val density = resources.displayMetrics.density
        heroLayer?.finger = if (x != null && y != null) {
            Pair(((x - width / 2f) / density).toDouble(), ((y - height / 2f) / density).toDouble())
        } else {
            null
        }
    }

    fun revealHeroLocally(): Boolean {
        if (Build.VERSION.SDK_INT < 34 || heroLayer?.concealed != true) return false
        heroLayer?.revealLocally(heroOriginX, heroOriginY)
        return true
    }

    fun setHeroColors(primary: Int, secondary: Int = primary) {
        if (Build.VERSION.SDK_INT >= 34) heroLayer?.setColors(primary, secondary)
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (Build.VERSION.SDK_INT >= 34 && heroLayer?.cloudActive == true) {
            heroLayer?.draw(canvas)
        } else {
            super.dispatchDraw(canvas)
        }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (Build.VERSION.SDK_INT < 34 || heroLayer == null) {
            return super.dispatchTouchEvent(event)
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                removeCallbacks(clearHeroOrigin)
                val density = resources.displayMetrics.density
                heroOriginX = (event.x - width / 2f) / density
                heroOriginY = (event.y - height / 2f) / density
            }

            MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(clearHeroOrigin)
                clearHeroOrigin.run()
            }
        }
        val handled = super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP) {
            // Child views may post their click; retain the point until that click is dispatched.
            post(clearHeroOrigin)
        }
        return handled
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (Build.VERSION.SDK_INT >= 34 && heroLayer?.concealed == true) return true
        return super.onInterceptTouchEvent(event)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (Build.VERSION.SDK_INT >= 34 && heroLayer?.cloudActive == true) {
            val fixed = (heroLayer!!.config.widthDp * resources.displayMetrics.density).toInt()
            setMeasuredDimension(resolveSize(fixed, widthMeasureSpec), measuredHeight)
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (Build.VERSION.SDK_INT >= 34) heroLayer?.layout()
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(clearHeroOrigin)
        clearHeroOrigin.run()
        if (heroObserving) {
            WalletCore.unregisterObserver(this)
            heroObserving = false
        }
        if (Build.VERSION.SDK_INT >= 34) heroLayer?.stop()
        super.onDetachedFromWindow()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (Build.VERSION.SDK_INT >= 34) {
            if (hasWindowFocus) heroLayer?.schedule() else heroLayer?.stop()
        }
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (Build.VERSION.SDK_INT >= 34) {
            if (isShown) heroLayer?.schedule() else heroLayer?.stop()
        }
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
        val protectContentLayoutSize: Boolean = true,
        val hero: HeroConfig? = null
    )

    val maskView = SensitiveDataMaskView(context).apply {
        cols = maskConfig.cols
        rows = maskConfig.rows
        cellSize = maskConfig.cellSize
        cornerRadius = maskConfig.cornerRadius.toFloat()
        skin = maskConfig.skin
        initMask()
        setOnClickListener {
            if (WGlobalStorage.getIsSensitiveDataProtectionOn()) {
                WGlobalStorage.toggleSensitiveDataHidden()
            }
        }
    }

    private enum class MaskState { HIDDEN, ANIMATING_IN, SHOWING, ANIMATING_OUT }

    private var maskState: MaskState = MaskState.HIDDEN

    init {
        addView(
            contentView,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = maskConfig.gravity
            }
        )
        addView(
            maskView,
            LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                gravity = maskConfig.gravity
                marginEnd = maskConfig.endMargin
            }
        )

        if (Build.VERSION.SDK_INT >= 34 && maskConfig.hero != null) {
            heroLayer = HeroSensitiveLayer(this, contentView, maskConfig.hero) {
                maskView.foregroundColor ?: WColor.PrimaryText.color
            }
            clipChildren = false
            clipToPadding = false
            setOnClickListener {
                val layer = heroLayer ?: return@setOnClickListener
                if (!layer.concealed) return@setOnClickListener
                if (maskConfig.hero.globalReveal) {
                    WGlobalStorage.toggleSensitiveDataHidden()
                } else {
                    layer.revealLocally(heroOriginX, heroOriginY)
                }
            }
        }
        maskView.visibility = GONE
        if (heroLayer == null && isSensitiveData &&
            WGlobalStorage.getIsSensitiveDataProtectionOn()
        ) {
            contentView.visibility = INVISIBLE
            // Awaits for view to be attached to the parent and then `updateProtectedView` will be called
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (Build.VERSION.SDK_INT >= 34 && heroLayer != null && !heroObserving) {
            WalletCore.registerObserver(this)
            heroObserving = true
        }
        if (maskConfig.protectContentLayoutSize &&
            WGlobalStorage.getIsSensitiveDataProtectionOn()
        ) {
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
        onProtectionChanged?.invoke(
            isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn()
        )
        if (Build.VERSION.SDK_INT >= 34 && heroLayer != null) {
            contentView.visibility = VISIBLE
            contentView.alpha = 1f
            maskView.visibility = GONE
            val hidden = isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn()
            heroLayer?.setHidden(hidden, animated, heroOriginX, heroOriginY)
            contentDescription = if (hidden) LocaleController.getString("Tap to reveal") else null
            return
        }
        if (isSensitiveData && WGlobalStorage.getIsSensitiveDataProtectionOn()) {
            if (maskState == MaskState.SHOWING || maskState == MaskState.ANIMATING_IN) return
            if (maskConfig.protectContentLayoutSize &&
                (layoutParams == null || contentView.height == 0)
            ) {
                // View is not attached to the window yet, wait...
                return
            }
            maskView.initMask()
            maskState = if (animated) MaskState.ANIMATING_IN else MaskState.SHOWING
            maskView.setIntersecting(true)
            maskView.visibility = VISIBLE
            if (_maskPivotYPercent > 0f) {
                maskView.post {
                    setMaskPivotYPercent(_maskPivotYPercent)
                }
            }
            if (animated) {
                val animations = listOf(
                    contentView.fadeOutObjectAnimator(),
                    maskView.fadeInObjectAnimator()
                )
                AnimatorSet().apply {
                    duration = AnimationConstants.VERY_QUICK_ANIMATION
                    playTogether(animations)
                    doOnEnd {
                        if (maskState == MaskState.ANIMATING_IN) {
                            maskState = MaskState.SHOWING
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
            if (maskState == MaskState.HIDDEN || maskState == MaskState.ANIMATING_OUT) return
            maskState = if (animated) MaskState.ANIMATING_OUT else MaskState.HIDDEN
            if (maskConfig.protectContentLayoutSize) {
                layoutParams = layoutParams.apply {
                    width = WRAP_CONTENT
                    height = WRAP_CONTENT
                }
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
                        if (maskState == MaskState.ANIMATING_OUT) {
                            maskState = MaskState.HIDDEN
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
        if (maskState == MaskState.HIDDEN) return
        val changed = maskView.initMask()
        if (!changed) return
        if (maskConfig.protectContentLayoutSize) setMaskedLayoutParams()
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
